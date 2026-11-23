#if os(iOS)
import SwiftUI

/// PlayerQueue.kt · QueueModePills
struct AudenQueueModes: View {
    @Environment(PlaybackController.self) private var controller

    var body: some View {
        HStack(spacing: 8) {
            mode(.bchShuffle, selected: controller.shuffleEnabled,
                 label: controller.shuffleEnabled ? "Shuffle on" : "Shuffle off") {
                Haptics.play(controller.shuffleEnabled ? .toggleOff : .toggleOn)
                controller.toggleShuffle()
            }
            mode(controller.repeatMode == .one ? nil : .bchRepeat, selected: controller.repeatMode != .off,
                 label: repeatLabel) {
                switch controller.repeatMode {
                case .off: Haptics.play(.toggleOn)
                case .all: Haptics.play(.select)
                case .one: Haptics.play(.toggleOff)
                }
                controller.cycleRepeat()
            }
            mode(.bchInfinity, selected: controller.autoplayEnabled,
                 label: controller.autoplayEnabled ? "AutoPlay on" : "AutoPlay off") {
                Haptics.play(controller.autoplayEnabled ? .toggleOff : .toggleOn)
                controller.toggleAutoplay()
            }
            mode(.bchVinylRecord, selected: controller.automixEnabled,
                 label: controller.automixEnabled ? "AutoMix on" : "AutoMix off") {
                Haptics.play(controller.automixEnabled ? .toggleOff : .toggleOn)
                controller.toggleAutomix()
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var repeatLabel: LocalizedStringKey {
        switch controller.repeatMode {
        case .off: "Repeat off"
        case .all: "Repeat all"
        case .one: "Repeat one"
        }
    }

    private func mode(_ icon: ImageResource?, selected: Bool, label: LocalizedStringKey,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let icon {
                    Image(icon).resizable().scaledToFit().frame(width: 20, height: 20)
                } else {
                    Text("1").scaledFont(size: 15, weight: .bold)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .frame(minHeight: 34)
            .background(.white.opacity(selected ? 0.30 : 0.12), in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
#endif
