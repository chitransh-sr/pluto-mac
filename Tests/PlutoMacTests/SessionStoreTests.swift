import Testing
@testable import PlutoMac

final class SessionStoreTests {
    // MARK: - SessionKey

    @Test func testSessionKeyEvent() {
        let key = SessionKey.event("opencode", "sess-123")
        #expect(key == "event|opencode|sess-123")
    }

    @Test func testSessionKeyScan() {
        let key = SessionKey.scan("claude", "456")
        #expect(key == "scan|claude|456")
    }

    @Test func testSessionKeyScanDefault() {
        let key = SessionKey.scan("codex", "")
        #expect(key == "scan|codex|")
    }

    // MARK: - AgentKind

    @Test func testAgentKindByID() {
        #expect(AgentKind.byID("opencode")?.displayName == "OpenCode")
        #expect(AgentKind.byID("claude")?.displayName == "Claude Code")
        #expect(AgentKind.byID("codex")?.displayName == "Codex")
        #expect(AgentKind.byID("gemini")?.displayName == "Gemini CLI")
        #expect(AgentKind.byID("cursor")?.displayName == "Cursor")
        #expect(AgentKind.byID("qwen")?.displayName == "Qwen Code")
    }

    @Test func testAgentKindUnknownID() {
        #expect(AgentKind.byID("nonexistent") == nil)
        #expect(AgentKind.byID("") == nil)
    }

    @Test func testAgentKindBundleID() {
        #expect(AgentKind.cursor.bundleID == "com.cursor.Cursor")
        #expect(AgentKind.opencode.bundleID == nil)
        #expect(AgentKind.claude.bundleID == nil)
    }

    @Test func testAgentKindIsGUI() {
        #expect(AgentKind.cursor.isGUI == true)
        #expect(AgentKind.opencode.isGUI == false)
        #expect(AgentKind.qwen.isGUI == false)
    }

    @Test func testAllAgentKinds() {
        #expect(AgentKind.all.count == 12)
        for agent in AgentKind.all {
            #expect(agent.id == agent.id.lowercased())
        }
    }
}
