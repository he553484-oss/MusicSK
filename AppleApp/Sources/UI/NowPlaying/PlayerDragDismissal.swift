#if os(iOS)
import SwiftUI

/// Reserve a small safe-area strip for the interactive cover grabber.
/// Lyrics, queue and transport keep their own gestures below it.
struct PlayerDragDismissal: ViewModifier {
    let enabled: Bool
    let dismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private struct Drag: Equatable {
        var acceptedDirection: Bool?
        var pull: CGFloat = 0
    }

    @GestureState private var drag = Drag()
    @State private var acceptedDirection: Bool?
    @State private var releasedOffset: CGFloat?

    func body(content: Content) -> some View {
        if enabled {
            GeometryReader { geometry in
                content
                    .padding(.top, PlayerLayout.dismissalTopSpacing)
                    .overlay(alignment: .top) { grabber(height: geometry.size.height) }
                    .offset(y: releasedOffset ?? drag.pull)
                    .animation(
                        drag.acceptedDirection == nil && releasedOffset == nil ? Motion.playerDragReturn(reduceMotion) : nil,
                        value: drag.pull
                    )
                    .onChange(of: drag.acceptedDirection) { _, direction in
                        if direction == nil { acceptedDirection = nil }
                    }
            }
        } else {
            content
        }
    }

    private func grabber(height: CGFloat) -> some View {
        Button(action: dismiss) {
            Capsule()
                .fill(.white.opacity(0.58))
                .frame(width: 42, height: 5)
                .padding(.top, 10)
                .frame(width: 96, height: 36, alignment: .top)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
        .gesture(
            DragGesture(minimumDistance: 10, coordinateSpace: .global)
                .updating($drag) { value, state, transaction in
                    transaction.animation = nil
                    if state.acceptedDirection == nil {
                        state.acceptedDirection = PlayerDismissal.isDownward(value.translation)
                    }
                    state.pull = state.acceptedDirection == true ? travel(value.translation.height) : 0
                }
                .onChanged { value in
                    if acceptedDirection == nil {
                        acceptedDirection = PlayerDismissal.isDownward(value.translation)
                    }
                }
                .onEnded { value in
                    let direction = acceptedDirection
                    acceptedDirection = nil
                    guard PlayerDismissal.shouldDismiss(
                        translation: value.translation,
                        projected: value.predictedEndTranslation,
                        height: height,
                        acceptedDirection: direction
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
