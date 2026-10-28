import AppKit
import CoreGraphics
import Foundation

/// The board: every live agent session with a small state machine
/// (Idle · Working · Needs you — the same three states Pluto tracks).
@MainActor
final class SessionStore: ObservableObject {
    static let shared = SessionStore()

    @Published private(set) var sessions: [String: Session] = [:]
    /// Bumped every second while ≥1 event session is working, so views can recompute
    /// live durations. Driven by a 1 Hz timer installed in `startTick()`.
    @Published private(set) var tick: Int = 0
    private var tickTimer: Timer?

    /// Fired for notable transitions. `text` is the banner line, e.g. "Done in 4:12".
    var onMoment: ((Session, Prefs.Moment, String?) -> Void)?

    /// Suppresses the start chirp during an OpenCode reconnect replay burst.
    private var lastStart: [String: Date] = [:]

    /// Newest "done / needs you / failed" event time — drives the face's happy/alert expression.
    @Published private(set) var expressionUntil: Date = .distantPast

    var activeCount: Int {
        // Only count live event sessions (not process-scan artifacts) for the header label.
        sessions.values.filter { ($0.source == .event) && ($0.state == .working || $0.state == .needsYou) }.count
    }

     /// Sessions currently doing work (drives the collapsed pet's progress sweep).
    /// Excludes process-scan hits for GUI editor apps (Cursor) which aren't real
    /// agent activity — only real event sessions and CLI-agent scans count.
    var workingCount: Int {
        sessions.values.filter { $0.state == .working && $0.source == .event }.count
    }

    var globalState: SessionState {
        if sessions.values.contains(where: { $0.source == .event && $0.state == .needsYou }) { return .needsYou }
        if sessions.values.contains(where: { $0.source == .event && $0.state == .working }) { return .working }
        if Date() < expressionUntil { return .idle }
        return .idle
    }

    var needsAttention: Bool {
        sessions.values.contains { $0.source == .event && $0.state == .needsYou }
    }

    func sortedSessions() -> [Session] {
        sessions.values.sorted { $0.lastActivity > $1.lastActivity }
    }

    // MARK: - Event pipeline (hooks, OpenCode plugin, anything that POSTs /event/<agent>)

    func applyEvent(agentID: String, body: [String: Any]) {
        guard let agent = AgentKind.byID(agentID), Prefs.shared.isWatching(agent) else { return }

        let rawType = (body["type"] as? String) ?? (body["hook_event_name"] as? String) ?? (body["event"] as? String) ?? ""
        let sessionID = (body["sessionID"] as? String) ?? (body["session_id"] as? String) ?? ""
        let cwd = (body["projectPath"] as? String) ?? (body["worktree"] as? String) ?? (body["cwd"] as? String)
        let snippet = (body["snippet"] as? String) ?? (body["message"] as? String) ?? (body["text"] as? String)
        let title = (body["title"] as? String)?.nilIfEmpty
        let key = SessionKey.event(agent.id, sessionID.isEmpty ? "default" : sessionID)
        let now = Date()

        // The SSE stream carries SSE event types directly.
        if sessionID.isEmpty, let props = (body["data"] as? [String: Any]) {
            // Allow callers that forward the envelope to still be usable.
            let _ = props
        }

        let moment: Prefs.Moment?
        switch rawType.lowercased() {
        case "session.seed":
            // Bulk seeding from GET /api/session: no banners, no chimes.
            moment = nil
            let seedWorking = (body["working"] as? Bool) ?? false
            upsert(key: key, agent: agent, source: .event, cwd: cwd, snippet: nil, title: title) {
                if $0.state != .needsYou {
                    $0.state = seedWorking ? .working : .idle
                    if seedWorking, $0.workingSince == nil { $0.workingSince = now }
                }
            }
            if let ms = body["updatedMs"] as? Double, ms > 0 {
                sessions[key]?.lastActivity = Date(timeIntervalSince1970: ms / 1000)
            }
        case "userpromptsubmit", "session.created", "session.status",
             "message.updated", "message.part.updated", "permission.replied":
            moment = sessions[key] == nil ? .start : nil
            upsert(key: key, agent: agent, source: .event, cwd: cwd, snippet: snippet, title: title) {
                $0.state = .working
                if $0.workingSince == nil { $0.workingSince = now }
            }
        case "session.updated":
            // Title/directory refresh only — don't flip the state.
            moment = nil
            upsert(key: key, agent: agent, source: .event, cwd: cwd, snippet: snippet, title: title) { _ in }
        case "stop", "session.idle":
            if sessions[key]?.state == .working {
                let dur = durationText(since: sessions[key]?.workingSince)
                moment = .done
                upsert(key: key, agent: agent, source: .event, cwd: cwd, snippet: nil, title: title) {
                    $0.state = .idle
                    $0.workingSince = nil
                    $0.lastDurationText = dur
                }
            } else {
                moment = nil
                upsert(key: key, agent: agent, source: .event, cwd: cwd, snippet: nil, title: title) {
                    if $0.state == .working {
                        $0.state = .idle
                        $0.workingSince = nil
                        $0.lastDurationText = durationText(since: $0.workingSince)
                    }
                }
            }
        case "notification", "permission.asked", "permission.updated":
            moment = .needsYou
            upsert(key: key, agent: agent, source: .event, cwd: cwd, snippet: snippet, title: title) {
                $0.state = .needsYou
                $0.workingSince = nil
            }
        case "session.error":
            moment = .failed
            upsert(key: key, agent: agent, source: .event, cwd: cwd, snippet: snippet, title: title) {
                $0.state = .failed
            }
        case "session.deleted", "session.ended":
            sessions.removeValue(forKey: key)
            moment = nil
        default:
            moment = nil
        }

        if let moment {
            announce(agent: agent, moment: moment)
        }
        pruneStale()
    }

