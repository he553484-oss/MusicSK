import Foundation

/// Geometry shared by a loaded detail header and its loading surface.
enum DetailHeaderLayout {
    static let maxContentWidth: CGFloat = 860
    static let albumInset: CGFloat = 16

    static func albumWidth(in width: CGFloat) -> CGFloat {
        min(max(1, width - albumInset * 2), maxContentWidth)
    }

    static func albumArtworkHeight(width: CGFloat, viewportHeight: CGFloat) -> CGFloat {
        min(albumWidth(in: width) * 0.82, max(168, viewportHeight * 0.52), 360)
    }

    static func artistArtworkHeight(width: CGFloat, viewportHeight: CGFloat) -> CGFloat {
        min(max(1, width) * 0.9, max(168, viewportHeight * 0.53), 480)
    }
}
