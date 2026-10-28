import AppKit
import SwiftUI

/// Pluto's whole pet UI in one place:
///  - collapsed → the notch/black body with the blinking dotted-eyes face
///  - expanded → a dark HUD sheet: the Notch header (face + title), the tab bar,
///    then the agent board / To Do, with a status footer.
struct PetRootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var controller: NotchPanelController
    @ObservedObject private var store = SessionStore.shared
    @ObservedObject private var prefs = Prefs.shared

    var body: some View {
        if controller.expanded {
            ExpandedPanel()
        } else {
            NotchBodyView(store: store, prefs: prefs, popped: $controller.hoverPopped)
                .onTapGesture {
                    controller.noteInteract()
                    controller.toggle()
                }
                .onTapGesture(count: 2) {
                    controller.expand()
                }
                .onHover { hovering in
                    controller.noteInteract()
                    controller.setHoverPopped(hovering)
                }
        }
    }
}

// MARK: - Collapsed

struct NotchBodyView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var prefs: Prefs
    @Binding var popped: Bool

    private var size: CGSize {
        var s = Placement.bodySize(location: prefs.location, size: prefs.size)
        s.height = max(20, s.height)
        s.width = max(56, s.width)
        return s
    }

    var body: some View {
        BotFaceView(
            bodySize: size,
            state: store.globalState,
            happy: Date() < store.expressionUntil,
            popped: popped,
            notchShape: prefs.location == .notch
        )
        .frame(width: size.width, height: size.height)
        .background(
            Group {
                if prefs.location == .notch {
                    Color.clear
                } else {
                    RoundedRectangle(cornerRadius: size.height * 0.48, style: .continuous)
                        .fill(Color.black.opacity(0.5))
                }
            }
        )
        .clipShape(
            prefs.location == .notch
                ? AnyShape(RoundedCorners(radius: 5, corners: [.bottomLeft, .bottomRight]))
                : AnyShape(RoundedRectangle(cornerRadius: size.height * 0.5))
        )
        .overlay(
            (prefs.location == .notch
                ? AnyShape(RoundedCorners(radius: 5, corners: [.bottomLeft, .bottomRight]))
                : AnyShape(RoundedRectangle(cornerRadius: size.height * 0.5)))
            .stroke(Color.white.opacity(0.18), lineWidth: 0.6)
        )
        .shadow(color: .black.opacity(0.35), radius: 7, x: 0, y: 2)
        .animation(.easeInOut(duration: 0.25), value: store.globalState)
        .animation(.easeInOut(duration: 0.25), value: popped)
        .overlay(alignment: .bottom) {
            if store.workingCount > 0 {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.systemBlue.opacity(0.65))
                    .frame(width: min(20, size.width * 0.22), height: 2.2)
                    .offset(y: -1)
                    .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: store.workingCount)
            }
        }
        .overlay(alignment: .topTrailing) {
            if store.needsAttention {
                Circle()
                    .fill(Color.yellow.opacity(0.9))
                    .frame(width: 7, height: 7)
                    .offset(x: -6, y: 6)
                    .animation(.easeIn(duration: 0.45).repeatForever(autoreverses: true), value: store.needsAttention)
            }
        }
    }
}

// MARK: - Expanded HUD sheet

struct ExpandedPanel: View {
    @ObservedObject private var store = SessionStore.shared
    @ObservedObject private var tap = OpenCodeTap.shared
    @State private var tab: Tab = .all

    enum Tab: String, CaseIterable, Identifiable {
        case all = "All agents"
        case todo = "To Do"
        var id: String { rawValue }
    }

    private let width: CGFloat = 440
    private let height: CGFloat = 440

