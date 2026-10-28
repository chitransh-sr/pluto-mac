import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A macOS-Settings-style window (Pluto's Settings on Windows → System Settings cards).
struct SettingsPanelRoot: View {
    @ObservedObject var model: AppModel

    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            AgentsTab()
                .tabItem { Label("Agents", systemImage: "sparkles") }
            RelaysTab()
                .tabItem { Label("Hooks & plugins", systemImage: "cable.connector") }
            SoundTab()
                .tabItem { Label("Sound", systemImage: "speaker.wave.2") }
            TodoSettingsTab()
                .tabItem { Label("To Do", systemImage: "checklist") }
            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 460, height: 470)
    }
}

// MARK: - General

struct GeneralTab: View {
    @ObservedObject private var prefs = Prefs.shared

    var body: some View {
        Form {
            Section("Where Pluto lives") {
                Picker("Placement", selection: $prefs.location) {
                    ForEach(Prefs.Location.allCases) { l in
                        Text(l.label).tag(l)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Picker("Size", selection: $prefs.size) {
                    ForEach(Prefs.Size.allCases) { s in
                        Text(s.label).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Toggle("Pop when you point at it", isOn: $prefs.hoverPop)
            }

            Section {
                Toggle("Launch Pluto when you log in", isOn: $prefs.launchAtLogin)
            } footer: {
                Text("Pluto never takes focus while it is small — typing stays where you left it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Agents

struct AgentsTab: View {
    @ObservedObject private var prefs = Prefs.shared

    var body: some View {
        Form {
            Section("Agents to watch") {
                ForEach(AgentKind.all) { agent in
                    Toggle(isOn: Binding(
                        get: { prefs.isWatching(agent) },
                        set: { prefs.setWatching(agent, $0) }
                    )) {
                        HStack(spacing: 8) {
                            ZStack {
                                Circle().fill(agent.color)
                                Image(systemName: agent.symbol)
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                            .frame(width: 18, height: 18)
                            Text(agent.displayName)
                        }
                    }
                }
            }

            Section("Local event feed") {
                Stepper(value: Binding(
                    get: { prefs.eventPort },
                    set: { prefs.eventPort = $0 }
                ), in: 1025...65535) {
                    Text("Port: \(prefs.eventPort)")
                } onEditingChanged: { editing in
                    if !editing {
                        Task { @MainActor in
                            AppModel.shared.restartEventServer()
                        }
                    }
                }
                Button("Test connection") {
                    Task { @MainActor in AppModel.shared.restartEventServer(); AppModel.shared.restartOpenCodeTap() }
                }
                Text("Hooks and the OpenCode plugin post here. Pluto also auto-attaches to your OpenCode service server on 127.0.0.1 — no restart needed for desktop sessions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Hooks & plugins

struct RelaysTab: View {
    @ObservedObject private var relay = RelayInstaller.shared
    @ObservedObject private var prefs = Prefs.shared

    var body: some View {
        Form {
            Section("OpenCode") {
                relayRow(
                    installed: relay.opencodePluginInstalled(),
                    current: relay.opencodePluginIsCurrent(),
                    path: RelayInstaller.opencodePluginURL.path,
                    install: "Install plugin",
                    installAction: { relay.installOpenCodePlugin() },
                    removeAction: { relay.removeOpenCodePlugin() },
                    note: "A global OpenCode plugin in ~/.config/opencode/plugins. Sessions, approvals and errors flow into Pluto live. Restart open OpenCode sessions after installing."
                )
            }

            Section("Claude Code") {
                relayRow(
                    installed: relay.claudeHooksInstalled(),
                    current: relay.claudeHooksInstalled(),
                    path: RelayInstaller.claudeSettingsURL.path,
                    install: "Install hooks",
                    installAction: { relay.installClaudeHooks() },
                    removeAction: { relay.removeClaudeHooks() },
                    note: "Adds UserPromptSubmit / Stop / Notification hooks to ~/.claude/settings.json (original kept as settings.json.before-pluto). Codex, Gemini, Cursor and the rest are still spotted by the process scanner — they just share less detail."
                )
            }

            if !relay.lastStatus.isEmpty {
                Section {
                    Text(relay.lastStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func relayRow(installed: Bool, current: Bool, path: String,
                          install installLabel: String,
                          installAction: @escaping () -> Void,
                          removeAction: @escaping () -> Void,
                          note: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: installed ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(installed ? Color.green : Color.secondary)
                Text(installed ? (current ? "Installed" : "Installed (update available)") : "Not installed")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Button(installLabel) { installAction() }
                Button("Remove", role: .destructive) { removeAction() }
                    .disabled(!installed)
            }
            Text(note)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Sound

struct SoundTab: View {
    @ObservedObject private var prefs = Prefs.shared
    @ObservedObject private var chime = Chime.shared

    var body: some View {
        Form {
            Section("Each moment has its own sound") {
                ForEach(Prefs.Moment.allCases) { moment in
                    Picker(moment.label, selection: Binding(
                        get: { prefs.soundChoice(for: moment) },
                        set: { prefs.soundChoices[moment.rawValue] = $0.rawValue }
                    )) {
                        ForEach(Prefs.SoundChoice.allCases) { c in
                            Text(c.label).tag(c)
                        }
                    }
                }
            }

            Section {
                Slider(value: $prefs.soundVolume, in: 0...1) {
                    Text("Volume")
                } minimumValueLabel: {
                    Image(systemName: "speaker.fill").font(.caption2)
                } maximumValueLabel: {
                    Image(systemName: "speaker.wave.3.fill").font(.caption2)
                }

                Button("Test sound") {
                    chime.play(.done)
                }
            } footer: {
                Text("“Custom file” uses <moment>.wav in \(Chime.soundsFolder.path)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Choose a WAV for the selected moment…") { pickCustomSound() }
            }
        }
        .formStyle(.grouped)
    }

    private func pickCustomSound() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio]
        panel.begin { resp in
            guard resp == .OK, let url = panel.url else { return }
            try? FileManager.default.createDirectory(at: Chime.soundsFolder, withIntermediateDirectories: true)
            let dest = Chime.soundsFolder.appendingPathComponent("done.wav")
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.copyItem(at: url, to: dest)
            chime.reloadCustomSounds()
        }
    }
}

// MARK: - To Do

struct TodoSettingsTab: View {
    @ObservedObject private var prefs = Prefs.shared
    @ObservedObject private var todos = TodoStore.shared

    var body: some View {
        Form {
            Section("A new day starts at") {
                Picker("Hour", selection: $prefs.todoDayStartHour) {
                    ForEach(0...9, id: \.self) { h in
                        Text(h == 0 ? "midnight" : "\(h):00").tag(h)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section("Checked tasks") {
                Picker("Move to bottom", selection: $prefs.checkedBehavior) {
                    ForEach(Prefs.CheckedBehavior.allCases) { b in
                        Text(b.label).tag(b)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            Section("History keeps") {
                Picker("Retention", selection: $prefs.historyRetention) {
                    ForEach(Prefs.HistoryRetention.allCases) { r in
                        Text(r.label).tag(r)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            Section {
                Button("Start a new day now") { todos.startNewDayNow() }
                Button("Uncheck all") { todos.uncheckAll() }
            } footer: {
                Text("Saved right away to \(TodoStore.fileURL.path)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: prefs.historyRetention.rawValue) { _ in
            todos.save()
        }
    }
}

// MARK: - About

struct AboutTab: View {
    var body: some View {
        Form {
            Section("Pluto for Mac · 0.2") {
                Text("A little bot that lives at the top of your screen and keeps an eye on your AI coding agents — with a daily To Do. A Swift port of Pluto for Windows.")
                    .font(.callout)
                Button("Open the GitHub project") {
                    if let url = URL(string: "https://github.com/raktim-yoddha/pluto") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }

            Section("Privacy") {
                Text("Everything stays on your Mac. Sessions are kept in memory only: agent, project folder name and a few words of the current step. Prompts, file contents and command output are never stored. The only network Pluto touches is 127.0.0.1 for its own event feed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("License") {
                Text("MIT — adapted from Pluto (Windows) by raktim-yoddha.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
