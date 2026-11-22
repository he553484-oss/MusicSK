import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Geometry shared by the scrollable hero and its loading surface.
enum DetailHeaderLayout {
    enum Hero: Equatable {
        case album, artist
    }

    static let maxContentWidth: CGFloat = 860
    static let contentInset: CGFloat = 20

    static func albumWidth(in width: CGFloat) -> CGFloat {
        width.isFinite ? max(1, width) : 1
    }

    static func albumArtworkHeight(width: CGFloat, viewportHeight: CGFloat) -> CGFloat {
        min(albumWidth(in: width), max(136, viewportHeight * 0.58), 540)
    }

    static func artistArtworkHeight(width: CGFloat, viewportHeight: CGFloat, immersive: Bool = true) -> CGFloat {
        if immersive {
            return min(albumWidth(in: width) * 1.04, max(168, viewportHeight * 0.62), 560)
        }
        return min(albumWidth(in: width) * 0.9, max(168, viewportHeight * 0.53), 480)
    }

    /// A landscape window or a tall provider image can otherwise lose most of
    /// the subject to a fill crop. Keep that image whole within the same field.
    static func artworkSize(in field: CGSize, sourceAspect: CGFloat?, hero: Hero) -> CGSize {
        guard field.width > 0, field.height > 0, field.width.isFinite, field.height.isFinite else {
            return CGSize(width: 1, height: 1)
        }
        let defaultAspect: CGFloat = hero == .album ? 1 : 4.0 / 3.0
        let aspect = sourceAspect.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? defaultAspect
        let fieldAspect = field.width / field.height
        let crop = 1 - min(aspect, fieldAspect) / max(aspect, fieldAspect)
        if crop <= (hero == .album ? 0.18 : 0.38) {
            return field
        }
        let fitWidth = min(field.width, field.height * aspect)
        return CGSize(width: fitWidth, height: fitWidth / aspect)
    }

    /// The final tenth of the image is already the opaque content surface. A
    /// small overlap joins identity and artwork without placing text on pixels.
    static func identityOverlap(artHeight: CGFloat, usesExpandedText: Bool) -> CGFloat {
        usesExpandedText ? 0 : min(28, max(0, artHeight * 0.08))
    }

    struct ScrollChrome: Equatable, Sendable {
        let showsToolbarBackground: Bool
        let showsInlineTitle: Bool

        init(offset: CGFloat, headerHeight: CGFloat) {
            showsToolbarBackground = offset > 48
            showsInlineTitle = headerHeight > 0 && offset > headerHeight - 50
        }
    }
}
