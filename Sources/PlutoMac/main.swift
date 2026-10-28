import AppKit

// Pluto for Mac — entry point. AppKit lifecycle (not SwiftUI @main) so the
// panels can be tuned precisely: they never take focus while Pluto is small.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
