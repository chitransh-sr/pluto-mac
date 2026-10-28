import AppKit
import Combine
import SwiftUI

/// Sizing numbers for Pluto's body, mirroring Pluto's Small / Medium / Large.
@MainActor
enum Placement {
    static let expandedSize = CGSize(width: 440, height: 440)

    static func bodySize(location: Prefs.Location, size: Prefs.Size) -> CGSize {
        switch (location, size) {
        case (.notch, .small): return CGSize(width: 72, height: 24)
        case (.notch, .medium): return CGSize(width: 84, height: 26)
        case (.notch, .large): return CGSize(width: 96, height: 28)
        case (.floating, .small): return CGSize(width: 100, height: 24)
        case (.floating, .medium): return CGSize(width: 120, height: 26)
        case (.floating, .large): return CGSize(width: 140, height: 28)
        }
    }

    static func bestScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        for s in NSScreen.screens {
            if s.frame.contains(mouse) { return s }
        }
        return NSScreen.main
    }

    static func centerX(for location: Prefs.Location, screen: NSScreen, bodyWidth: CGFloat) -> (center: CGFloat, bounds: ClosedRange<CGFloat>) {
        let mid = screen.frame.midX
        let margin = bodyWidth / 2 + 24
        let lo = mid - (screen.frame.width / 2 - margin)
        let hi = mid + (screen.frame.width / 2 - margin)
        let offset = location == .notch ? Prefs.shared.notchX : Prefs.shared.floatX
        let center = mid + offset
        return (min(max(center, lo), hi), lo...hi)
    }
}

/// The see-through, always-on-top panel that hosts the pet + its list.
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class NotchPanelController: NSObject, NSWindowDelegate, ObservableObject {
    @Published var expanded = false
    var hoverPopped = false

    let panel = NotchPanel(
        contentRect: NSRect(x: 0, y: 0, width: 200, height: 40),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )

    var appModel: AppModel!
    private var hosting: NSHostingView<PetRootView>?
    private var subscriptions: [AnyCancellable] = []
    private var outsideMonitor: Any?
    private var autoCollapseTask: Task<Void, Never>?
    private(set) var lastInteract = Date()

    var screen: NSScreen {
        Placement.bestScreen() ?? NSScreen.main ?? NSScreen.screens[0]
    }

    func install(model: AppModel) {
        appModel = model

        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.delegate = self

        let root = PetRootView(model: model, controller: self)
        let hv = NSHostingView<PetRootView>(rootView: root)
        hv.autoresizingMask = [.width, .height]
        hosting = hv
        panel.contentView = hv
        applyContentSize()

        place(expanded: false, animate: false)

        // Any preference change → re-place at the right size & position.
        Prefs.shared.objectWillChange
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.place(expanded: self?.expanded ?? false, animate: true) }
            .store(in: &subscriptions)

        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                self?.place(expanded: self?.expanded ?? false, animate: false)
            }
            .store(in: &subscriptions)

        panel.makeKeyAndOrderFront(nil)
    }

    func applyPrefs(grandReload: Bool) {
        place(expanded: expanded, animate: false)
        if grandReload {
            let root = PetRootView(model: appModel, controller: self)
            hostContentView()?.subviews.removeAll()
            hostContentView()?.addSubview(NSHostingView<PetRootView>(rootView: root))
        }
    }

    private func applyContentSize() {
        let targetSize = expanded ? Placement.expandedSize : Placement.bodySize(location: Prefs.shared.location, size: Prefs.shared.size)
        panel.setContentSize(targetSize)
        hostContentView()?.frame = NSRect(origin: .zero, size: targetSize)
        hostContentView()?.autoresizingMask = [.width, .height]
    }

    private func hostContentView() -> NSView? { panel.contentView }

    // MARK: geometry

    func place(expanded: Bool, animate: Bool) {
        if self.expanded != expanded {
            self.expanded = expanded
            applyContentSize()
            objectWillChange.send()
        }
        let scr = screen
        let top = scr.frame.maxY
        let targetSize = expanded ? Placement.expandedSize : Placement.bodySize(location: Prefs.shared.location, size: Prefs.shared.size)
        let placement = Placement.centerX(for: Prefs.shared.location, screen: scr, bodyWidth: targetSize.width)
        // Both states pin to the top edge and grow downward.
        let frame = NSRect(x: placement.center - targetSize.width / 2,
                           y: top - targetSize.height,
                           width: targetSize.width,
                           height: targetSize.height)
        setFrameAnimated(frame, animate: animate)
    }

    private func setFrameAnimated(_ frame: NSRect, animate: Bool) {
        if animate {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.40
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.165, 0.84, 0.44, 1)
                context.allowsImplicitAnimation = true
                panel.setFrame(frame, display: true)
            })
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    // MARK: interaction from SwiftUI

    func noteInteract() {
        lastInteract = Date()
    }

    func setHoverPopped(_ popped: Bool) {
        hoverPopped = popped && Prefs.shared.hoverPop
        objectWillChange.send()
    }

    func toggle() {
        if expanded { collapse() } else { expand() }
    }

    func expand() {
        guard !expanded else { return }
        expanded = true
        applyContentSize()
        objectWillChange.send()
        noteInteract()
        place(expanded: true, animate: true)
        scheduleAutoCollapse()
        installOutsideMonitor()
    }

    func collapse() {
        guard expanded else { return }
        expanded = false
        applyContentSize()
        objectWillChange.send()
        place(expanded: false, animate: true)
        removeOutsideMonitor()
        autoCollapseTask?.cancel()
        autoCollapseTask = nil
    }

    private func scheduleAutoCollapse() {
        autoCollapseTask?.cancel()
        autoCollapseTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, self.expanded else { break }
                let typing = self.panel.firstResponder is NSTextView
                if Date().timeIntervalSince(self.lastInteract) > 4.5 && !typing {
                    await MainActor.run { self.collapse() }
                    break
                }
            }
        }
    }

    private func installOutsideMonitor() {
        removeOutsideMonitor()
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.expanded, self.panel.isVisible else { return }
                let mouse = NSEvent.mouseLocation
                let frame = self.panel.frame.insetBy(dx: -6, dy: -6)
                if !frame.contains(mouse) {
                    self.collapse()
                }
            }
        }
    }

    private func removeOutsideMonitor() {
        if let m = outsideMonitor {
            NSEvent.removeMonitor(m)
            outsideMonitor = nil
        }
    }

    // MARK: dragging — drop near the top edge to make a notch there

    private var moveSettle: Task<Void, Never>?

    func windowDidMove(_ notification: Notification) {
        // macOS has no "did end moving" delegate call; debounce until the
        // frame stops changing for a moment, then treat that as drag end.
        moveSettle?.cancel()
        let frame = panel.frame
        moveSettle = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 280_000_000)
            await MainActor.run {
                guard let self, !Task.isCancelled, self.panel.frame == frame else { return }
                self.finishDrag(at: frame)
            }
        }
    }

    private func finishDrag(at frame: NSRect) {
        let scr = screen
        let gap = frame.maxY - scr.frame.maxY
        let center = frame.midX
        let mid = scr.frame.midX
        if abs(gap) <= 34 {
            Prefs.shared.location = .notch
            let margin = Placement.bodySize(location: .notch, size: Prefs.shared.size).width / 2 + 24
            let maxOff = scr.frame.width / 2 - margin
            Prefs.shared.notchX = Double(min(max(center - mid, -maxOff), maxOff))
        } else {
            Prefs.shared.location = .floating
            let margin = Placement.bodySize(location: .floating, size: Prefs.shared.size).width / 2 + 24
            let maxOff = scr.frame.width / 2 - margin
            Prefs.shared.floatX = Double(min(max(center - mid, -maxOff), maxOff))
        }
        place(expanded: expanded, animate: false)
    }

    func windowDidResize(_ notification: Notification) {
        // SwiftUI hosting view auto-resizes with autoresizing mask; nothing to do.
    }
}

