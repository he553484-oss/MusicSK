import SwiftUI

/// Appearance settings change only presentation; playback and lyric settings
/// remain owned by their existing controllers.
struct AppearanceLab: View {
    @Environment(PlaybackController.self) private var controller
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage("musicsk_appearance_profile") private var profile = "original"
    @AppStorage("musicsk_player_background") private var background = "original"
    @AppStorage("ambient_animation") private var animated = true
    @AppStorage("musicsk_material_mode") private var material = "automatic"
    @AppStorage("ambient_speed") private var speed = 1.0
    @AppStorage("ambient_blur") private var blur = 64.0
    @AppStorage("ambient_intensity") private var intensity = 1.0
    @AppStorage("ambient_saturation") private var saturation = 1.0
    @AppStorage("ambient_brightness") private var brightness = 0.0
    @AppStorage("ambient_darkening") private var darkening = 0.0

    var body: some View {
        Form {
            Section("Preview") {
                ZStack {
                    MeshBackdrop(seed: controller.current?.id.hashValue ?? 0,
                                 artwork: controller.current?.artworkData)
                    #if os(iOS)
                    if background == "artwork" && !reduceTransparency {
                        FullArtworkBlurBackdrop(entry: controller.current, blurRadius: blur)
                            .saturation(saturation)
                            .brightness(brightness)
                            .overlay { Color.black.opacity(darkening) }
                    }
                    #endif
                    VStack {
                        Spacer()
                        HStack(spacing: 10) {
                            ArtworkView(entry: controller.current, side: 42)
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(controller.current?.title ?? String(localized: "Player Preview"))
                                    .font(.headline).lineLimit(1)
                                Text(controller.current?.artist ?? String(localized: "Play a song to preview its artwork"))
                                    .font(.subheadline).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "play.fill").font(.body.weight(.semibold))
                        }
                        .padding(10)
                        .chromeGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }
                .frame(height: 170)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .listRowInsets(EdgeInsets())
            }
            Section("Visual Profile") {
                Picker("Visual Profile", selection: Binding(get: { profile }, set: applyProfile)) {
                    Text("Apple Experience").tag("apple")
                    Text("MusicSK Original").tag("original")
                    Text("OLED Minimal").tag("oled")
                    Text("Custom").tag("custom")
                }
                Picker("Player Background", selection: customBinding($background)) {
                    Text("Original Ambient").tag("original")
                    Text("Apple Dynamic").tag("dynamic")
                    #if os(iOS)
                    Text("Artwork Blur").tag("artwork")
                    #endif
                    Text("Static Gradient").tag("static")
                    Text("Dominant Color").tag("solid")
                    Text("OLED Black").tag("black")
                    Text("System").tag("system")
                }
            }
            Section {
                Toggle("Animate Background", isOn: customBinding($animated))
                parameter("Movement Speed", value: $speed, range: 0.2...2)
                parameter("Gradient Intensity", value: $intensity, range: 0...1)
                parameter("Blur Intensity", value: $blur, range: 0...100)
                parameter("Saturation", value: $saturation, range: 0...2)
                parameter("Brightness", value: $brightness, range: -0.3...0.2)
                parameter("Darkening", value: $darkening, range: 0...0.7)
            } header: {
                Text("Ambient Background")
            } footer: {
                Text("Movement and gradient intensity apply to Apple Dynamic. Accessibility and Low Power Mode can reduce effects.")
            }
            Section {
                Picker("Materials", selection: customBinding($material)) {
                    Text("Automatic Glass").tag("automatic")
                    Text("Translucent Material").tag("material")
                    Text("Opaque").tag("opaque")
                }
            } header: {
                Text("Materials")
            } footer: {
                Text("Applies to MusicSK's own surfaces. System controls manage their own appearance.")
            }
            Section {
                Button("Restore Default Appearance") { applyProfile("original") }
            }
        }
        .navigationTitle("Appearance Lab")
    }

    private func customBinding<Value>(_ value: Binding<Value>) -> Binding<Value> {
        Binding(get: { value.wrappedValue }, set: { value.wrappedValue = $0; profile = "custom" })
    }

    private func parameter(_ name: LocalizedStringKey, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading) {
            Text(name)
            Slider(value: customBinding(value), in: range)
        }
    }

    private func applyProfile(_ selected: String) {
        profile = selected
        guard let values = AppearanceProfileValues.preset(selected) else { return }
        background = values.background
        animated = values.animated
        material = values.material
        speed = values.speed; blur = values.blur; intensity = values.intensity
        saturation = values.saturation; brightness = values.brightness; darkening = values.darkening
    }
}
