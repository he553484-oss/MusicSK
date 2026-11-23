import Foundation

// PlayerControls.kt, ThinSlider.kt, NowPlayingScreen.kt and GlassNavBar.kt.
enum AudenPlayerMetrics {
    static let gutter: CGFloat = 30
    static let maxDeckWidth: CGFloat = 560
    static let headerArt: CGFloat = 54
    static let headerHeight: CGFloat = 60
    static let scrubberIdle: CGFloat = 7
    static let scrubberActive: CGFloat = 12
    static let scrubberHeight: CGFloat = 34
    static let labelLift: CGFloat = 9
    static let volumeRowHeight: CGFloat = 32
    static let skipTouch: CGFloat = 53
    static let skipFlatten: CGFloat = 0.85
    static let centerTouch: CGFloat = 44
    static let paneIcon: CGFloat = 26
    static let paneTile: CGFloat = 35
    static let paneTileRadius: CGFloat = 7
    static let inlineNavSide: CGFloat = 48
    static let expandedNavHeight: CGFloat = 62
    static let miniArt: CGFloat = 30.4
    static let miniArtRadius: CGFloat = 5.7
    static let inlineGap: CGFloat = 14
    static let miniGap: CGFloat = 8
    static let queueTravel: CGFloat = 26

    static func queueProgress(pull: CGFloat, travel: CGFloat) -> CGFloat {
        guard pull.isFinite, travel.isFinite, travel >= 1 else { return 0 }
        return min(1, max(0, pull / travel))
    }

    static func opensQueue(progress: CGFloat, upwardVelocity: CGFloat) -> Bool {
        if upwardVelocity >= 450 { return true }
        if upwardVelocity <= -450 { return false }
        return progress >= 0.3
    }

    static func transport(compact: Bool) -> (glyph: CGFloat, touch: CGFloat, skip: CGFloat, spinner: CGFloat) {
        compact ? (58, 76, 44, 30) : (74, 84, 53, 38)
    }

    static func actionInset(width: CGFloat) -> CGFloat {
        // Two edge targets and the space reserved for a two-segment pill.
        max(0, (width - centerTouch * 2 - 128) / 4)
    }

    static func fraction(_ value: Double, maximum: Double) -> Double {
        guard value.isFinite, maximum.isFinite, maximum > 0 else { return 0 }
        return min(max(value / maximum, 0), 1)
    }

    static func feather(width: CGFloat) -> CGFloat {
        max(0, min(width / 2, max(6, min(40, width * 0.4))))
    }
}