/// The short note that hangs from the top edge for three seconds.
@MainActor
final class BannerController: ObservableObject {
    struct Note: Identifiable, Equatable {
        let id = UUID()
        var agent: AgentKind
        var title: String
        var detail: String?
    }

    @Published private(set) var note: Note?

    private let panel = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 320, height: 46),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    private var hideTask: Task<Void, Never>?
    private var hosting: NSHostingView<BannerPanelView>?

    init() {
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.ignoresMouseEvents = true
        hosting = NSHostingView<BannerPanelView>(rootView: BannerPanelView(controller: self))
        panel.contentView = hosting
    }

    func show(agent: AgentKind, title: String, detail: String?) {
        note = Note(agent: agent, title: title, detail: detail)
        objectWillChange.send()

        // Host replacement for the new note, then slide in.
        let v = BannerPanelView(controller: self)
        let hv = NSHostingView<BannerPanelView>(rootView: v)
        panel.contentView = hv

        let scr = Placement.bestScreen() ?? NSScreen.main!
        let top = scr.frame.maxY
        let petH = Placement.bodySize(location: Prefs.shared.location, size: Prefs.shared.size).height
        let result = Placement.centerX(for: Prefs.shared.location, screen: scr, bodyWidth: 320)
        let width: CGFloat = 320
        let height: CGFloat = 46
        let restY = top - petH - 6 - height
        let startFrame = NSRect(x: result.center - width / 2, y: top + 4, width: width, height: height)
        panel.setFrame(startFrame, display: false)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.30
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 0.84, 0.44, 1)
            ctx.allowsImplicitAnimation = true
            panel.setFrame(NSRect(x: startFrame.minX, y: restY, width: width, height: height), display: true)
        }

        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                guard let self else { return }
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.30
                    ctx.allowsImplicitAnimation = true
                    self.panel.setFrame(startFrame, display: true)
                }, completionHandler: {
                    self.panel.orderOut(nil)
                    self.note = nil
                    self.objectWillChange.send()
                })
            }
        }
    }
}
