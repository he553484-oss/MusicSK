import SwiftUI
import BitChordShared

struct LyricsStyleSettingsPage: View {
    private var style = LyricStyleStorage()

    var body: some View {
        Form {
            Section {
                Picker("Lyrics Style", selection: style.$preset) {
                    ForEach(LyricPreset.allCases, id: \.self) { preset in
                        Text(preset.label).tag(preset)
                    }
                }
                .pickerStyle(.inline)
            }
            Section("Karaoke Preview") {
                LyricsStylePreview(background: style.presentation.background)
            }
            if style.preset == .custom {
                customControls
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Lyrics Style")
    }

    @ViewBuilder private var customControls: some View {
        let custom = style.custom
        Section("Text") {
            slider("Text Size", value: field(\.typeSize), range: LyricCustomStyle.typeSizeRange)
            Picker("Font Weight", selection: field(\.weight)) {
                ForEach(LyricFontWeight.allCases, id: \.self) { weight in
                    Text(weight.label).tag(weight)
                }
            }
            Picker("Text Alignment", selection: field(\.alignment)) {
                ForEach(LyricTextPosition.allCases, id: \.self) { alignment in
                    Text(alignment.label).tag(alignment)
                }
            }
            Toggle("Highlight Timed Words", isOn: field(\.wordHighlight))
        }
        Section("Lyrics Effects") {
            Picker("Lyrics Background", selection: field(\.background)) {
                ForEach(LyricBackdrop.allCases, id: \.self) { background in
                    Text(background.label).tag(background)
                }
            }
            Toggle("Reduce Lyrics Effects", isOn: field(\.reduceEffects))
            slider("Blur Intensity", value: field(\.blur), range: LyricCustomStyle.blurRange)
                .disabled(!style.blurEnabled || custom.reduceEffects)
            slider("Glow Intensity", value: field(\.glow), range: LyricCustomStyle.glowRange)
                .disabled(custom.reduceEffects || !custom.wordHighlight)
            slider("Inactive Verse Opacity", value: field(\.inactiveOpacity), range: LyricCustomStyle.inactiveOpacityRange)
            slider("Transition Softness", value: field(\.softness), range: LyricCustomStyle.softnessRange)
                .disabled(custom.reduceEffects)
        }
        Section {
            Button("Reset Custom Style") { style.custom = LyricCustomStyle() }
                .disabled(custom == LyricCustomStyle())
        }
    }

    private func field<Value>(_ property: WritableKeyPath<LyricCustomStyle, Value>) -> Binding<Value> {
        Binding(get: { style.custom[keyPath: property] }, set: { newValue in
            var custom = style.custom
            custom[keyPath: property] = newValue
            style.custom = custom
        })
    }

    private func slider(_ title: LocalizedStringKey, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                Spacer()
                Text(value.wrappedValue, format: .percent.precision(.fractionLength(0)))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range, step: 0.01)
                .accessibilityLabel(Text(title))
        }
    }
}

/// An isolated, silent example that exercises the same pane and renderer on
/// each edit. The clock for an actual song remains the transport's clock.
private struct LyricsStylePreview: View {
    let background: LyricBackdrop

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var start = Date()

    var body: some View {
        let playing = scenePhase == .active && !reduceMotion
        LyricsPane(
            lines: Self.lines,
            loading: false,
            clock: LyricsClock(playing: playing, pausedPosition: playing ? nil : 1) { date in
                max(0, date.timeIntervalSince(start)).truncatingRemainder(dividingBy: 9)
            },
            fontSize: 24,
            hasTrack: true
        )
        .frame(height: 188)
        .background {
            switch background {
            case .artwork:
                LinearGradient(colors: [Color(red: 0.15, green: 0.23, blue: 0.33), LyricBackdrop.solidColor],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            case .mesh:
                RadialGradient(colors: [Color(red: 0.27, green: 0.17, blue: 0.34), LyricBackdrop.solidColor],
                               center: .topLeading, startRadius: 10, endRadius: 230)
            case .solid:
                LyricBackdrop.solidColor
            }
        }
        .clipShape(.rect(cornerRadius: 12))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @MainActor private static let lines: [LyricLineDto] = [
        timedLine(String(localized: "A line begins"), at: 0, alignment: .start),
        timedLine(String(localized: "The voice answers"), at: 3_000, alignment: .end),
        timedLine(String(localized: "We sing together"), at: 6_000, alignment: .start)
    ]

    private static func timedLine(_ text: String, at time: Int64, alignment: LyricAlignment) -> LyricLineDto {
        var onset = time
        let words = text.split(separator: " ").enumerated().map { index, token in
            let end = onset + (index == 0 ? 1_400 : 600)
            let word = LyricWordDto(startMs: onset, endMs: end, text: String(token))
            onset = end
            return word
        }
        return LyricLineDto(timeMs: time, text: text, words: words, sungUntilMs: nil,
                            background: nil, alignment: alignment)
    }
}
