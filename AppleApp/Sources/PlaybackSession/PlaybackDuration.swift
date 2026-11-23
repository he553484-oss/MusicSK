import Foundation

/// A missing, non-finite or unrepresentable duration remains unknown.
/// The shared provider bridge accepts signed 32-bit seconds.
enum PlaybackDuration {
    static func roundedSeconds(_ value: Double) -> Int? {
        guard value.isFinite, value > 0, value.rounded() <= Double(Int32.max) else { return nil }
        let seconds = Int(value.rounded())
        return seconds > 0 ? seconds : nil
    }

    static func wholeSeconds(_ value: Double) -> Int32? {
        guard value.isFinite, value > 0, value < Double(Int32.max) + 1 else { return nil }
        let seconds = Int32(value)
        return seconds > 0 ? seconds : nil
    }
}
