import Foundation

/// Whole-file average including container overhead, not codec nominal bitrate.
enum CachedBitrate {
    static func estimateKbps(bytes: Int64, durationSeconds: Int?, complete: Bool) -> Int? {
        guard complete, bytes > 0, let seconds = durationSeconds, seconds > 0 else { return nil }
        let value = (Double(bytes) * 8 / Double(seconds) / 1000).rounded()
        guard value >= 1, value < Double(Int32.max) else { return nil }
        return Int(value)
    }
}
