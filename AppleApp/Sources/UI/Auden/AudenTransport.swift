#if os(iOS)
import SwiftUI

struct AudenScrubber: View {
    let duration: Double
    let position: Double
    let versionChanging: Bool
    let mixing: Bool
    let transitionWindow: ClosedRange<Double>?
    let status: String?
    let seek: (Double) -> Void
    let didDrag: (Bool) -> Void
    let openPipeline: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var finger: CGFloat?
    private let metrics = AudenPlayerMetrics.self

    private var maximum: Double { duration.isFinite ? max(0, duration) : 0 }
    private var fraction: Double {
        finger.map { Double(min(max($0, 0), 1)) } ?? metrics.fraction(position, maximum: maximum)
    }
    private var seconds: Double { fraction * maximum }
    private var dragging: Bool { finger != nil }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                bar(width: geo.size.width)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .updating($finger) { value, fraction, transaction in
                                transaction.animation = nil
                                guard geo.size.width > 0 else { return }
                                fraction = value.location.x / geo.size.width
                            }
                            .onEnded { value in
                                guard maximum > 0, geo.size.width > 0 else { return }
                                seek(metrics.fraction(value.location.x, maximum: geo.size.width) * maximum)
                            }
                    )
                    .allowsHitTesting(maximum > 0)
            }
            .frame(height: metrics.scrubberHeight)
            .accessibilityElement()
            .accessibilityLabel("Playback position")
            .accessibilityValue(NowPlayingView.timestamp(seconds))
            .accessibilityAdjustableAction { direction in
                guard maximum > 0 else { return }
                switch direction {
                case .increment: seek(min(maximum, seconds + 1))
                case .decrement: seek(max(0, seconds - 5))
                @unknown default: break
                }
            }

            ZStack {
                HStack {
                    Text(NowPlayingView.timestamp(seconds))
                    Spacer()
                    Text("−" + NowPlayingView.timestamp(max(0, maximum - seconds)))
                }
                .monospacedDigit()
                if mixing && !dragging {
                    Text("Mixing")
                } else if let status {
                    Button(action: openPipeline) { Text(status).lineLimit(1) }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 54)
                }
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.55))
            .padding(.top, -metrics.labelLift)
        }
        .onChange(of: dragging) { _, value in didDrag(value) }
        .onDisappear { if dragging { didDrag(false) } }
    }

    private func bar(width: CGFloat) -> some View {
        let showMix = mixing && !dragging
        let showWait = versionChanging && !dragging && !showMix
        return ZStack(alignment: .leading) {
            Capsule().fill(.white.opacity(0.26))
            if !dragging, let transitionWindow, maximum > 0 {
                let start = metrics.fraction(transitionWindow.lowerBound, maximum: maximum)
                let end = metrics.fraction(transitionWindow.upperBound, maximum: maximum)
                let span = max(0, width * (end - start))
                if span > 0 {
                    let feather = metrics.feather(width: span) / span
                    Rectangle()
                        .fill(LinearGradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .white.opacity(0.50), location: feather),
                            .init(color: .white.opacity(0.50), location: 1 - feather),
                            .init(color: .clear, location: 1),
                        ], startPoint: .leading, endPoint: .trailing))
                        .frame(width: span)
                        .offset(x: width * start)
                }
            }
            Capsule()
                .fill(.white.opacity(showMix ? 0.45 : 0.92))
                .frame(width: showMix ? width : width * fraction)
                .opacity(showWait ? 0 : 1)
            if showMix || showWait {
                AudenScrubberSheen(reduceMotion: reduceMotion)
            }
        }
        .frame(height: dragging ? metrics.scrubberActive : metrics.scrubberIdle)
        .clipShape(Capsule())
        .animation(reduceMotion ? nil : .interpolatingSpring(mass: 1, stiffness: 400, damping: 20),
                   value: dragging)
        .animation(reduceMotion ? nil : .timingCurve(0.4, 0, 0.2, 1, duration: 0.45), value: showWait)
    }
}

