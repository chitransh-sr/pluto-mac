import AppKit
import SwiftUI

/// One supported AI coding agent. Mirrors Pluto (Windows) — the same set of
/// CLIs, including OpenCode as a first-class citizen.
struct AgentKind: Identifiable, Hashable {
    let id: String
    let displayName: String
    /// Brand color used for the avatar badge.
    let color: Color
    /// SF Symbol fallback icon.
    let symbol: String
    /// macOS bundle ID for GUI app activation (nil for CLI-only agents).
    let bundleID: String?

    static func == (lhs: AgentKind, rhs: AgentKind) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension AgentKind {
    static let opencode = AgentKind(id: "opencode", displayName: "OpenCode",
                                    color: Color(red: 0.30, green: 0.56, blue: 0.98), symbol: "chevron.left.forwardslash.chevron.right", bundleID: nil)
    static let claude = AgentKind(id: "claude", displayName: "Claude Code",
                                  color: Color(red: 0.91, green: 0.45, blue: 0.24), symbol: "sparkle", bundleID: nil)
    static let codex = AgentKind(id: "codex", displayName: "Codex",
                                 color: Color(red: 0.42, green: 0.24, blue: 0.86), symbol: "chevron.left.chevron.right", bundleID: nil)
    static let gemini = AgentKind(id: "gemini", displayName: "Gemini CLI",
                                  color: Color(red: 0.18, green: 0.55, blue: 0.87), symbol: "diamond", bundleID: nil)
    static let cursor = AgentKind(id: "cursor", displayName: "Cursor",
                                  color: Color(red: 0.10, green: 0.10, blue: 0.12), symbol: "cursorarrow.rays", bundleID: "com.cursor.Cursor")
    static let copilot = AgentKind(id: "copilot", displayName: "Copilot CLI",
                                   color: Color(red: 0.35, green: 0.40, blue: 0.48), symbol: "brain.head.profile", bundleID: nil)
    static let aider = AgentKind(id: "aider", displayName: "Aider",
                                 color: Color(red: 0.16, green: 0.62, blue: 0.45), symbol: "chevron.up.chevron.down", bundleID: nil)
    static let goose = AgentKind(id: "goose", displayName: "Goose",
                                 color: Color(red: 0.85, green: 0.50, blue: 0.15), symbol: "bird", bundleID: nil)
    static let crush = AgentKind(id: "crush", displayName: "Crush",
                                 color: Color(red: 0.72, green: 0.13, blue: 0.30), symbol: "bolt.fill", bundleID: nil)
    static let amp = AgentKind(id: "amp", displayName: "Amp",
                               color: Color(red: 0.20, green: 0.20, blue: 0.22), symbol: "waveform", bundleID: nil)
    static let droid = AgentKind(id: "droid", displayName: "Droid",
                                 color: Color(red: 0.15, green: 0.35, blue: 0.65), symbol: "antenna.radiowaves.left.and.right", bundleID: nil)
    static let qwen = AgentKind(id: "qwen", displayName: "Qwen Code",
                                color: Color(red: 0.47, green: 0.32, blue: 0.86), symbol: "text.bubble", bundleID: nil)

    static let all: [AgentKind] = [.opencode, .claude, .codex, .gemini, .cursor, .copilot,
                                   .aider, .goose, .crush, .amp, .droid, .qwen]

    static func byID(_ id: String) -> AgentKind? {
        all.first { $0.id == id }
    }

    /// Whether this agent is a GUI app whose mere presence in the process
    /// table does NOT imply an active agent session (Cursor editor, etc.).
    var isGUI: Bool { self == .cursor }
}

/// A live agent session in the board.
struct Session: Identifiable, Hashable {
    /// "agent|source|pid-or-sessionID"
    let id: String
    let agent: AgentKind
    /// scan = process scanner, event = hook / plugin / OpenCode SSE
    let source: Source
    var state: SessionState = .working
    var title: String?
    var projectFolder: String?
    var hostAppName: String?
    var hostPID: pid_t?
    var snippet: String?
    var workingSince: Date?
    var lastActivity: Date = Date()
    var lastDurationText: String?

    enum Source: String, Codable {
        case scan, `event`
    }

    var ageText: String {
        let s = Int(Date().timeIntervalSince(lastActivity))
        if s < 5 { return "just now" }
        if s < 60 { return "\(s)s ago" }
        if s < 3600 { return "\(s / 60)m ago" }
        return "\(s / 3600)h ago"
    }
}

enum SessionState: String, Codable {
    case working, idle, needsYou, failed
}
