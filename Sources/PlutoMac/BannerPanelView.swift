import SwiftUI

/// The hanging note: "OpenCode is done · 4:12".
struct BannerPanelView: View {
    @ObservedObject var controller: BannerController

    var body: some View {
        Group {
            if let note = controller.note {
                HStack(spacing: 8) {
                    ZStack {
                        Circle().fill(note.agent.color)
                        Image(systemName: note.agent.symbol)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 18, height: 18)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(note.title)                 // "OpenCode is done"
                            .font(.system(size: 12, weight: .semibold))
                        if let detail = note.detail, !detail.isEmpty {
                            Text(detail)                 // "Done in 4:12"
                                .font(.system(size: 10))
                                .foregroundStyle(Color.white.opacity(0.7))
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
            }
        }
        .frame(width: 320, height: 46)
        .background(
            RoundedCorners(radius: 10, corners: [.bottomLeft, .bottomRight])
                .fill(Color.black)
                .grayscale(0)
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: controller.note)
    }
}