private struct AudenScrubberSheen: View {
    let reduceMotion: Bool

    var body: some View {
        if reduceMotion {
            Rectangle().fill(.white.opacity(0.24))
        } else {
            TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                Canvas { context, size in
                    let band = size.width * 0.34
                    let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1)
                    let center = -band + (size.width + 2 * band) * phase
                    context.fill(Path(CGRect(origin: .zero, size: size)),
                                 with: .linearGradient(Gradient(colors: [.clear, .white.opacity(0.50), .clear]),
                                    startPoint: CGPoint(x: center - band / 2, y: 0),
                                    endPoint: CGPoint(x: center + band / 2, y: 0)))
                }
            }
            .allowsHitTesting(false)
        }
    }
}

extension NowPlayingView {
    var audenScrubber: some View {
        AudenScrubber(duration: controller.duration, position: controller.position,
                      versionChanging: controller.racingLossless,
                      mixing: controller.smartMixInProgress,
                      transitionWindow: controller.smartTransitionWindow.flatMap { window in
                          window.end > window.start ? window.start...window.end : nil
                      },
                      status: pane == .main && showsPlaybackStatusLine ? songStatusLine : nil,
                      seek: { controller.seek(to: $0) },
                      didDrag: { dragging in
                          lyricsScrubbing = dragging
                          if !dragging { lyricsControlActivity += 1 }
                      },
                      openPipeline: { showPipeline = true })
            .id(controller.current?.id)
    }

    func audenTransport(compact: Bool) -> some View {
        let metrics = AudenPlayerMetrics.transport(compact: compact)
        let locked = party.state.controlsLocked
        return HStack(spacing: 0) {
            Spacer(minLength: 0)
            Button {
                Haptics.play(.skipPrevious)
                controller.previous()
            } label: {
                Image(.bchPrevious).resizable().scaledToFit()
                    .frame(width: metrics.skip, height: metrics.skip)
                    .scaleEffect(y: AudenPlayerMetrics.skipFlatten)
                    .frame(width: AudenPlayerMetrics.skipTouch, height: AudenPlayerMetrics.skipTouch)
                    .contentShape(Rectangle())
            }
            .disabled(!controller.canPlayPrevious || locked)
            .accessibilityLabel("Previous track")
            Spacer(minLength: 0)
            Button {
                Haptics.play(controller.isPlaying ? .pause : .resume)
                controller.togglePlayPause()
            } label: {
                ZStack {
                    if controller.isBuffering {
                        ProgressView().controlSize(.large).tint(.white)
                            .frame(width: metrics.spinner, height: metrics.spinner)
                    } else {
                        Image(controller.isPlaying ? .bchTransportPause : .bchTransportPlay)
                            .resizable().scaledToFit()
                            .frame(width: metrics.glyph, height: metrics.glyph)
                    }
                }
                .frame(width: metrics.touch, height: metrics.touch)
                .contentShape(Rectangle())
            }
            .disabled(controller.current == nil || locked)
            .accessibilityLabel(controller.isBuffering ? "Buffering" : (controller.isPlaying ? "Pause" : "Play"))
            Spacer(minLength: 0)
            Button {
                Haptics.play(.skipNext)
                controller.next()
            } label: {
                Image(.bchNext).resizable().scaledToFit()
                    .frame(width: metrics.skip, height: metrics.skip)
                    .scaleEffect(y: AudenPlayerMetrics.skipFlatten)
                    .frame(width: AudenPlayerMetrics.skipTouch, height: AudenPlayerMetrics.skipTouch)
                    .contentShape(Rectangle())
            }
            .disabled(!controller.canPlayNext || locked)
            .accessibilityLabel("Next track")
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .buttonStyle(AudenTransportPress())
    }
}

private struct AudenTransportPress: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(enabled ? (configuration.isPressed ? 0.72 : 1) : 0.35)
            .animation(reduceMotion ? nil : .timingCurve(0.4, 0, 0.2, 1, duration: 0.18),
                       value: configuration.isPressed)
    }
}
#endif
