import SwiftUI

struct AudenLyricSkeleton: View {
    let reduceMotion: Bool

    private let blocks: [[CGFloat]] = [
        [0.97, 0.54], [0.92, 0.99, 0.41], [0.68], [0.95, 0.73], [0.89, 0.96, 0.37],
    ]

    var body: some View {
        GeometryReader { viewport in
            let width = max(0, viewport.size.width - 60)
            if reduceMotion {
                rows(width: width, alpha: 0.22)
            } else {
                TimelineView(.animation(minimumInterval: 1 / 30)) { time in
                    let phase = time.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
                    rows(width: width, alpha: 0.16 + 0.12 * (0.5 - 0.5 * cos(phase * 2 * .pi)))
                }
            }
        }
        .padding(.horizontal, 30)
        .padding(.top, 40)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading lyrics")
    }

    private func rows(width: CGFloat, alpha: Double) -> some View {
        VStack(alignment: .leading, spacing: 35) {
            ForEach(blocks.indices, id: \.self) { index in
                VStack(alignment: .leading, spacing: 15) {
                    ForEach(blocks[index].indices, id: \.self) { line in
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.white.opacity(alpha))
                            .frame(width: width * blocks[index][line], height: 26)
                    }
                }
            }
        }
    }
}
