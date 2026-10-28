import Foundation

/// Finds running agent CLIs by scanning the process list, the same way
/// Pluto's ProcessScanner does on Windows — 3 s loop over `ps`.
@MainActor
final class ProcessScanner: ObservableObject {
    static let shared = ProcessScanner()

    private var task: Task<Void, Never>?
    /// Last known PID per agent (from the most recent scan). Used to activate
    /// event-source sessions that don't carry a hostPID themselves.
    private var lastPIDs: [String: pid_t] = [:]

    /// Returns the most recently scanned PID for the given agent id, if any.
    func lastPID(for agentID: String) -> pid_t? {
        lastPIDs[agentID]
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                self?.scanOnce()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// Resolve a PID's cwd via `lsof -a -d cwd -F n`. `-F n` emits one
    /// `n<path>` record per matched descriptor, so paths with spaces survive
    /// intact and the call is cheap. (A bare `split(separator: "")` here would
    /// shatter the path into single characters — that's how the project folder
    /// once came back as just "s".)
    private func cwd(for pid: pid_t) -> String? {
        let data = run("/usr/sbin/lsof", ["-a", "-p", String(pid), "-d", "cwd", "-F", "n"])
        let text = String(data: data, encoding: .utf8) ?? ""
        for line in text.split(separator: "\n") {
            let l = String(line)
            if l.hasPrefix("n"), l.dropFirst().trimmingCharacters(in: .whitespaces).isEmpty == false {
                let path = l.dropFirst().trimmingCharacters(in: .whitespaces)
                if path != "/" { return path }
            }
        }
        return nil
    }

    func scanOnce() {
        let data = run("/bin/ps", ["-axww", "-o", "pid=,args="])
        guard let text = String(data: data, encoding: .utf8) else { return }

        var hits: [SessionStore.Hit] = []
        var seen: Set<pid_t> = []
        let myPID = getpid()

        for line in text.split(separator: "\n") {
            let l = line.trimmingCharacters(in: .whitespaces)
            guard let pidEnd = l.firstIndex(of: " ") else { continue }
            guard let pid = pid_t(l[l.startIndex..<pidEnd]) else { continue }
            guard pid > 1, pid != myPID else { continue }

            let args = String(l[l.index(after: pidEnd)...]).lowercased()
            guard !args.contains("plutomac"), !args.contains("pluto.app") else { continue }

            guard let agent = matchAgent(args: args) else { continue }
            // "opencode serve --service" is a background daemon, not an active session.
            if agent.id == AgentKind.opencode.id && args.contains("serve") { continue }
            let isService = agent.id == AgentKind.opencode.id && args.contains("serve")
            guard !seen.contains(pid) else { continue }
            seen.insert(pid)
            let cwdPath = cwd(for: pid)
            hits.append(SessionStore.Hit(pid: pid, agent: agent,
                                        cwd: cwdPath,
                                        isService: isService))
            lastPIDs[agent.id] = pid
        }

        SessionStore.shared.syncScanResults(hits)
    }

    private func matchAgent(args: String) -> AgentKind? {
        let tokens = args.split(separator: " ").map(String.init)
        for agent in AgentKind.all {
            guard Prefs.shared.isWatching(agent) else { continue }
            if hit(agent.id, tokens: tokens, args: args) { return agent }
        }
        return nil
    }

    private func hit(_ needle: String, tokens: [String], args: String) -> Bool {
        // Match the executable only: the first token's basename, or the token
        // right after a node/bun/deno runtime (npm globals). Checking every
        // token let any path containing the agent name — e.g. Cursor's
        // `.../cursor` helper paths — masquerade as that agent (13 fake rows).
        guard let exe = tokens.first else { return false }
        let exeBase = (exe as NSString).lastPathComponent.lowercased()
        if exeBase == needle { return true }
        if ["node", "bun", "deno", "npx", "bunx"].contains(exeBase), tokens.count > 1 {
            let second = (tokens[1] as NSString).lastPathComponent.lowercased()
            if second == needle { return true }
        }
        _ = args
        return false
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
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return data
    }
}
