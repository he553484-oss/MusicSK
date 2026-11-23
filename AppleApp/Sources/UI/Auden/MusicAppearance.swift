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
        withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.85)) { folded = value }
    }
}

enum AudenDesign {
    static let gutter: CGFloat = 20
    static let spacing: CGFloat = 14
    static let dockHeight: CGFloat = 52
    static let miniHeight: CGFloat = 48

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