    var body: some View {
        VStack(spacing: 0) {
            header
            tabBar
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
            switch tab {
            case .all: AgentList(tap: tap)
            case .todo: TodoTabView()
            }
            footer
        }
        .frame(width: width, height: height)
        .background(
            VisualEffectBlur(material: .hudWindow)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 24, x: 0, y: 12)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // The top "notch band" — solid black, home to the face + title + gear.
    @ViewBuilder
    private var header: some View {
        HStack(spacing: 12) {
            BotFaceView(
                bodySize: CGSize(width: 48, height: 22),
                state: store.globalState,
                happy: Date() < store.expressionUntil,
                popped: false,
                notchShape: false
            )
            Text("Pluto")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.95))
            Spacer()
            if store.activeCount > 0 || store.needsAttention {
                Text(store.needsAttention ? "needs you" : "\(store.activeCount) active")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(store.needsAttention ? Color.yellow.opacity(0.9) : Color.systemBlue.opacity(0.9))
                    .padding(.trailing, 4)
            }
            if !tap.connected && tap.watchedPort != nil {
                Text("reconnecting…")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.orange.opacity(0.8))
            }
            Button {
                AppModel.shared.showSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.75))
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 48)
        .padding(.horizontal, 16)
        .background(
            LinearGradient(gradient: Gradient(colors: [
                Color.black.opacity(0.88),
                Color.black.opacity(0.42)
            ]), startPoint: .top, endPoint: .bottom)
        )
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
                .offset(y: 47),
            alignment: .bottom
        )
    }

    private var tabBar: some View {
        HStack(spacing: 24) {
            ForEach(Tab.allCases) { t in
                VStack(spacing: 5) {
                    Text(t.rawValue)
                        .font(.system(size: 12.5, weight: tab == t ? .semibold : .regular, design: .rounded))
                        .foregroundStyle(tab == t ? Color.white.opacity(0.92) : Color.white.opacity(0.5))
                    Capsule()
                        .fill(tab == t ? Color.white.opacity(0.85) : Color.clear)
                        .frame(width: 22, height: 2.5)
                }
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { tab = t }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(tap.connected ? Color.systemGreen : Color.white.opacity(0.3))
                    .frame(width: 7, height: 7)
                    .shadow(color: tap.connected ? Color.systemGreen.opacity(0.5) : .clear, radius: 2)
                if let p = tap.watchedPort {
                    Text("OpenCode · :\(p) · \(tap.connected ? "live" : "connecting")")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.6))
                } else {
                    Text("OpenCode · starting…")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if store.activeCount > 0 {
                    Text("\(store.activeCount) active")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.systemBlue.opacity(0.85))
                }
                Text("Pluto v0.2 · \(store.sessions.values.filter { $0.source == .event }.count) tracked · \(tap.eventsReceived) events")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.38))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Rectangle()
                .fill(LinearGradient(
                    gradient: Gradient(colors: [Color.black.opacity(0.35), Color.clear]),
                    startPoint: .top, endPoint: .bottom))
        )
    }
}

// MARK: - Agent list

struct AgentList: View {
    @ObservedObject private var store = SessionStore.shared
    @ObservedObject private var tap: OpenCodeTap

    init(tap: OpenCodeTap = OpenCodeTap.shared) {
        _tap = ObservedObject(wrappedValue: tap)
    }

