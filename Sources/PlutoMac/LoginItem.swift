import ServiceManagement

/// "Start with Mac" — the same switch Pluto has for Windows, via SMAppService.
@MainActor
enum LoginItem {
    static func set(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // App not yet in /Applications can fail; ignore quietly.
        }
    }

    static func isRegistered() -> Bool {
        SMAppService.mainApp.status == .enabled
    }
}