    // MARK: - Process scanner pipeline

    /// A process-scan match, mirrored into the session board.
    struct Hit {
        let pid: pid_t
        let agent: AgentKind
        /// Working directory, resolved via `lsof` — becomes the row's project folder.
        let cwd: String?
        /// `opencode serve --service` style daemon (idle, no start banner).
        let isService: Bool
    }

    func syncScanResults(_ found: [Hit]) {
        let now = Date()
        var seenPID: Set<String> = []
        for f in found where Prefs.shared.isWatching(f.agent) {
            let key = SessionKey.scan(f.agent.id, String(f.pid))
            seenPID.insert(key)
            if var s = sessions[key] {
                if f.isService { s.state = .idle } else { s.state = .working }
                if !f.isService { s.lastActivity = now }
                s.hostPID = f.pid
                if let cwd = f.cwd, !cwd.isEmpty, cwd != "/" {
                    s.projectFolder = URL(fileURLWithPath: cwd).lastPathComponent.isEmpty ? cwd : URL(fileURLWithPath: cwd).lastPathComponent
                }
                sessions[key] = s
            } else {
                var s = Session(id: key, agent: f.agent, source: .scan)
                s.state = f.isService ? .idle : .working
                s.workingSince = f.isService ? nil : now
                s.hostPID = f.pid
                if f.isService { s.snippet = "service daemon" }
                if let cwd = f.cwd, !cwd.isEmpty, cwd != "/" {
                    s.projectFolder = URL(fileURLWithPath: cwd).lastPathComponent.isEmpty ? cwd : URL(fileURLWithPath: cwd).lastPathComponent
                }
                sessions[key] = s
                if !f.isService, Prefs.shared.soundChoice(for: .start) != .none {
                    announce(agent: f.agent, moment: .start)
                }
            }
        }
        // Drop scan sessions whose process has gone.
        for (key, s) in sessions where s.source == .scan && !seenPID.contains(key) {
            sessions.removeValue(forKey: key)
        }
        pruneStale()
    }

    // MARK: - Helpers

    private func upsert(key: String, agent: AgentKind, source: Session.Source,
                        cwd: String?, snippet: String?, title: String?, mutate: (inout Session) -> Void) {
        var s = sessions[key] ?? Session(id: key, agent: agent, source: source)
        s.lastActivity = Date()
        if let cwd, !cwd.isEmpty {
            s.projectFolder = URL(fileURLWithPath: cwd).lastPathComponent
        }
        if let title, !title.isEmpty {
            s.title = title
        }
        if let snippet, !snippet.isEmpty {
            let trimmed = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { s.snippet = String(trimmed.suffix(64)) }
        }
        mutate(&s)
        sessions[key] = s
    }

    private func announce(agent: AgentKind, moment: Prefs.Moment) {
        let s = sessions.values
            .filter { $0.agent == agent }
            .max { $0.lastActivity < $1.lastActivity }
        if moment == .start {
            let last = lastStart[agent.id] ?? .distantPast
            lastStart[agent.id] = Date()
            if Date().timeIntervalSince(last) < 1.0 {
                // Burst (e.g. OpenCode replaying history on reconnect) — stay quiet.
                return
            }
        }
        if moment == .done || moment == .needsYou || moment == .failed {
            expressionUntil = Date().addingTimeInterval(4)
        }
        onMoment?(s ?? Session(id: "ephemeral-\(agent.id)", agent: agent, source: .event), moment, nil)
    }

    private func durationText(since start: Date?) -> String? {
        guard let start else { return nil }
        let total = Int(Date().timeIntervalSince(start))
        guard total >= 0 else { return nil }
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Event sessions leave the board when nothing happened for a while.
    private func pruneStale() {
        let cutoff = Date().addingTimeInterval(-2 * 3600)
        sessions = sessions.filter { $0.value.source == .scan || $0.value.lastActivity > cutoff }
    }

    // MARK: - Ticker

    /// Install a 1 Hz timer that bumps `tick` whenever any *event* session
    /// is in `.working` state. This forces SwiftUI to recompute captions and
    /// age labels with a fresh `Date()`, so live durations stay current
    /// instead of freezing between SSE events.
    func startTick() {
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let hasWorking = self.sessions.values.contains { $0.source == .event && $0.state == .working }
            if hasWorking {
                self.tick &+= 1
            }
        }
    }
}

enum SessionKey {
    static func event(_ agent: String, _ id: String) -> String { "event|\(agent)|\(id)" }
    static func scan(_ agent: String, _ pid: String) -> String { "scan|\(agent)|\(pid)" }
}