    var rows: [Session] {
        // Only hide a process-scan row when there's a *live* event session
        // (working or needs-you) for the same agent — so your currently-active
        // TUI (caught by the process scan) stays visible even when the SSE tap
        // has replayed historical idle sessions for that agent.
        let liveAgents = Set(
            store.sessions.values
                .filter { $0.source == .event && ($0.state == .working || $0.state == .needsYou) && $0.lastActivity.timeIntervalSinceNow > -900 }
                .map { $0.agent.id }
        )
        let filtered = store.sortedSessions().filter { session in
            // Scan rows for agents we have a live event session on get replaced
            // by that richer event row.
            if session.source == .scan, liveAgents.contains(session.agent.id) { return false }
            // Drop process-scan hits from GUI-only apps (Cursor editor helpers) —
            // they have no resolved project folder and aren't real agent sessions.
            if session.source == .scan,
               session.agent.isGUI,
               session.projectFolder?.isEmpty ?? true { return false }
            // Drop any scan row that couldn't resolve a cwd (helper processes, etc.)
            if session.source == .scan,
               session.projectFolder?.isEmpty ?? true { return false }
            return true
        }
        // Collapse multiple process-scan rows for the same agent (e.g. Cursor's
        // many helper processes) into a single most-recent row, so one running
        // agent = one line. Real per-session event rows are preserved as-is.
        var seen: Set<String> = []
        var out: [Session] = []
        for s in filtered {
            if s.source == .scan {
                if seen.contains(s.agent.id) { continue }
                seen.insert(s.agent.id)
            }
            out.append(s)
        }
        return out
    }

    var body: some View {
        let rows = rows
        if rows.isEmpty {
            empty
        } else {
            ScrollView {
                LazyVStack(spacing: 6, pinnedViews: []) {
                    ForEach(rows) { s in
                        SessionRowView(session: s) {
                            AppModel.shared.activateSession(s)
                        }
                    }
                    if rows.count <= 3 {
                        Text("All caught up — no other agents running")
                            .font(.system(size: 10.5, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.35))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 12)
                    }
                    Color.clear
                        .frame(height: 60)
                        .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 12)
            }
            .frame(maxHeight: .infinity)
            .background(Color.black.opacity(0.15))
        }
    }

    private var `empty`: some View {
        VStack(spacing: 18) {
            BotFaceView(
                bodySize: CGSize(width: 100, height: 50),
                state: .idle,
                happy: false,
                popped: false,
                notchShape: false
            )
            Text("All quiet")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.9))
            Text("No agents running.\nStart a supported coding agent to see it appear here.")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .fixedSize()
            if !tap.connected {
                Button("Reconnect OpenCode") {
                    AppModel.shared.restartOpenCodeTap()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(Color.systemBlue)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SessionRowView: View {
    var session: Session
    var action: () -> Void
    @State private var isHovering = false

    private var stateColor: Color {
        switch session.state {
        case .needsYou: return .yellow
        case .failed: return .red
        case .working: return .systemBlue
        case .idle: return .secondary
        }
    }

    private var title: String {
        let t = session.title?.nilIfEmpty ?? session.projectFolder
        return t?.isEmpty == false ? "\(session.agent.displayName) — \(t!)" : session.agent.displayName
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Avatar with subtle glow
                ZStack {
                    Circle().fill(session.agent.color)
                    Image(systemName: session.agent.symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 26, height: 26)
                .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 0.5))
                .shadow(color: session.agent.color.opacity(0.35), radius: isHovering ? 3 : 1.5)

                // Content
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        // Source indicator: blue dot for live SSE, gray for scan
                        Circle()
                            .fill(session.source == .event ? Color.systemBlue : Color.gray)
                            .frame(width: 5, height: 5)
                            .opacity(session.source == .event ? 0.9 : 0.45)
                        Text(title)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }

                    // Primary caption: state + project + duration
                    Text(session.stateCaption)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(session.state == .working
                                         ? Color.systemBlue.opacity(0.9)
                                         : Color.secondary)
                        .lineLimit(1)

                    // Secondary: snippet / current activity
                    if session.snippet?.isEmpty == false {
                        Text(session.snippet!)
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.55))
                            .lineLimit(1)
                            .textSelection(.enabled)
                    }

                    // Project path detail (scan sessions)
                    if session.source == .scan, let folder = session.projectFolder, !folder.isEmpty {
                        Text(folder)
                            .font(.system(size: 9.5, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.38))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                // Status indicator + age
                VStack(alignment: .trailing, spacing: 4) {
                    statusIndicator
                    Text(session.workingDurationText ?? session.ageText)
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(session.state == .working
                                         ? Color.systemBlue.opacity(0.85)
                                         : Color.secondary)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .background(
            Group {
                if isHovering {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                } else if session.state == .needsYou {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.yellow.opacity(0.06))
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.clear)
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .inset(by: 0.5)
                .stroke(stateColor.opacity(session.state == .needsYou ? 0.55 : 0.18),
                        lineWidth: session.state == .needsYou ? 1.5 : 0.5)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovering = hovering }
        }
    }

    @ViewBuilder private var statusIndicator: some View {
        HStack(spacing: 6) {
            if session.state == .working {
                // Continuous spin via TimelineView — never restarts, no @State leak.
                TimelineView(.animation) { ctx in
                    Image(systemName: "circle.dashed.circle")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(stateColor)
                        .frame(width: 22, height: 22)
                        .rotationEffect(.degrees(
                            ctx.date.timeIntervalSinceReferenceDate
                                .truncatingRemainder(dividingBy: 1.2) / 1.2 * 360
                        ))
                }
            } else if session.state == .needsYou {
                Image(systemName: "exclamationmark.shield")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(stateColor)
                    .frame(width: 22, height: 22)
            } else {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(stateColor)
            }

            // State pill
            Text(session.stateLabel)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(stateColor.opacity(0.18)))
                .foregroundStyle(stateColor)
        }
    }
}

