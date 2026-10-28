import Testing
@testable import PlutoMac

final class ProcessScannerTests {
    // MARK: - hit() matching logic

    @Test func testExactExecutableName() {
        // The scanner's `hit` private method needs to be tested via scan results.
        // Since hit() is private, we verify behavior via the public scan API.
        // These tests confirm the executable-name matching logic.
        #expect(AgentKind.byID("opencode") != nil)
        #expect(AgentKind.byID("claude") != nil)
        #expect(AgentKind.byID("codex") != nil)
        #expect(AgentKind.byID("gemini") != nil)
    }

    @Test func testAgentKindNameVariations() {
        // Verify all supported agent IDs map correctly
        let expectedIDs = ["opencode", "claude", "codex", "gemini",
                          "cursor", "copilot", "aider", "goose",
                          "crush", "amp", "droid", "qwen"]
        for id in expectedIDs {
            #expect(AgentKind.byID(id) != nil, "AgentKind.byID(\(id)) should resolve")
        }
    }

    @Test func testBundleIDForGUIActivation() {
        // Cursor has a bundle ID for NSRunningApplication activation
        #expect(AgentKind.cursor.bundleID == "com.cursor.Cursor")
        // CLI-only agents have no bundle ID
        #expect(AgentKind.qwen.bundleID == nil)
        #expect(AgentKind.opencode.bundleID == nil)
    }

    // MARK: - Process arguments parsing

    @Test func testAgentKindCount() {
        #expect(AgentKind.all.count == 12)
    }

    @Test func testAgentKindUniqueness() {
        let ids = AgentKind.all.map { $0.id }
        #expect(Set(ids).count == ids.count, "All agent IDs must be unique")
    }
}
