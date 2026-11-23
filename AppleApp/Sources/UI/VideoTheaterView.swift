import SwiftUI

/// Full-screen picture presentation. Lyrics remain in the player's existing
/// pane; opening the theater never changes which pane the listener chose.
struct VideoTheaterView: View {
    let controller: PlaybackController

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var controlsVisible = true
    @State private var controlActivity = 0
    @State private var draftPosition: Double?

    private var duration: Double {
        let value = controller.duration
        return value.isFinite && value > 0 ? value : 1
    }

    private var position: Double {
        min(max(controller.livePosition(at: Date()), 0), duration)
    }

    private var seekPosition: Binding<Double> {
        Binding(
            get: { draftPosition ?? position },
            set: { value in
                if draftPosition != nil {
                    draftPosition = value
                } else {
                    controller.seek(to: value)
                    revealControls()
                }
            }
        )
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            GeometryReader { geometry in
                VideoSurface(cornerRadius: 0, announcesLoading: true, showsPictureControls: false) {
                    ArtworkView(entry: controller.current,
                                side: min(geometry.size.width, geometry.size.height),
                                reusesPlayerThumbnail: true)
                }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .contentShape(Rectangle())
                    .onTapGesture { revealControls() }
            }
            .ignoresSafeArea(.container)

            controls
        }
        .task(id: controlActivity) {
            guard controlsVisible, draftPosition == nil else { return }
            do {
                try await Task.sleep(for: .seconds(3))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            controlsVisible = false
        }
        .onChange(of: controller.current?.id) { _, _ in
            draftPosition = nil
            revealControls()
        }
    }

    private var controls: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(controller.current?.title ?? "Music Video")
                        .font(.headline)
                        .lineLimit(1)
                    Text(controller.current?.artist ?? "")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline.weight(.semibold))
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel("Close Video Theater")
            }

            Spacer()

            VStack(spacing: 12) {
                HStack(spacing: 36) {
                    Button {
                        controller.seek(to: max(0, position - 10))
                        revealControls()
                    } label: {
                        Image(systemName: "gobackward.10")
                    }
                    .accessibilityLabel("Back 10 seconds")

                    Button {
                        controller.togglePlayPause()
                        revealControls()
                    } label: {
                        Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                            .frame(width: 48, height: 48)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel(controller.isPlaying ? "Pause" : "Play")

                    Button {
                        controller.seek(to: min(duration, position + 10))
                        revealControls()
                    } label: {
                        Image(systemName: "goforward.10")
                    }
                    .accessibilityLabel("Forward 10 seconds")
                }

                HStack(spacing: 10) {
                    Text(timeLabel(draftPosition ?? position))
                        .monospacedDigit()
                    Slider(value: seekPosition, in: 0...duration, onEditingChanged: scrubChanged)
                    Text(timeLabel(duration))
                        .monospacedDigit()
                }
                .font(.caption)
            }
        }
        .foregroundStyle(.white)
        .padding(24)
        .background {
            LinearGradient(
                colors: [.black.opacity(0.56), .clear, .black.opacity(0.76)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
        .opacity(controlsVisible ? 1 : 0)
        .allowsHitTesting(controlsVisible)
        .accessibilityHidden(!controlsVisible)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: controlsVisible)
    }

    private func scrubChanged(_ editing: Bool) {
        if editing {
            draftPosition = position
        } else if let target = draftPosition {
            draftPosition = nil
            controller.seek(to: min(target, duration))
        }
        revealControls()
    }

    private func revealControls() {
        controlsVisible = true
        controlActivity += 1
    }

    private func timeLabel(_ seconds: Double) -> String {
        let value = max(0, Int(seconds.rounded(.down)))
        return "\(value / 60):\(String(format: "%02d", value % 60))"
    }
}
