import Foundation

enum MusicAppearance: String, CaseIterable, Identifiable {
    case original
    case auden

    static let storageKey = "musicsk.appearance.edition"

    var id: String { rawValue }
}

enum AudenDockPolicy {
    static func nextState(from previous: Double, to offset: Double, folded: Bool) -> Bool {
        if offset <= 8 { return false }
        if offset >= 28, offset - previous >= 10 { return true }
        if previous - offset >= 10 { return false }
        return folded
    }
}

#if canImport(SwiftUI)
import SwiftUI

extension EnvironmentValues {
    @Entry var musicAppearance: MusicAppearance = .original
    @Entry var audenScrollChanged: ((Double, Double) -> Void)? = nil
}

#if os(iOS)
enum AudenDesign {
    static let gutter: CGFloat = 20
    static let spacing: CGFloat = 14
    static let dockHeight: CGFloat = 52
    static let miniHeight: CGFloat = 48
    static let coverRadius: CGFloat = 8

    static func canvas(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .black : .white
    }

    static func panel(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.11, green: 0.11, blue: 0.12)
            : Color(red: 0.95, green: 0.95, blue: 0.97)
    }
}

struct AudenScrollTracking: ViewModifier {
    @Environment(\.audenScrollChanged) private var changed

    @ViewBuilder
    func body(content: Content) -> some View {
        if let changed {
            content.onScrollGeometryChange(for: Double.self) { geometry in
                Double(geometry.contentOffset.y + geometry.contentInsets.top)
            } action: { old, new in changed(old, new) }
        } else {
            content
        }
    }
}

struct AudenPanel: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var opaque

    func body(content: Content) -> some View {
        content
            .background {
                if opaque { RoundedRectangle(cornerRadius: 24).fill(AudenDesign.panel(scheme)) }
                else { RoundedRectangle(cornerRadius: 24).fill(.thickMaterial) }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 24).strokeBorder(.primary.opacity(0.13), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
    }
}
#endif
#endif
