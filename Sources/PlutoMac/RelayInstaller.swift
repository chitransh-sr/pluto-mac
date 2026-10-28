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
}
