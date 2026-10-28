import Foundation
import Network

/// Watches the OpenCode app/service server for session events over SSE.
///
/// Sessions that live in the OpenCode desktop app / shared service run on a
/// local HTTP server whose API is Basic-auth'd with the key in
/// `~/.config/opencode/service.json`. Pluto finds the server on its own,
/// authenticates, then follows `GET /api/event` — no plugin needed there.
/// CLI/TUI sessions expose no server at all and are covered by the plugin.
@MainActor
final class OpenCodeTap: ObservableObject {
    static let shared = OpenCodeTap()

    @Published private(set) var connected = false
    @Published private(set) var lastEventAt: Date?
    @Published private(set) var watchedPort: UInt16?
    /// SSE frames received — surfaced in /health to confirm the tap is alive.
    @Published private(set) var eventsReceived = 0

    private var stream: NWConnection?
    private var probeConn: NWConnection?
    private var restartTask: Task<Void, Never>?
    private var seedTask: Task<Void, Never>?
    private var buffer = ""
    private static let ioTimeoutSec: UInt64 = 8

    func start() {
        guard restartTask == nil else { return }
        restartTask = Task { [weak self] in
            var delay: UInt64 = 3
            while !Task.isCancelled {
                await self?.discoverAndConnect()
                if Task.isCancelled { break }
                if self?.connected == true { continue }
                try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
                delay = min(delay * 2, 60)
            }
        }
    }

    func stop() {
        restartTask?.cancel()
        restartTask = nil
        seedTask?.cancel()
        seedTask = nil
        shutdownStream()
    }

    private func shutdownStream() {
        if let s = stream { s.cancel() }
        stream = nil
        connected = false
        watchedPort = nil
    }

    // MARK: - Discovery

    private struct Candidate {
        let port: UInt16
        let probeCommand: String?
    }

    private func candidates() -> [Candidate] {
        var list: [Candidate] = []

        // 1. Listening sockets owned by an opencode binary (lsof -F output).
        let data = run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-F", "-a"])
        if let text = String(data: data, encoding: .utf8) {
            var currentPID: pid_t?
            var currentCommand: String = ""
            for line in text.split(separator: "\n") {
                let l = String(line)
                if l.hasPrefix("p") {
                    currentPID = pid_t(l.dropFirst())
                    currentCommand = pidCommand(currentPID ?? 0)
                } else if l.hasPrefix("n") {
                    let addr = String(l.dropFirst())
                    let parts = addr.split(separator: ":")
                    guard parts.count >= 2 else { continue }
                    let host = String(parts[0])
                    let portString = parts.count > 2 ? String(parts[2]) : String(parts[1])
                    if host == "127.0.0.1", let port = UInt16(portString),
                       currentCommand.hasSuffix("opencode") {
                        list.append(Candidate(port: port, probeCommand: currentCommand))
                    }
                }
            }
        }

        // 2. Well-known fallbacks (in case lsof is missing or silent).
        list.append(Candidate(port: 4096, probeCommand: nil))
        if let ps = String(data: run("/bin/ps", ["-axww", "-o", "args="]), encoding: .utf8) {
            for line in ps.split(separator: "\n") where line.lowercased().contains("opencode") {
                for token in line.split(separator: " ") where token.hasPrefix("--port=") {
                    if let p = UInt16(token.dropFirst("--port=".count)) {
                        list.append(Candidate(port: p, probeCommand: nil))
                    }
                }
            }
        }

        var seen = Set<UInt16>()
        return list.filter { seen.insert($0.port).inserted }
    }

    private func pidCommand(_ pid: pid_t) -> String {
        let data = run("/bin/ps", ["-p", String(pid), "-o", "comm="])
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
    }

