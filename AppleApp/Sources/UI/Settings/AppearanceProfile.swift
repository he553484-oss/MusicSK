import Foundation

/// Profiles own presentation values only. They never change playback, volume,
/// EQ or lyrics preferences.
struct AppearanceProfileValues: Equatable {
    var background: String
    var animated: Bool
    var material: String = "automatic"
    var motion: String = "automatic"
    var haptics: Bool = true
    var transitions: Bool = true
    var speed: Double = 1
    var blur: Double = 64
    var intensity: Double = 1
    var saturation: Double = 1
    var brightness: Double = 0
    var darkening: Double = 0

    static func preset(_ name: String) -> AppearanceProfileValues? {
        switch name {
        case "apple": return .init(background: "dynamic", animated: true)
        case "original": return .init(background: "original", animated: true)
        case "oled": return .init(background: "black", animated: false, material: "opaque", motion: "reduced", haptics: false, transitions: false)
        default: return nil
        }
    }
}

enum AppearanceInstallDefaults {
    /// Use the app's existing onboarding decision and never replace an
    /// explicitly stored appearance preference during an upgrade.
    static func shouldApplyAppleProfile(onboarded: Bool, signedIn: Bool,
                                        hasQueue: Bool, hasAppearancePreference: Bool) -> Bool {
        !onboarded && !signedIn && !hasQueue && !hasAppearancePreference
    }

    static let preferenceKeys = [
        "musicsk_appearance_profile", "musicsk_player_background", "legacy_mesh_gradient",
        "reduce_animation", "reduce_dynamic_blur", "full_bleed_artwork", "animated_canvas", "theme_mode",
    ]
}
