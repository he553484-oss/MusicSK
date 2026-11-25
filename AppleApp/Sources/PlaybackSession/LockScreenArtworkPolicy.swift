import Foundation

/// Presentation policy only; it never changes playback, audio gain or artwork files.
enum LockScreenArtworkPolicy {
    static let preferencesChanged = Notification.Name("MusicSKLockScreenArtworkPreferencesChanged")

    static func allowsAnimation(enabled: Bool, wifiOnly: Bool, usesWiFi: Bool,
                                canvasAllowed: Bool, constrained: Bool, reduceMotion: Bool,
                                lowPower: Bool, autoPlay: Bool, thermalSerious: Bool) -> Bool {
        enabled && (!wifiOnly || usesWiFi) && canvasAllowed && !constrained && !reduceMotion
            && !lowPower && autoPlay && !thermalSerious
    }
}
