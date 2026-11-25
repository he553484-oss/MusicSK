#if os(iOS)
import SwiftUI

/// These preferences govern only animated lock-screen artwork. iOS decides
/// whether to expand or animate a supported artwork in its own surfaces.
struct LockScreenArtworkSettings: View {
    @AppStorage("lockscreen_animated_artwork") private var animated = true
    @AppStorage("lockscreen_artwork_wifi_only") private var wifiOnly = false

    var body: some View {
        Form {
            Section {
                if #available(iOS 26, *) {
                    Toggle("Allow Animated Artwork", isOn: $animated)
                    Toggle("Animated Artwork on Wi-Fi Only", isOn: $wifiOnly)
                        .disabled(!animated)
                } else {
                    Text("Animated lock screen artwork requires iOS 26 or later.")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("The system controls artwork expansion and may show a still image for accessibility, power, data or thermal reasons.")
            }
        }
        .navigationTitle("Lock Screen")
        .onChange(of: animated) { _, _ in notify() }
        .onChange(of: wifiOnly) { _, _ in notify() }
    }

    private func notify() {
        NotificationCenter.default.post(name: LockScreenArtworkPolicy.preferencesChanged, object: nil)
    }
}
#endif