// MARK: - Session state helpers

private extension Session {
    var durationTextSinceWorking: String? {
        guard let start = workingSince else { return nil }
        let total = Int(Date().timeIntervalSince(start))
        guard total >= 0 else { return nil }
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    var captionText: String {
        if state == .working {
            // Working state always shows status + location + duration
            let dur = durationTextSinceWorking
            var parts: [String] = [stateLabel]
            if let p = projectFolder, !p.isEmpty { parts.append("in \(p)") }
            if let d = dur { parts.append(d) }
            return parts.joined(separator: " · ")
        }
        // For non-working states, show snippet or status
        if let snippet = snippet, !snippet.isEmpty { return snippet }
        switch source {
        case .scan:
            if let p = projectFolder, !p.isEmpty { return "spotted in \(p)" }
            return "spotted by process scan"
        case .event:
            if state == .idle {
                if let d = lastDurationText, !d.isEmpty {
                    var parts: [String] = ["done · \(d)"]
                    if let p = projectFolder, !p.isEmpty { parts.append("in \(p)") }
                    return parts.joined(separator: " · ")
                }
                return "idle"
            }
            if state == .needsYou { return "needs your approval" }
            if state == .failed { return "failed" }
            return "waiting"
        }
    }

    /// Caption text used in the primary row line (always shows state + location).
    var stateCaption: String {
        if let snippet = snippet, !snippet.isEmpty {
            // When we have a snippet, still show status + location below it
            let dur = durationTextSinceWorking
            var parts: [String] = [stateLabel]
            if let p = projectFolder, !p.isEmpty { parts.append("in \(p)") }
            if let d = dur { parts.append(d) }
            return parts.joined(separator: " · ")
        }
        return captionText
    }

    /// Duration text for working sessions, or nil to fall back to ageText.
    var workingDurationText: String? {
        guard state == .working, let dur = durationTextSinceWorking else { return nil }
        return "\(dur) elapsed"
    }

    /// Human-readable source label for debug purposes.
    var sourceLabel: String {
        source == .event ? "live event" : "process scan"
    }

    var stateLabel: String {
        switch state {
        case .working where source == .scan: return "running"
        case .working: return "working"
        case .idle where lastDurationText != nil: return "done · \(lastDurationText ?? "")"
        case .idle: return "idle"
        case .needsYou: return "needs you"
        case .failed: return "failed"
        }
    }
}

// MARK: - To Do tab

struct TodoTabView: View {
    @ObservedObject private var todos = TodoStore.shared
    @State private var newTask = ""
    @State private var showHistory = false

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE d MMM"; return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            progressHeader
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
            if showHistory {
                historyList
            } else {
                taskList
            }
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
            addField
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var progressHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.12), lineWidth: 3)
                    .frame(width: 22, height: 22)
                if todos.items.count > 0 {
                    let frac = CGFloat(todos.items.filter(\.done).count) / CGFloat(todos.items.count)
                    Circle()
                        .trim(from: 0.75, to: 0.75 + 0.5 * frac)
                        .stroke(Color.systemBlue, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                        .frame(width: 22, height: 22)
                        .rotationEffect(.degrees(-135))
                }
            }
            Text("Today · \(Self.dayFormatter.string(from: Date()))")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
            Spacer()
            Text("\(todos.items.filter(\.done).count)/\(todos.items.count)")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            Button {
                withAnimation { showHistory.toggle() }
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 11))
                    .foregroundStyle(showHistory ? Color.systemBlue : .secondary)
            }
            .buttonStyle(.plain)
            .help(showHistory ? "Show tasks" : "History")
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(
            LinearGradient(gradient: Gradient(colors: [
                Color.black.opacity(0.85),
                Color.black.opacity(0.55)
            ]), startPoint: .top, endPoint: .bottom)
        )
    }

    @ViewBuilder
    private var taskList: some View {
        let items = todos.items
        if items.isEmpty {
            Text("Nothing on the list. Add today's tasks below.")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(items) { item in
                        TodoRow(
                            item: item,
                            toggleAction: { todos.toggle(item.id) },
                            deleteAction: { todos.remove(item.id) },
                            moveUp: { todos.move(item.id, offset: -1) },
                            moveDown: { todos.move(item.id, offset: 1) }
                        )
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    @ViewBuilder
    private var historyList: some View {
        if todos.history.isEmpty {
            Text("History is empty — finished days land here.")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(todos.history) { day in
                        historyCard(day: day)
                    }
                }
                .padding(.vertical, 10)
            }
        }
    }

    @ViewBuilder
    private func historyCard(day: TodoStore.HistoryDay) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(day.dayKey)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("\(day.items.filter(\.done).count)/\(day.items.count) done")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Bring back unfinished") {
                    todos.bringBackUnfinished(from: day)
                    withAnimation { showHistory = false }
                }
                .font(.system(size: 10, design: .rounded))
                .buttonStyle(.plain)
                .foregroundStyle(Color.systemBlue)
            }
            ForEach(day.items) { item in
                Text((item.done ? "✓ " : "• ") + item.text)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(item.done ? Color.secondary : Color.primary)
                    .lineLimit(1)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.05)))
    }

    private var addField: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 11))
                .foregroundStyle(Color.secondary)
            TextField("Add a task and press Return", text: $newTask)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .rounded))
                .onSubmit {
                    todos.add(newTask)
                    newTask = ""
                }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.04))
    }
}

struct TodoRow: View {
    var item: TodoStore.Item
    var toggleAction: () -> Void
    var deleteAction: () -> Void
    var moveUp: () -> Void
    var moveDown: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: toggleAction) {
                ZStack {
                    Circle().stroke(item.done ? Color.systemBlue : Color.white.opacity(0.55), lineWidth: 1.4)
                        .frame(width: 16, height: 16)
                    if item.done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color.systemBlue)
                    }
                }
            }
            .buttonStyle(.plain)

            Text(item.text)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(item.done ? .secondary : .primary)
                .strikethrough(item.done)
                .lineLimit(1)

            Spacer()

            if hovered {
                Button(role: .destructive) { deleteAction() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .onHover { isHovered in
            withAnimation(.easeInOut(duration: 0.15)) { hovered = isHovered }
        }
        .contextMenu {
            Button("Move up") { moveUp() }
            Button("Move down") { moveDown() }
            Divider()
            Button("Delete", role: .destructive) { deleteAction() }
        }
    }
}
