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
