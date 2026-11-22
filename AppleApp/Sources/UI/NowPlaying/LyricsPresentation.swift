import Foundation

/// Opacity describes lyric focus. Blur is independently controlled by the
/// listener's setting, with a lighter radius while reading by hand.
struct LyricRowLook: Equatable {
    let alpha: Double
    let blur: CGFloat

    private static let compactAlpha = [0.69, 0.58, 0.48, 0.39, 0.33]
    private static let regularAlpha = [0.85, 0.75, 0.64, 0.55, 0.48]
    private static let focusBlur: [CGFloat] = [1.3, 2.1, 2.9, 3.6, 4.2]

    static func forLine(
        timed: Bool, synced: Bool, active: Bool, distance: Int,
        compact: Bool, browsing: Bool, blurEnabled: Bool
    ) -> Self {
        guard synced else { return Self(alpha: 0.95, blur: 0) }
        guard timed else { return Self(alpha: 0.9, blur: 0) }
        guard !active else { return Self(alpha: 1, blur: 0) }
        let index = min(max(distance, 1) - 1, focusBlur.count - 1)
        let alpha = (compact ? compactAlpha : regularAlpha)[index]
        let blur = blurEnabled ? focusBlur[index] : 0
        return Self(alpha: browsing ? max(0.8, alpha) : alpha, blur: browsing ? blur * 0.30 : blur)
    }
}

enum LyricWordProgress {
    static func at(_ position: Int64, start: Int64, end: Int64) -> Double {
        guard end > start, position > start else { return 0 }
        guard position < end else { return 1 }
        // The ordered timestamps can straddle the signed Int64 boundaries.
        let elapsed = UInt64(bitPattern: position) &- UInt64(bitPattern: start)
        let duration = UInt64(bitPattern: end) &- UInt64(bitPattern: start)
        return Double(elapsed) / Double(duration)
    }

    static func glowEnvelope(_ progress: Double) -> Double {
        guard progress > 0, progress < 1 else { return 0 }
        return sin(.pi * progress)
    }
}

/// Separates touching the scroll view from actually reading away from the
/// playhead. Only a real drag or momentum starts the return delay.
struct LyricFollowState: Equatable {
    enum Scroll {
        case resting, touching, moving
    }

    private(set) var scroll: Scroll = .resting
    private(set) var browsing = false
    private(set) var returnRevision: UInt = 0
    private(set) var resumeTicket: UInt?
    private var nextTicket: UInt = 0

    var follows: Bool { scroll == .resting && !browsing }

    mutating func update(_ scroll: Scroll) {
        guard self.scroll != scroll else { return }
        self.scroll = scroll
        resumeTicket = nil
        if scroll == .moving { browsing = true }
        if scroll == .resting, browsing {
            nextTicket &+= 1
            resumeTicket = nextTicket
        }
    }

    mutating func returnToPlayhead(ticket: UInt) {
        guard resumeTicket == ticket, scroll == .resting else { return }
        browsing = false
        resumeTicket = nil
        returnRevision &+= 1
    }

    mutating func replaceDocument() {
        browsing = false
        resumeTicket = nil
    }
}