    private func run(_ path: String, _ argv: [String]) -> Data {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = argv
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
        } catch {
            return Data()
        }
        let d = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return d
    }

    private func servicePassword() -> String? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/opencode/service.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pw = json["password"] as? String, !pw.isEmpty else { return nil }
        return pw
    }

    // MARK: - Connect

    private func discoverAndConnect() async {
        shutdownStream()
        let password = servicePassword()

        for candidate in candidates() {
            if Task.isCancelled { return }

            for useAuth in [false, true] {
                if Task.isCancelled { return }
                guard !useAuth || password != nil else { continue }
                let up: (String, String)? = useAuth ? ("opencode", password ?? "") : nil
                guard await probeServer(port: candidate.port, basic: up) else { continue }
                await openStream(port: candidate.port, basic: up)
                if connected { return }
            }
        }
    }

    private static nonisolated func basicHeader(_ up: (String, String)) -> String {
        let raw = Data("\(up.0):\(up.1)".utf8).base64EncodedString()
        return "Authorization: Basic \(raw)"
    }
    /// Single-shot GET /api/config. True when OpenCode answers with its JSON
    /// (not the SPA fallback, not another service).
    private func probeServer(port: UInt16, basic: (String, String)?) async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            let c = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
            self.probeConn = c
            // Box the flag in a class so it's safely capturable across Sendable closures.
            final class Flag { var value = false }
            let settled = Flag()

            @Sendable func finish(_ ok: Bool) {
                guard !settled.value else { return }
                settled.value = true
                c.cancel()
                cont.resume(returning: ok)
            }

            c.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    var req = "GET /api/config HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n"
                    if let up = basic {
                        req += Self.basicHeader(up) + "\r\n"
                    }
                    req += "\r\n"
                    c.send(content: req.data(using: .utf8), completion: .contentProcessed { _ in })
                case .failed, .cancelled:
                    finish(false)
                default:
                    break
                }
            }
            c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                if let data, !data.isEmpty, error == nil, Self.probeLooksLikeOpenCode(data) {
                    finish(true)
                } else if isComplete || error != nil {
                    finish(false)
                } else if let data, !data.isEmpty {
                    // header may have been split — read the rest once
                    c.receive(minimumIncompleteLength: 1, maximumLength: 262_144) { more, _, moreComplete, moreError in
                        let combined = data + (more ?? Data())
                        finish(Self.probeLooksLikeOpenCode(combined) || (moreError != nil && moreComplete))
                    }
                } else {
                    finish(false)
                }
            }
            c.start(queue: .global(qos: .utility))

            Task { [weak self] in
                try? await Task.sleep(nanoseconds: Self.ioTimeoutSec * 1_000_000_000)
                if !settled.value { finish(false) }
                _ = self
            }
        }
    }

    private nonisolated static func probeLooksLikeOpenCode(_ data: Data) -> Bool {
        let text = String(decoding: data, as: UTF8.self)
        let is200 = text.hasPrefix("HTTP/1.1 200") || text.hasPrefix("HTTP/1.0 200")
        guard is200 else { return false }
        let body = text.components(separatedBy: "\r\n\r\n").dropFirst().joined(separator: "\r\n\r\n")
        return body.contains("version") || body.contains("plugin") || body.contains("schema")
    }

    // MARK: - SSE stream

    private func openStream(port: UInt16, basic: (String, String)?) async {
        let c = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        self.stream = c
        buffer = ""

        c.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    var req = "GET /api/event HTTP/1.1\r\nHost: 127.0.0.1\r\nAccept: text/event-stream\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\n"
                    if let up = basic {
                        req += Self.basicHeader(up) + "\r\n"
                    }
                    req += "\r\n"
                    c.send(content: req.data(using: .utf8), completion: .contentProcessed { _ in })
                    self?.connected = true
                    self?.watchedPort = port
                case .failed, .cancelled:
                    self?.connected = false
                default:
                    break
                }
            }
        }
        // NWConnection callbacks (stateUpdate + receive completion) fire on the
        // queue passed to `start`. openStream is @MainActor and pokes @Published
        // state (connected/watchedPort/eventsReceived/lastEventAt) from those
        // callbacks — so callbacks MUST land on the main actor, otherwise the
        // @Published writes race and SIGSEGV. Delivery is async (we `await` each
        // receive), so this never blocks the main runloop.
        c.start(queue: .main)
        // The SSE stream only carries *new* events. Seed the board from
        // GET /api/session (auth'd) once the port is known, then refresh every
        // 30 s so already-running sessions — including ones opened before Pluto
        // started — appear with their title, directory and state.
        seedTask?.cancel()
        seedTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            while !Task.isCancelled {
                await self?.seedSessions()
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }

        // Drive the receive loop until it closes. `c.start(queue: .main)` above
        // means NW callbacks (and thus this loop after `await recvChunk`) resume
        // on the main actor, so @Published writes here are safe.
        var raw = Data()
        while !Task.isCancelled, stream === c {
            let (chunk, closed, _) = await recvChunk(c)
            if !chunk.isEmpty {
                raw.append(chunk)
                if raw.count > 262_144 {
                    raw = raw.suffix(65_536)
                }
                let (frames, rest) = Self.parseSSE(raw)
                raw = rest
                for frame in frames {
                    await MainActor.run { [weak self] in
                        self?.eventsReceived += 1
                        self?.lastEventAt = Date()
                    }
                    forward(frame)
                }
            }
            if closed {
                connected = false
                if stream === c { stream = nil }
                return
            }
        }
    }

    private func recvChunk(_ c: NWConnection) async -> (Data, closed: Bool, NWError?) {
        await withCheckedContinuation { (cont: CheckedContinuation<(Data, Bool, NWError?), Never>) in
            c.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
                cont.resume(returning: (data ?? Data(), isComplete, error))
            }
        }
    }

    // MARK: - Session seeding

    /// GET /api/session and mirror the freshest sessions onto the board so the
    /// panel immediately shows sessions that were already running (the SSE
    /// stream only delivers events going forward). A session is "working" while
    /// its `updated` time is newer than its `idle` time.
    func seedSessions() async {
        guard let port = watchedPort else { return }
        var args = ["-s", "-m", "4", "-H", "Accept: application/json"]
        if let pw = servicePassword() { args += ["-u", "opencode:\(pw)"] }
        args.append("http://127.0.0.1:\(port)/api/session")
        let data = await runAsync("/usr/bin/curl", args)
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let list = json["data"] as? [[String: Any]] else { return }
        let sorted = list.sorted { lhs, rhs in
            let lu = (lhs["time"] as? [String: Any])?["updated"] as? Double ?? 0
            let ru = (rhs["time"] as? [String: Any])?["updated"] as? Double ?? 0
            return lu > ru
        }
        let cutoff = Date().addingTimeInterval(-2 * 3600)
        for s in sorted.prefix(12) {
            guard let id = s["id"] as? String, !id.isEmpty else { continue }
            let time = s["time"] as? [String: Any]
            let updated = time?["updated"] as? Double
            guard let ms = updated, ms > 0,
                  Date(timeIntervalSince1970: ms / 1000) > cutoff else { continue }
            let idle = time?["idle"] as? Double ?? 0
            let working = ms > idle
            var body: [String: Any] = ["type": "session.seed",
                                       "sessionID": id,
                                       "working": working]
            if let t = s["title"] as? String, !t.isEmpty { body["title"] = t }
            if let loc = s["location"] as? [String: Any],
               let dir = loc["directory"] as? String, !dir.isEmpty {
                body["projectPath"] = dir
            }
            body["updatedMs"] = ms
            SessionStore.shared.applyEvent(agentID: "opencode", body: body)
        }
    }

    /// Non-blocking Process runner (the blocking `run` would freeze the main actor).
    private func runAsync(_ path: String, _ argv: [String]) async -> Data {
        await withCheckedContinuation { (cont: CheckedContinuation<Data, Never>) in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: path)
            p.arguments = argv
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = FileHandle.nullDevice
            p.terminationHandler = { _ in
                cont.resume(returning: pipe.fileHandleForReading.readDataToEndOfFile())
            }
            do { try p.run() } catch { cont.resume(returning: Data()) }
        }
    }

    /// Splits an SSE byte buffer on the blank-line delimiter, returning parsed
    /// event envelopes (`{type,data}`) and the unconsumed remainder.
    private static func parseSSE(_ raw: Data) -> (frames: [[String: Any]], rest: Data) {
        let text = String(decoding: raw, as: UTF8.self)
        var frames: [[String: Any]] = []
        var remainder = text
        while let range = firstDoubleNewline(in: remainder) {
            let block = String(remainder[..<range.lowerBound])
            remainder.removeSubrange(..<range.upperBound)
            if let json = Self.parseEvent(block) {
                frames.append(json)
            }
        }
        return (frames, Data(remainder.utf8))
    }

    private static func firstDoubleNewline(in s: String) -> Range<String.Index>? {
        if let r = s.range(of: "\r\n\r\n") { return r }
        return s.range(of: "\n\n")
    }

    private static func parseEvent(_ block: String) -> [String: Any]? {
        var type: String?
        var dataText = ""
        for line in block.split(separator: "\n") {
            let l = line.hasSuffix("\r") ? String(line.dropLast()) : String(line)
            if l.hasPrefix(":") { continue }                 // heartbeat / comment
            if l.hasPrefix("data:") || l.hasPrefix("data: ") {
                dataText += (l == "data:" ? "" : String(l.dropFirst("data: ".count))) + "\n"
            } else if l.hasPrefix("event:") {
                type = String(l.dropFirst("event: ".count)).trimmingCharacters(in: .whitespaces)
            }
        }
        dataText = dataText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = dataText.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              var dict = json as? [String: Any] else { return nil }
        if let type { dict["type"] = type }
        return dict
    }

    // MARK: - Event mapping

    private func forward(_ event: [String: Any]) {
        guard let type = event["type"] as? String,
              type.hasPrefix("session.") || type.hasPrefix("message.") || type.hasPrefix("permission.")
        else { return }

        let data = event["data"] as? [String: Any] ?? [:]
        var body: [String: Any] = ["type": type]

        var sessionID = data["sessionID"] as? String
        var title: String?
        var projectPath: String?

        if let info = data["info"] as? [String: Any] {
            sessionID = sessionID ?? (info["id"] as? String) ?? (info["sessionID"] as? String)
            if let t = info["title"] as? String, !t.isEmpty { title = t }
            if let d = info["directory"] as? String, !d.isEmpty {
                projectPath = d
            } else if let d = info["worktree"] as? String, !d.isEmpty {
                projectPath = d
            }
        }
        if let msg = data["message"] as? [String: Any] {
            sessionID = sessionID ?? (msg["sessionID"] as? String)
        }

        if let sid = sessionID, !sid.isEmpty { body["sessionID"] = sid }
        if let t = title { body["title"] = t }
        if let p = projectPath { body["projectPath"] = p }
        if let s = Self.snippet(from: data) { body["snippet"] = s }
        if type == "permission.updated" || type == "permission.asked" {
            body["text"] = "needs your approval"
        }
        if type == "session.error",
           let err = data["error"] as? [String: Any],
           let msg = err["message"] as? String {
            body["text"] = String(msg.suffix(60))
        }

        SessionStore.shared.applyEvent(agentID: "opencode", body: body)
    }

    static func snippet(from data: [String: Any]) -> String? {
        func texts(in array: [[String: Any]]) -> [String] {
            array.compactMap { part -> String? in
                guard (part["type"] as? String) == "text", let t = part["text"] as? String else { return nil }
                return t
            }
        }
        var all: [String] = []
        if let parts = data["parts"] as? [[String: Any]] {
            all += texts(in: parts)
            if let role = (data["info"] as? [String: Any])?["role"] as? String, role != "assistant" { return nil }
        }
        if let info = data["info"] as? [String: Any] {
            if let role = info["role"] as? String, role != "assistant" { return nil }
            if let parts = info["parts"] as? [[String: Any]] { all += texts(in: parts) }
        }
        if let part = data["part"] as? [String: Any] {
            if let role = part["role"] as? String, role != "assistant" { return nil }
            if (part["type"] as? String) == "text", let t = part["text"] as? String { all.append(t) }
        }
        if let msg = data["message"] as? [String: Any] {
            if let role = msg["role"] as? String, role != "assistant" { return nil }
            if let parts = msg["parts"] as? [[String: Any]] { all += texts(in: parts) }
        }
        guard let last = all.last, !last.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return String(last.suffix(64))
    }
}
