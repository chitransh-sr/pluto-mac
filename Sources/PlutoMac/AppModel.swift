import AppKit
import Combine
import SwiftUI

/// Wires the stores to the windows: sessions → banner + chime, settings → panels.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let notchPanel = NotchPanelController()
    let banner = BannerController()

    var settingsWindow: NSWindow?

    func install() {
        // sessions → moments
        SessionStore.shared.onMoment = { [weak self] session, moment, extra in
            guard let self else { return }
            let chime = Chime.shared
            chime.play(moment)

            let name = session.agent.displayName
            let (title, detail): (String, String?) = switch moment {
            case .start:
                ("\(name) is working", session.snippet)
            case .done:
                ("\(name) is done", session.lastDurationText.map { "Done in \($0)" } ?? nil)
            case .needsYou:
                ("\(name) needs you", session.snippet ?? "waiting for your approval")
            case .failed:
                ("\(name) failed", session.snippet)
            }
            self.banner.show(agent: session.agent, title: title, detail: detail)
        }
    }

    func noteInteract() {
        notchPanel.noteInteract()
    }

    func showSettings() {
        if let w = settingsWindow, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 470),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = "Pluto Settings"
        w.contentView = NSHostingView(rootView: SettingsPanelRoot(model: self))
        w.center()
        w.isReleasedWhenClosed = false
        w.level = .floating
        settingsWindow = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func restartEventServer() {
        EventServerHolder.shared.stop()
        EventServerHolder.shared.start()
    }

    func restartOpenCodeTap() {
        OpenCodeTap.shared.stop()
        OpenCodeTap.shared.start()
    }

    func activateSession(_ session: Session) {
        // Process-scan hits have a real PID — activate that process directly.
        if let pid = session.hostPID, pid > 1,
           let app = NSRunningApplication(processIdentifier: pid) {
            app.activate(options: [.activateAllWindows])
            notchPanel.collapse()
            return
        }
        // Event sessions (from OpenCode SSE / plugin) may not carry a PID.
        // Fall back to activating the agent's known app bundle, or the
        // most recently seen process for that agent.
        let pid = ProcessScanner.shared.lastPID(for: session.agent.id)
        if let pid, pid > 1, let app = NSRunningApplication(processIdentifier: pid) {
            app.activate(options: [.activateAllWindows])
        } else if session.agent.bundleID != nil,
                  let app = NSRunningApplication.runningApplications(
                      withBundleIdentifier: session.agent.bundleID!
                  ).first {
            app.activate(options: [.activateAllWindows])
        }
        notchPanel.collapse()
    }
}

/// Separate holder so the server survives settings-window churn.
@MainActor
final class EventServerHolder {
    static let shared = EventServerHolder()
    private let server = EventServer()
    var listening: Bool { server.listening }
    func start() { server.start() }
    func stop() { server.stop() }
}

// MARK: - App entry

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var todoTick: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let model = AppModel.shared
        model.install()

        // Start feed + scanner + OpenCode SSE tap (desktop service server).
        EventServerHolder.shared.start()
        let scanner = ProcessScanner.shared
        scanner.start()
        OpenCodeTap.shared.start()

        // 1 Hz ticker: keeps live durations and the spinner crisp.
        SessionStore.shared.startTick()

        // Keep the OpenCode plugin current on every launch: install it the first
        // time (so the pet is OpenCode-ready immediately) and silently refresh
        // it whenever the port drifts. Removing it in Settings stays respected.
        let relay = RelayInstaller.shared
        if !relay.opencodePluginInstalled() || !relay.opencodePluginIsCurrent() {
            relay.installOpenCodePlugin()
        }
        // Auto-install Claude Code + Codex hooks too — silent, non-destructive.
        if !relay.claudeHooksInstalled() {
            relay.installClaudeHooks()
        }
        if !relay.codexHooksInstalled() {
            relay.installCodexHooks()
        }
        // Gemini plugin install is optional — only if the config dir exists.
        // Users install it from Settings if they want Gemini event forwarding.
        _ = RelayInstaller.geminiPluginInstalled() // no-op check; plugin installed via Settings tab
        UserDefaults.standard.set(true, forKey: "didFirstRun")

        model.notchPanel.install(model: model)

        // To Do digest: roll the day and keep prefs-aware trimming alive.
        TodoStore.shared.rollIfNeeded()
        todoTick = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in
                TodoStore.shared.rollIfNeeded()
            }
        }

        buildStatusMenu()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func buildStatusMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "🪐"
        item.button?.toolTip = "Pluto — watching your AI agents"

        let menu = NSMenu()
        menu.addItem(withTitle: "Open the list", action: #selector(openListFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: "Settings…", action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        menu.addItem(.separator())
        let feedTitle = "Event feed on 127.0.0.1:\(Prefs.shared.eventPort)"
        let feed = NSMenuItem(title: EventServerHolder.shared.listening ? feedTitle : "\(feedTitle) — not listening",
                              action: nil, keyEquivalent: "")
        feed.isEnabled = false
        menu.addItem(feed)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Pluto", action: #selector(quitApp), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @objc private func openListFromMenu() {
        AppModel.shared.notchPanel.expand()
    }

    @objc private func openSettingsFromMenu() {
        AppModel.shared.showSettings()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
