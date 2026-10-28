import Foundation
import Network

/// A tiny HTTP listener on 127.0.0.1 — the Mac twin of Pluto's named pipe.
/// Everything ships events here:
///   * OpenCode plugin        → POST /event/opencode  {…}
///   * Claude Code hooks      → POST /event/claude    (hook JSON on stdin)
///   * anything else          → curl -d @-  /event/<agent>
@MainActor
final class EventServer: ObservableObject {
    @Published private(set) var listening = false
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var buffers: [ObjectIdentifier: Data] = [:]

    var port: UInt16 { UInt16(max(1025, min(65535, Prefs.shared.eventPort))) }

    func start() {
        stop()
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        do {
            let l = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            listener = l
            l.newConnectionHandler = { [weak self] c in
                Task { @MainActor in
                    self?.accept(c)
                }
            }
            l.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    self?.listening = (state == .ready)
                }
            }
            // NW callbacks (newConnection / receive completions) mutate @MainActor
            // state (buffers, connections, listening) — so run them on the main
            // queue, matching EventServer's @MainActor isolation. (The receive
            // loop is async via `connection.receive`, so this never blocks UI.)
            l.start(queue: .main)
        } catch {
            NSLog("Pluto: could not bind port \(port): \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        connections.values.forEach { $0.cancel() }
        connections.removeAll()
        buffers.removeAll()
    }

    private func accept(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.receiveLoop(connection)
                case .failed, .cancelled:
                    self?.drop(connection)
                default:
                    break
                }
            }
        }
        // See note in start(): receive completions mutate @MainActor state,
        // so the connection's callback queue must be the main queue.
        connection.start(queue: .main)
    }

    private func drop(_ connection: NWConnection) {
        connections.removeValue(forKey: ObjectIdentifier(connection))
        buffers.removeValue(forKey: ObjectIdentifier(connection))
    }

    private func receiveLoop(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            let id = ObjectIdentifier(connection)
            guard let self else { return }
            // The receive completion callback is @Sendable-escaping; route all
            // main-actor mutations through a Task so the compiler is satisfied
            // and we never race the UI.
            Task { @MainActor in
                if let data, !data.isEmpty {
                    self.buffers[id, default: Data()] += data
                }
                if let request = self.buffers[id], Self.isComplete(request) {
                    self.handle(request: request, connection: connection)
                    self.drop(connection)
                    return
                }
                if isComplete || error != nil {
                    // Client hung up; parse what we have.
                    if let request = self.buffers[id] {
                        self.handle(request: request, connection: connection)
                    }
                    self.drop(connection)
                } else if self.buffers[id]?.count ?? 0 > 1_048_576 {
                    self.drop(connection)
                } else {
                    self.receiveLoop(connection)
                }
            }
        }
    }

    /// Finds the byte offset just past the `\r\n\r\n` header separator.
    /// Minimal stderr writer so `print(..., to: &stderr)` works.
    /// Minimal stderr writer.
    private static func headerEnd(in data: Data) -> Int? {
        let sep: [UInt8] = [0x0D, 0x0A, 0x0D, 0x0A]
        return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Int? in
            let bytes = raw.bindMemory(to: UInt8.self)
            guard bytes.count >= sep.count else { return nil }
            var i = 0
            outer: while i <= bytes.count - sep.count {
                for j in 0..<sep.count where bytes[i + j] != sep[j] {
                    i += 1
                    continue outer
                }
                return i + sep.count
            }
            return nil
        }
    }

    private static func isComplete(_ data: Data) -> Bool {
        guard let end = headerEnd(in: data) else { return false }
        let headerText = String(decoding: data[..<end], as: UTF8.self)
        if let clLine = headerText.split(separator: "\r\n")
            .first(where: { $0.lowercased().hasPrefix("content-length:") })?
            .split(separator: ":").last,
           let n = Int(clLine.trimmingCharacters(in: .whitespaces)) {
            return data.count >= end + n
        }
        return true
    }

    private func handle(request: Data, connection: NWConnection) {
        let text = String(decoding: request, as: UTF8.self)
        let lines = text.components(separatedBy: "\r\n")
        let requestLine = lines.first ?? ""

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            send("HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n", on: connection)
            return
        }
        let path = String(parts[1])

        if path == "/health" {
            let tap = OpenCodeTap.shared
            let body = """
            {
              "ok": true,
              "listening": true,
              "inputPort": \(Prefs.shared.eventPort),
              "sessions": \(SessionStore.shared.sessions.count),
              "opencodeConnected": \(tap.connected ? "true" : "false"),
              "opencodePort": \(tap.watchedPort ?? 0),
              "opencodeEvents": \(tap.eventsReceived)
            }
            """
            let payload = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n\(body)"
            send(payload, on: connection)
            return
        }

        if path == "/debug" {
            let now = Date()
            let arr = SessionStore.shared.sortedSessions().map { s -> [String: Any] in
                let age = Int(now.timeIntervalSince(s.lastActivity))
                return [
                    "id": s.id,
                    "agent": s.agent.id,
                    "state": s.state.rawValue,
                    "source": s.source.rawValue,
                    "age": "\(age)s",
                    "project": s.projectFolder ?? "",
                    "title": s.title ?? "",
                    "pid": s.hostPID ?? 0,
                    "workingSince": s.workingSince.map { Int(now.timeIntervalSince($0)) } ?? 0
                ] as [String: Any]
            }
            let data = (try? JSONSerialization.data(withJSONObject: arr, options: [.fragmentsAllowed])) ?? Data()
            let prefix = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(data.count)\r\nConnection: close\r\n\r\n"
            var full = Data(prefix.utf8)
            full.append(data)
            sendRaw(full, on: connection)
            return
        }

        guard path.hasPrefix("/event/"), let end = Self.headerEnd(in: request) else {
            send("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n", on: connection)
            return
        }

        let agentID = String(path.dropFirst("/event/".count))
        let bodyData = request.subdata(in: end..<request.count)
        guard !agentID.isEmpty, let body = try? JSONSerialization.jsonObject(with: bodyData),
              let dict = body as? [String: Any] else {
            send("HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n", on: connection)
            return
        }

        let store = SessionStore.shared
        Task { @MainActor in
            store.applyEvent(agentID: agentID.lowercased(), body: dict)
        }
        send("HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n", on: connection)
    }

    private func send(_ text: String, on connection: NWConnection) {
        connection.send(content: text.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func sendRaw(_ data: Data, on connection: NWConnection) {
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
