#if os(iOS)
import SwiftUI

/// The phone sheet has a system pan recognizer. The full-screen cover uses its
/// own grabber, outside the scrolling lyrics, queue and transport controls.
struct PlayerDragDismissal: ViewModifier {
    let enabled: Bool
    let dismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var pull: CGFloat = 0
    @State private var releasedOffset: CGFloat?

    func body(content: Content) -> some View {
        if enabled {
            GeometryReader { geometry in
                content
                    .overlay(alignment: .top) { grabber(height: geometry.size.height) }
                    .offset(y: releasedOffset ?? pull)
                    .animation(pull == 0 && releasedOffset == nil ? Motion.playerDragReturn(reduceMotion) : nil, value: pull)
            }
        } else {
            content
        }
    }

    private func grabber(height: CGFloat) -> some View {
        Button(action: dismiss) {
            Capsule()
                .fill(.white.opacity(0.35))
                .frame(width: 42, height: 5)
                .padding(.top, 10)
                .frame(width: 96, height: 36, alignment: .top)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
        .gesture(
            DragGesture(minimumDistance: 10, coordinateSpace: .global)
                .updating($pull) { value, state, transaction in
                    transaction.animation = nil
                    state = PlayerDismissal.isDownward(value.translation) ? travel(value.translation.height) : 0
                }
                .onEnded { value in
                    guard PlayerDismissal.shouldDismiss(
                        translation: value.translation,
                        projected: value.predictedEndTranslation,
                        height: height
                    ) else { return }
                    // Hold the release position while SwiftUI hands the cover
                    // back to its presentation controller.
                    releasedOffset = travel(value.translation.height)
                    dismiss()
                }
        )
    }

    private func travel(_ distance: CGFloat) -> CGFloat {
        reduceMotion ? 0 : max(0, distance)
    }
}
#endif
