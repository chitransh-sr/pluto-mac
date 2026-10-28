import Foundation

/// Installs (or removes) the relay that lets an agent talk to Pluto.
/// OpenCode gets a global plugin — the cleanest integration, since plugins
/// are first-class in OpenCode. Claude Code gets standard hooks in
/// ~/.claude/settings.json, with a `*.before-pluto` backup of the original.
@MainActor
final class RelayInstaller: ObservableObject {
    static let shared = RelayInstaller()

    @Published private(set) var lastStatus: String = ""

    // MARK: - OpenCode plugin (V2 package)

    /// Directory containing the V2 OpenCode plugin package (`pluto/`).
    static var opencodePluginURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/opencode/plugins/pluto")
    }

    static var opencodePluginServerURL: URL { opencodePluginURL.appendingPathComponent("server.js") }
    static var opencodePluginPackageURL: URL { opencodePluginURL.appendingPathComponent("package.json") }
    /// The entry registered in the global ~/.config/opencode/opencode.json.
    static let opencodePluginEntry = "./plugins/pluto"

    func opencodePluginInstalled() -> Bool {
        FileManager.default.fileExists(atPath: Self.opencodePluginServerURL.path)
    }

    func opencodePluginIsCurrent() -> Bool {
        guard opencodePluginInstalled(),
              let src = try? String(contentsOf: Self.opencodePluginServerURL, encoding: .utf8) else { return false }
        return src.contains("plugin v2") && src.contains("const PORT = \(Prefs.shared.eventPort)")
    }

    func installOpenCodePlugin() {
        let dir = Self.opencodePluginURL
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Self.pluginSource(port: Prefs.shared.eventPort).write(to: Self.opencodePluginServerURL, atomically: true, encoding: .utf8)
            try Self.pluginPackageJSON.write(to: Self.opencodePluginPackageURL, atomically: true, encoding: .utf8)
            registerGlobally(enabled: true)
            lastStatus = "OpenCode plugin installed → \(dir.path) (registered in opencode.json)"
        } catch {
            lastStatus = "Could not install plugin: \(error.localizedDescription)"
        }
        objectWillChange.send()
    }

    func removeOpenCodePlugin() {
        try? FileManager.default.removeItem(at: Self.opencodePluginURL)
        registerGlobally(enabled: false)
        lastStatus = "OpenCode plugin removed. Remove \"\(Self.opencodePluginEntry)\" from opencode.json if desired."
        objectWillChange.send()
    }

    /// Add/remove `"./plugins/pluto"` in the global opencode.json `plugins` array.
    private func registerGlobally(enabled: Bool) {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/opencode/opencode.json")
        guard FileManager.default.fileExists(atPath: url.path),
              let text = try? String(contentsOf: url, encoding: .utf8),
              let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { return }
        var copy = json
        var plugins = (copy["plugins"] as? [String]) ?? []
        if enabled { if !plugins.contains(Self.opencodePluginEntry) { plugins.append(Self.opencodePluginEntry) } }
        else { plugins.removeAll { $0 == Self.opencodePluginEntry } }
        if plugins.isEmpty { copy.removeValue(forKey: "plugins") }
        else { copy["plugins"] = plugins }
        guard let data = try? JSONSerialization.data(withJSONObject: copy, options: [.prettyPrinted]) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static let pluginPackageJSON: String = """
    {
      "name": "pluto",
      "version": "1.0.0",
      "type": "module",
      "exports": { ".": "./server.js" },
      "dependencies": { "@opencode/plugin": "latest" }
    }
    """

    static func pluginSource(port: Int) -> String {
        """
        // Pluto for Mac — OpenCode plugin v2 (installed by Pluto's Settings).
        // Watches sessions on the OpenCode server and pings Pluto's feed.
        // Runs silently: every error is swallowed so OpenCode never notices.
        import { Plugin } from "@opencode/plugin";

        const PORT = \(port);
        const ENDPOINT = "http://127.0.0.1:" + PORT + "/event/opencode";

        function lastText(p) {
          const lists = [(p.parts ?? []), (p.info?.parts ?? []), (p.part ? [p.part] : [])];
          for (const parts of lists) {
            const texts = (parts || []).filter((x) => x && x.type === "text" && x.text).map((x) => x.text);
            if (texts.length) return texts[texts.length - 1].slice(-60);
          }
          return "";
        }

        function plutoPost(ev) {
          const p = ev?.data ?? ev?.properties ?? {};
          const t = ev?.type ?? "";
          if (!t) return;
          if (t === "message.updated" || t === "message.part.updated") {
            const role = p.info?.role ?? p.role ?? "";
            if (role && role !== "assistant") return;
          }
          const body = {
            type: t,
            sessionID: p.sessionID ?? p.info?.sessionID ?? p.info?.id ?? p.message?.sessionID ?? "",
            title: p.info?.title ?? p.message?.title ?? "",
            projectPath: p.info?.directory ?? p.info?.worktree ?? p.worktree ?? p.directory ?? "",
            snippet: lastText(p),
          };
          if (t === "permission.asked" || t === "permission.updated") {
            body.text = p.permission?.title ?? p.title ?? "needs your approval";
          }
          if (t === "session.error") body.text = (p.error?.message ?? "error").slice(-60);
          void fetch(ENDPOINT, {
            method: "POST",
            headers: { "content-type": "application/json" },
            body: JSON.stringify(body),
            signal: AbortSignal.timeout(1500),
          }).catch(() => {});
        }

        export default Plugin.define({
          id: "pluto",
          async setup(ctx) {
            const controller = new AbortController();
            void (async () => {
              try {
                for await (const event of ctx.event.subscribe({ signal: controller.signal })) {
                  try { plutoPost(event); } catch (_) {}
                }
              } catch (_) {}
            })();
            return () => controller.abort();
          },
        });
        """
    }

    // MARK: - Claude Code hooks

    static var claudeSettingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    static func claudeHookCommand(port: Int) -> String {
        "curl -fsS -m 2 -X POST http://127.0.0.1:\(port)/event/claude -H 'Content-Type: application/json' --data-binary @- >/dev/null 2>&1"
    }

    func claudeHooksInstalled() -> Bool {
        guard let text = try? String(contentsOf: Self.claudeSettingsURL, encoding: .utf8),
              let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any],
              let flattened = try? JSONSerialization.data(withJSONObject: hooks),
              let wire = String(data: flattened, encoding: .utf8) else { return false }
        return wire.contains("127.0.0.1:\(Prefs.shared.eventPort)/event/claude")
    }

    func installClaudeHooks() {
        let url = Self.claudeSettingsURL
        var json: [String: Any] = [:]
        if let text = try? String(contentsOf: url, encoding: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] {
            json = parsed
        } else if FileManager.default.fileExists(atPath: url.path) {
            // Exists but unreadable — back it up before touching it.
            let backup = url.deletingPathExtension().appendingPathExtension("json.before-pluto")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.copyItem(at: url, to: backup)
        }

        // First-ever install: keep a copy of the original settings.
        let before = url.deletingPathExtension().appendingPathExtension("json.before-pluto")
        if !FileManager.default.fileExists(atPath: before.path) {
            try? FileManager.default.copyItem(at: url, to: before)
        }

        var hooks = json["hooks"] as? [String: Any] ?? [:]
        let command = Self.claudeHookCommand(port: Prefs.shared.eventPort)
        for event in ["UserPromptSubmit", "Stop", "SubagentStop", "Notification"] {
            var groups = (hooks[event] as? [[String: Any]]) ?? []
            var group = groups.first ?? ["matcher": ""]
            var matchers = (group["hooks"] as? [[String: Any]]) ?? []
            // Remove any previous pluto entry, then add ours.
            matchers.removeAll { ($0["command"] as? String)?.contains("/event/claude") == true }
            matchers.append(["type": "command", "command": command])
            group["hooks"] = matchers
            if groups.isEmpty { groups = [group] } else { groups[0] = group }
            hooks[event] = groups
        }
        json["hooks"] = hooks

        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
            lastStatus = "Claude Code hooks installed → \(url.path)"
        } catch {
            lastStatus = "Could not write Claude hooks: \(error.localizedDescription)"
        }
        objectWillChange.send()
    }

    func removeClaudeHooks() {
        let url = Self.claudeSettingsURL
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              var json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              var hooks = json["hooks"] as? [String: Any] else { return }
        for event in ["UserPromptSubmit", "Stop", "SubagentStop", "Notification"] {
            guard var groups = hooks[event] as? [[String: Any]] else { continue }
            for i in groups.indices {
                guard var matchers = groups[i]["hooks"] as? [[String: Any]] else { continue }
                matchers.removeAll { ($0["command"] as? String)?.contains("/event/claude") == true }
                groups[i]["hooks"] = matchers
            }
            // Drop now-empty matchers.
            groups = groups.filter { !(($0["hooks"] as? [[String: Any]]) ?? []).isEmpty }
            if groups.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = groups }
        }
        json["hooks"] = hooks
        do {
            let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
            lastStatus = "Claude Code hooks removed."
        } catch {
            lastStatus = "Could not update Claude hooks: \(error.localizedDescription)"
        }
        objectWillChange.send()
    }

    // MARK: - Codex CLI hooks

    /// Codex CLI reads hooks from `~/.codex/config.toml`. We inject a `hook`
    /// entry that POSTs each event type to Pluto's event feed.
    static var codexConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/config.toml")
    }

    static var codexConfigDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    }

    static func codexHookCommand(port: Int) -> String {
        "curl -fsS -m 2 -X POST http://127.0.0.1:\(port)/event/codex -H 'Content-Type: application/json' --data-binary @- >/dev/null 2>&1"
    }

    func codexHooksInstalled() -> Bool {
        guard let text = try? String(contentsOf: Self.codexConfigURL, encoding: .utf8) else { return false }
        return text.contains("127.0.0.1:\(Prefs.shared.eventPort)/event/codex")
    }

    func installCodexHooks() {
        let dir = Self.codexConfigDir
        let cmd = Self.codexHookCommand(port: Prefs.shared.eventPort)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var toml = ""
            if FileManager.default.fileExists(atPath: Self.codexConfigURL.path) {
                toml = (try? String(contentsOf: Self.codexConfigURL, encoding: .utf8)) ?? ""
            }
            // Remove any previous managed block, then append ours.
            if let startIdx = toml.range(of: Self.codexMarker) {
                // Find end of our block: scan lines starting from the marker.
                let lines = toml[startIdx.lowerBound...].split(separator: "\n", omittingEmptySubsequences: false)
                _ = lines.prefix(5) // Our block is 5 lines: marker + [hooks] + 3 commands
                // Compute end index: marker line start + 5 line ends
                var endIdx = startIdx.lowerBound
                for _ in 0..<5 {
                    if endIdx < toml.endIndex, let nextNL = toml[endIdx...].firstIndex(of: "\n") {
                        endIdx = toml.index(after: nextNL)
                    } else {
                        endIdx = toml.endIndex
                        break
                    }
                }
                toml.removeSubrange(startIdx.lowerBound..<endIdx)
            }
            let section = """
            # --- Pluto hooks (managed) ---
            [hooks]
            user_prompt_submitted = ["\(cmd)"]
            agent_completed = ["\(cmd)"]
            notification = ["\(cmd)"]
            """
            if !toml.isEmpty && !toml.hasSuffix("\n") { toml += "\n" }
            toml += "\n" + section + "\n"
            try toml.write(to: Self.codexConfigURL, atomically: true, encoding: .utf8)
            lastStatus = "Codex CLI hooks installed → \(Self.codexConfigURL.path)"
        } catch {
            lastStatus = "Could not install Codex hooks: \(error.localizedDescription)"
        }
        objectWillChange.send()
    }

    /// Marker comment for the managed block.
    private static let codexMarker = "# --- Pluto hooks (managed) ---"

    func removeCodexHooks() {
        guard var toml = try? String(contentsOf: Self.codexConfigURL, encoding: .utf8) else { return }
        guard let startIdx = toml.range(of: Self.codexMarker) else {
            lastStatus = "No Codex hooks to remove."
            objectWillChange.send()
            return
        }
        // Remove our 5-line managed block.
        var endIdx = startIdx.lowerBound
        for _ in 0..<5 {
            if endIdx < toml.endIndex, let nextNL = toml[endIdx...].firstIndex(of: "\n") {
                endIdx = toml.index(after: nextNL)
            } else {
                endIdx = toml.endIndex
                break
            }
        }
        toml.removeSubrange(startIdx.lowerBound..<endIdx)
        do {
            try toml.write(to: Self.codexConfigURL, atomically: true, encoding: .utf8)
            lastStatus = "Codex CLI hooks removed."
        } catch {
            lastStatus = "Could not remove Codex hooks: \(error.localizedDescription)"
        }
        objectWillChange.send()
    }

    // MARK: - Gemini CLI plugin

    /// Gemini CLI supports a JSON plugin spec at ~/.gemini/plugins/pluto.json
    /// that forwards events to an HTTP endpoint.
    static var geminiPluginURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/plugins/pluto.json")
    }

    static func geminiPluginInstalled() -> Bool {
        FileManager.default.fileExists(atPath: Self.geminiPluginURL.path)
    }

    static func geminiPluginIsCurrent() -> Bool {
        guard let text = try? String(contentsOf: Self.geminiPluginURL, encoding: .utf8) else { return false }
        return text.contains("127.0.0.1:\(Prefs.shared.eventPort)")
    }

    func installGeminiPlugin() {
        let dir = Self.geminiPluginURL.deletingLastPathComponent()
        let plugin: [String: Any] = [
            "name": "pluto",
            "version": "1.0.0",
            "description": "Pluto notifier for Gemini CLI",
            "events": ["user_prompt", "agent_end", "notification"],
            "endpoint": [
                "url": "http://127.0.0.1:\(Prefs.shared.eventPort)/event/gemini",
                "method": "POST",
                "headers": ["Content-Type": "application/json"]
            ]
        ]
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: plugin, options: [.prettyPrinted])
            try data.write(to: Self.geminiPluginURL, options: .atomic)
            lastStatus = "Gemini CLI plugin installed → \(Self.geminiPluginURL.path)"
        } catch {
            lastStatus = "Could not install Gemini plugin: \(error.localizedDescription)"
        }
        objectWillChange.send()
    }

    func removeGeminiPlugin() {
        try? FileManager.default.removeItem(at: Self.geminiPluginURL)
        lastStatus = "Gemini CLI plugin removed."
        objectWillChange.send()
    }
}
