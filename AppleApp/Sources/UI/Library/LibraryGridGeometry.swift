import Foundation

/// Bounds transient layout proposals before converting a width to an integer.
enum LibraryGridGeometry {
    static func dimensions(viewportWidth: CGFloat, accessibilitySize: Bool) -> (width: CGFloat, count: Int) {
        let width = viewportWidth.isFinite ? min(860, max(1, viewportWidth - 40)) : 1
        let minimum: CGFloat = accessibilitySize ? 192 : 105
        let count = max(1, min(4, Int((width + 14) / (minimum + 14))))
        return (width, count)
    }
}
