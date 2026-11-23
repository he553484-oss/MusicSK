import Foundation

enum MusicAppearance: String, CaseIterable, Identifiable {
    case original
    case auden

    static let storageKey = "musicsk.appearance.edition"

    var id: String { rawValue }
}

struct AudenDockPolicy {
    private var anchor: Double = 0

    mutating func update(offset: Double, folded: Bool) -> Bool {
        guard offset.isFinite else { return folded }
        if offset <= 8 { anchor = 0; return false }
        if folded {
            anchor = max(anchor, offset)
            if anchor - offset >= 14 { anchor = offset; return false }
        } else {
            anchor = min(anchor, offset)
            if offset >= 28, offset - anchor >= 20 { anchor = offset; return true }
        }
        return folded
    }
}

extension Sequence where Element: Identifiable {
    func audenUnique() -> [Element] {
        var seen: Set<Element.ID> = []
        return filter { seen.insert($0.id).inserted }
    }
}

#if canImport(SwiftUI)
import SwiftUI

extension EnvironmentValues {
    @Entry var musicAppearance: MusicAppearance = .original
    @Entry var audenTabActive = true
}

#if os(iOS)
import Observation

extension EnvironmentValues {
    @Entry var audenDockState: AudenDockState? = nil
}

@MainActor
@Observable
final class AudenDockState: Equatable {
    private(set) var folded = false
    @ObservationIgnored private var policy = AudenDockPolicy()

    nonisolated static func == (lhs: AudenDockState, rhs: AudenDockState) -> Bool { lhs === rhs }

    func observe(offset: Double, reduceMotion: Bool) {
        setFolded(policy.update(offset: offset, folded: folded), reduceMotion: reduceMotion)
    }

    func expand(reduceMotion: Bool) {
        policy = AudenDockPolicy()
        setFolded(false, reduceMotion: reduceMotion)
    }

    private func setFolded(_ value: Bool, reduceMotion: Bool) {
        guard value != folded else { return }
        withAnimation(reduceMotion ? nil : AudenDesign.dockMotion(stiffness: value ? 900 : 260,
                                                                      delay: value ? 0 : 0.03)) {
            folded = value
        }
    }
}

enum AudenDesign {
    static let gutter: CGFloat = 20
    static let spacing: CGFloat = 14
    static let miniHeight = AudenPlayerMetrics.inlineNavSide

    // Compose spring(stiffness:, dampingRatio: .74), mass one.
    static func dockMotion(stiffness: Double, delay: Double = 0) -> Animation {
        .interpolatingSpring(mass: 1, stiffness: stiffness, damping: 2 * 0.74 * sqrt(stiffness))
            .delay(delay)
    }

    static func canvas(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .black : .white
    }

    static func panel(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.11, green: 0.11, blue: 0.12)
            : Color(red: 0.95, green: 0.95, blue: 0.97)
    }
}

struct AudenScrollTracking: ViewModifier {
    @Environment(\.audenDockState) private var dockState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func body(content: Content) -> some View {
        if let dockState {
            content.onScrollGeometryChange(for: Double.self) { geometry in
                Double(geometry.contentOffset.y + geometry.contentInsets.top)
            } action: { _, new in dockState.observe(offset: new, reduceMotion: reduceMotion) }
        } else {
            content
        }
    }
}

struct AudenPanel: ViewModifier {
    var nativeGlass = true
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var opaque

    @ViewBuilder
    func body(content: Content) -> some View {
        if opaque {
            content.background(AudenDesign.panel(scheme), in: Capsule())
        } else if nativeGlass, #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content
                .background(.thickMaterial, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(.primary.opacity(0.13), lineWidth: 0.5)
                        .allowsHitTesting(false)
                }
        }
    }
}

struct AudenGlassGroup: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var opaque

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !opaque {
            GlassEffectContainer(spacing: AudenPlayerMetrics.inlineGap) { content }
        } else {
            content
        }
    }
}
#endif
#endif

#if os(iOS)
struct AudenEditionPicker: View {
    @AppStorage(MusicAppearance.storageKey) private var edition: MusicAppearance = .original

    var body: some View {
        Picker("Interface Edition", selection: $edition) {
            Text("MusicSK Original").tag(MusicAppearance.original)
            Text("Auden Edition").tag(MusicAppearance.auden)
        }
        .accessibilityIdentifier("settings.appearance.edition")
    }
}
#endif

enum AudenPlayerGeometry {
    static func sleeveFrame(in stage: CGSize) -> CGRect {
        guard stage.width.isFinite, stage.height.isFinite else { return .zero }
        let width = max(0, stage.width)
        let top = min(8, max(0, stage.height))
        let side = max(0, min(560, width - 60, stage.height - top - 4))
        return CGRect(x: (width - side) / 2, y: top, width: side, height: side)
    }
}
