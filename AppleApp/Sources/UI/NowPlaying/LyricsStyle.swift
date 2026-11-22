import Foundation
import SwiftUI

/// Shared by Settings and the player so an edit reaches the current song
/// through UserDefaults without changing the playback or lyric document.
struct LyricStyleStorage: DynamicProperty {
    @AppStorage(LyricPreset.storageKey) var preset = LyricPreset.musicsk
    @AppStorage(LyricCustomStyle.storageKey) private var savedCustom = Data()
    @AppStorage("lyrics_blur") var blurEnabled = true

    var custom: LyricCustomStyle {
        get { LyricCustomStyle.restore(savedCustom) }
        nonmutating set {
            if let data = try? JSONEncoder().encode(newValue.bounded) { savedCustom = data }
        }
    }

    var presentation: LyricPresentation {
        LyricPresentation(preset: preset, custom: preset == .custom ? custom : .init(), blurEnabled: blurEnabled)
    }
}

extension LyricPreset {
    var label: String {
        switch self {
        case .musicsk: "Musicsk"
        case .bitChord: String(localized: "BitChord Original")
        case .custom: String(localized: "Custom")
        }
    }
}

extension LyricBackdrop {
    static let solidColor = Color(red: 0.08, green: 0.09, blue: 0.10)

    var label: String {
        switch self {
        case .artwork: String(localized: "Artwork Blur")
        case .mesh: String(localized: "Artwork Colors")
        case .solid: String(localized: "Solid Dark")
        }
    }
}

extension LyricFontWeight {
    var fontWeight: Font.Weight {
        switch self {
        case .regular: .regular
        case .semibold: .semibold
        case .heavy: .heavy
        }
    }

    var label: String {
        switch self {
        case .regular: String(localized: "Regular")
        case .semibold: String(localized: "Semibold")
        case .heavy: String(localized: "Heavy")
        }
    }
}

extension LyricTextPosition {
    var horizontal: HorizontalAlignment {
        switch self {
        case .automatic, .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    var frame: Alignment {
        Alignment(horizontal: horizontal, vertical: .center)
    }

    var text: TextAlignment {
        switch self {
        case .automatic, .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    var label: String {
        switch self {
        case .automatic: String(localized: "Follow Vocals")
        case .leading: String(localized: "Leading")
        case .center: String(localized: "Centered")
        case .trailing: String(localized: "Trailing")
        }
    }
}

extension LyricPresentation {
    func emphasis(reduceMotion: Bool) -> Animation? {
        guard !reduceMotion, !reduceEffects else { return nil }
        return original ? originalMotion : .easeInOut(duration: emphasisDuration)
    }

    func follow(rejoining: Bool, reduceMotion: Bool) -> Animation? {
        guard !reduceMotion else { return nil }
        return original ? originalMotion : .smooth(duration: followDuration(rejoining: rejoining))
    }

    private var originalMotion: Animation {
        .timingCurve(0.41, 0, 0.12, 0.99, duration: 0.4)
    }
}
