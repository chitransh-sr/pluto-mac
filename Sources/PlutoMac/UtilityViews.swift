import AppKit
import SwiftUI

extension String {
    /// Returns nil for empty/whitespace-only strings — handy for JSON mapping.
    var nilIfEmpty: String? {
        let t = self.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

extension Color {
    static let systemGreen = Color(NSColor.systemGreen)
    static let systemBlue = Color(NSColor.systemBlue)
}

// A tiny attention dot + label used in the footer; keeps the file cohesive.
struct StatusDot: View {
    var on: Bool
    var body: some View {
        Circle()
            .fill(on ? Color.systemGreen : Color.white.opacity(0.35))
            .frame(width: 6.5, height: 6.5)
    }
}
