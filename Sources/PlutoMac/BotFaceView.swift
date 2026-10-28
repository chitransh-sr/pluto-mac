import SwiftUI

/// A rounded rectangle that only rounds chosen corners — for the notch shape.
struct RoundedCorners: Shape {
    enum Corner {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    var radius: CGFloat
    var corners: Set<Corner>

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let maxR = min(rect.width, rect.height) / 2
        let tl = corners.contains(.topLeft) ? min(radius, maxR) : 0
        let tr = corners.contains(.topRight) ? min(radius, maxR) : 0
        let br = corners.contains(.bottomRight) ? min(radius, maxR) : 0
        let bl = corners.contains(.bottomLeft) ? min(radius, maxR) : 0

        p.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        if tr > 0 {
            p.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr), radius: tr,
                     startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
        }
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        if br > 0 {
            p.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br), radius: br,
                     startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        }
        p.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        if bl > 0 {
            p.addArc(center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl), radius: bl,
                     startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        }
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        if tl > 0 {
            p.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl), radius: tl,
                     startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        }
        p.closeSubpath()
        return p
    }
}

/// Pluto's face: two eyes and a smile that blink, breathe and change with the
/// agents' state (sleeping when all is quiet, alert when something needs you).
struct BotFaceView: View {
    var bodySize: CGSize
    var state: SessionState
    var happy: Bool
    var popped: Bool
    var notchShape: Bool

    @State private var eyesOpen = true

    private var eyeColor: Color {
        switch state {
        case .needsYou: return Color(red: 1.0, green: 0.76, blue: 0.28)
        case .failed: return Color(red: 1.0, green: 0.42, blue: 0.42)
        default: return .white
        }
    }

    var body: some View {
        let w = bodySize.width
        let h = bodySize.height
        ZStack(alignment: .bottom) {
            bodyShape
                .foregroundColor(.black)
                .frame(width: w, height: h)

            GeometryReader { geo in
                let faceH = geo.size.height
                VStack(spacing: max(2, h * 0.08)) {
                    eyeSpacingView
                    smile
                        .frame(width: max(14, w * 0.20), height: max(6, h * 0.18))
                        .padding(.top, 1)
                }
                .position(x: geo.size.width / 2, y: faceH * 0.48)
                .frame(maxHeight: .infinity)
            }
            .padding(.horizontal, notchShape ? w * 0.10 : w * 0.08)
        }
        .scaleEffect(popped ? 1.055 : 1.0)
        .animation(.spring(response: 0.28, dampingFraction: 0.55), value: popped)
        .onAppear { repeatBlinkForever() }
    }

    private var bodyShape: some Shape {
        if notchShape {
            return AnyShape(RoundedCorners(radius: 6, corners: [.bottomLeft, .bottomRight]))
        }
        return AnyShape(RoundedRectangle(cornerRadius: bodySize.height * 0.48, style: .continuous))
    }

    private var eyeSpacingView: some View {
        HStack(spacing: max(7, bodySize.width * 0.09)) {
            eyeGlyph
                .foregroundColor(eyeColor)
            eyeGlyph
                .foregroundColor(eyeColor)
        }
    }

    @ViewBuilder
    private var eyeGlyph: some View {
        let eyeSize: CGFloat = max(4.2, bodySize.height * 0.20)
        if eyesOpen {
            // Agent active → round eyes; sleeping → slightly oval.
            if state == .idle || state == .failed {
                Ellipse()
                    .frame(width: eyeSize, height: eyeSize * 1.35)
            } else {
                Circle()
                    .frame(width: eyeSize, height: eyeSize)
            }
        } else {
            RoundedRectangle(cornerRadius: 1)
                .frame(width: eyeSize * 1.9, height: 1.4)
        }
    }

    private var smile: some View {
        SmilePath(droop: happy ? 0.8 : 0.45)
            .stroke(eyeColor, style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
    }

    private func repeatBlinkForever() {
        Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64.random(in: 1_800_000_000...4_600_000_000))
                if Task.isCancelled { break }
                withAnimation(.easeInOut(duration: 0.09)) { eyesOpen = false }
                try? await Task.sleep(nanoseconds: 115_000_000)
                if Task.isCancelled { break }
                withAnimation(.easeInOut(duration: 0.09)) { eyesOpen = true }
            }
        }
    }
}

private struct SmilePath: Shape {
    var droop: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.minY + rect.height * droop)
        )
        return p
    }
}
