import Foundation

enum LyricPreset: String, CaseIterable {
    case musicsk, bitChord, custom

    static let storageKey = "musicsk_lyric_preset"
}

enum LyricFontWeight: String, Codable, CaseIterable {
    case regular, semibold, heavy
}

enum LyricTextPosition: String, Codable, CaseIterable {
    case automatic, leading, center, trailing

    func resolved(secondVoice: Bool) -> Self {
        self == .automatic ? (secondVoice ? .trailing : .leading) : self
    }
}

enum LyricBackdrop: String, Codable, CaseIterable {
    case artwork, mesh, solid
}

struct LyricCustomStyle: Codable, Equatable {
    static let storageKey = "musicsk_lyric_style_custom"
    static let typeSizeRange = 0.8...1.25
    static let blurRange = 0.0...1.25
    static let glowRange = 0.0...1.5
    static let inactiveOpacityRange = 0.38...0.74
    static let softnessRange = 0.0...1.0

    var typeSize = 1.0
    var weight: LyricFontWeight = .heavy
    var alignment: LyricTextPosition = .automatic
    var blur = 1.0
    var glow = 1.0
    var inactiveOpacity = 0.52
    var softness = 0.5
    var background: LyricBackdrop = .artwork
    var wordHighlight = true
    var reduceEffects = false

    static func restore(_ data: Data) -> Self {
        (try? JSONDecoder().decode(Self.self, from: data))?.bounded ?? Self()
    }

    var bounded: Self {
        let defaults = Self()
        var result = self
        result.typeSize = Self.clamp(typeSize, to: Self.typeSizeRange, fallback: defaults.typeSize)
        result.blur = Self.clamp(blur, to: Self.blurRange, fallback: defaults.blur)
        result.glow = Self.clamp(glow, to: Self.glowRange, fallback: defaults.glow)
        result.inactiveOpacity = Self.clamp(inactiveOpacity, to: Self.inactiveOpacityRange, fallback: defaults.inactiveOpacity)
        result.softness = Self.clamp(softness, to: Self.softnessRange, fallback: defaults.softness)
        return result
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>, fallback: Double) -> Double {
        value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : fallback
    }
}

extension LyricCustomStyle {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        typeSize = (try? values.decode(Double.self, forKey: .typeSize)) ?? typeSize
        weight = (try? values.decode(LyricFontWeight.self, forKey: .weight)) ?? weight
        alignment = (try? values.decode(LyricTextPosition.self, forKey: .alignment)) ?? alignment
        blur = (try? values.decode(Double.self, forKey: .blur)) ?? blur
        glow = (try? values.decode(Double.self, forKey: .glow)) ?? glow
        inactiveOpacity = (try? values.decode(Double.self, forKey: .inactiveOpacity)) ?? inactiveOpacity
        softness = (try? values.decode(Double.self, forKey: .softness)) ?? softness
        background = (try? values.decode(LyricBackdrop.self, forKey: .background)) ?? background
        wordHighlight = (try? values.decode(Bool.self, forKey: .wordHighlight)) ?? wordHighlight
        reduceEffects = (try? values.decode(Bool.self, forKey: .reduceEffects)) ?? reduceEffects
    }
}

/// Presentation only. Presets and live edits never change a document's identity
/// or its line/word timing index.
struct LyricPresentation: Equatable {
    let preset: LyricPreset
    private let custom: LyricCustomStyle
    let blurEnabled: Bool
    let auden: Bool

    init(preset: LyricPreset = .musicsk, custom: LyricCustomStyle = .init(), blurEnabled: Bool = true,
         auden: Bool = false) {
        self.preset = preset
        self.custom = preset == .custom ? custom.bounded : LyricCustomStyle()
        self.blurEnabled = blurEnabled
        self.auden = auden && preset == .musicsk
    }

    var original: Bool { preset == .bitChord }
    var typeSize: CGFloat { CGFloat(custom.typeSize) }
    var weight: LyricFontWeight { custom.weight }
    var alignment: LyricTextPosition { custom.alignment }
    var background: LyricBackdrop { custom.background }
    var wordHighlight: Bool { custom.wordHighlight }
    var reduceEffects: Bool { custom.reduceEffects }
    var inactiveScale: CGFloat { original || auden ? 0.98 : 1 }
    var phoneAnchor: CGFloat { auden ? 0 : (original ? 0.32 : 0.27) }
    var blurMultiplier: CGFloat { blurEnabled && !reduceEffects ? CGFloat(custom.blur) : 0 }
    var glowAlpha: Double { reduceEffects ? 0 : (original || auden ? 0.62 : 0.30 * custom.glow) }
    var glowRadius: CGFloat { original || auden ? 6 : CGFloat(3.5 * min(1.3, custom.glow)) }
    var preservesDuetLanes: Bool { alignment == .automatic }

    var emphasisDuration: Double {
        original ? 0.4 : 0.22 + 0.20 * custom.softness
    }

    func followDuration(rejoining: Bool) -> Double {
        if original { return 0.4 }
        let duration = 0.24 + 0.24 * custom.softness
        return (reduceEffects ? min(duration, 0.30) : duration) + (rejoining ? 0.08 : 0)
    }

    func inactiveAlpha(base: Double, nearby: Double, upcoming: Bool) -> Double {
        if original { return base }
        let upcomingScale = upcoming ? 0.78 : 1
        if preset == .custom {
            return max(0.26, custom.inactiveOpacity * base / nearby * upcomingScale)
        }
        return base * upcomingScale
    }
}

/// Opacity describes lyric focus. Blur is independently controlled by the
/// listener's setting, with a lighter radius while reading by hand.
struct LyricRowLook: Equatable {
    let alpha: Double
    let blur: CGFloat
    var scale: CGFloat = 1

    private static let compactAlpha = [0.52, 0.45, 0.38, 0.32, 0.27]
    private static let regularAlpha = [0.63, 0.54, 0.46, 0.39, 0.33]
    private static let focusBlur: [CGFloat] = [1.3, 2.1, 2.9, 3.6, 4.2]
    // The original Apple port's falloffs, after the active row at index zero.
    private static let originalCompactAlpha = [0.74, 0.60, 0.48, 0.40, 0.34]
    private static let originalRegularAlpha = [0.80, 0.70, 0.58, 0.46]
    private static let originalBlur: [CGFloat] = [1.0, 1.0, 1.7, 2.4]

    static func forLine(
        timed: Bool, synced: Bool, active: Bool, distance: Int,
        compact: Bool, browsing: Bool, presentation: LyricPresentation = .init(), upcoming: Bool = false
    ) -> Self {
        guard synced else { return Self(alpha: 0.95, blur: 0) }
        guard timed else { return Self(alpha: 0.9, blur: 0) }
        if presentation.auden {
            let alpha = AudenLyricMetrics.alpha(distance: distance, compact: compact)
            let blur = browsing ? 0 : AudenLyricMetrics.blur(distance: distance) * presentation.blurMultiplier
            return Self(alpha: browsing ? 0.8 : alpha, blur: active ? 0 : blur,
                        scale: active ? 1 : presentation.inactiveScale)
        }
        guard !active else { return Self(alpha: 1, blur: 0) }
        let index = max(distance, 1) - 1
        let alphaSteps = presentation.original
            ? (compact ? originalCompactAlpha : originalRegularAlpha)
            : (compact ? compactAlpha : regularAlpha)
        let blurSteps = presentation.original ? originalBlur : focusBlur
        let alpha = presentation.inactiveAlpha(base: alphaSteps[min(index, alphaSteps.count - 1)],
                                                nearby: alphaSteps[0], upcoming: upcoming)
        let blur = blurSteps[min(index, blurSteps.count - 1)] * presentation.blurMultiplier
        return Self(alpha: browsing ? max(0.8, alpha) : alpha,
                    blur: browsing ? blur * (presentation.original ? 0 : 0.30) : blur,
                    scale: presentation.inactiveScale)
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

/// The transcript allocates text, effects and the opposite voice's lane from
/// the scroll viewport's proposed width.
struct LyricRowGeometry: Equatable {
    let documentInset: CGFloat
    let rowWidth: CGFloat
    let effectInset: CGFloat
    let duetInset: CGFloat
    let textWidth: CGFloat

    init(viewportWidth: CGFloat, compact: Bool, duet: Bool, presentation: LyricPresentation = .init()) {
        let viewport = max(0, viewportWidth)
        documentInset = min(presentation.auden ? 20 : (compact && !presentation.original ? 12 : 2), viewport * 0.10)
        rowWidth = viewport - 2 * documentInset
        effectInset = min(presentation.original || presentation.auden ? 10 : 14, rowWidth * 0.10)
        let interior = rowWidth - 2 * effectInset
        duetInset = duet && presentation.preservesDuetLanes ? min(44, interior * 0.18) : 0
        textWidth = interior - duetInset
    }
}

/// Occludes the actual header while preserving a legible centre on compact
/// displays and with Dynamic Type.
struct LyricViewportGeometry {
    let topOcclusion: CGFloat
    let bottomOcclusion: CGFloat
    let edgeFade: CGFloat
    let compactFocusAnchor: CGFloat

    init(height: CGFloat, topChrome: CGFloat, bottomChrome: CGFloat, preferredAnchor: CGFloat = 0.27) {
        let viewport = max(0, height)
        topOcclusion = min(max(0, topChrome), viewport)
        bottomOcclusion = min(max(0, bottomChrome), max(0, viewport - topOcclusion - 64))
        edgeFade = min(16, (viewport - topOcclusion - bottomOcclusion) / 2)
        let belowHeader = viewport > 0 ? (topOcclusion + 24) / viewport : 0
        compactFocusAnchor = min(0.72, max(preferredAnchor, belowHeader))
    }
}

struct LyricWord: Equatable {
    let text: String
    let startMs: Int64
    let endMs: Int64
}

struct LyricTextSpan: Equatable {
    let text: String
    let timing: LyricWord?
}

enum LyricTextSpans {
    /// Annotate the displayed provider string in order. Separators, explicit
    /// line breaks and scripts written without spaces stay exactly as supplied.
    static func make(text: String, words: [LyricWord]) -> [LyricTextSpan] {
        var spans: [LyricTextSpan] = []
        var cursor = text.startIndex
        var searchStart = cursor
        for word in words {
            let token = word.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty,
                  let match = text.range(of: token, options: [.caseInsensitive, .diacriticInsensitive],
                                         range: searchStart..<text.endIndex) else { continue }
            searchStart = match.upperBound
            guard word.endMs > word.startMs else { continue }
            if cursor < match.lowerBound {
                spans.append(LyricTextSpan(text: String(text[cursor..<match.lowerBound]), timing: nil))
            }
            spans.append(LyricTextSpan(text: String(text[match]), timing: word))
            cursor = match.upperBound
        }
        if cursor < text.endIndex {
            spans.append(LyricTextSpan(text: String(text[cursor...]), timing: nil))
        }
        return spans
    }
}

enum LyricPlaybackTime {
    static func milliseconds(at seconds: Double, offsetMs: Int32) -> Int64 {
        guard seconds.isFinite else { return 0 }
        let milliseconds = (seconds * 1000).rounded(.towardZero) - Double(offsetMs)
        if milliseconds >= Double(Int64.max) { return .max }
        return Int64(max(0, milliseconds))
    }
}

/// Which lines are sung and which line the transcript follows.
struct LyricFocusState: Equatable {
    var document: ObjectIdentifier?
    var active: [Int] = []
    var lead = 0
    var gap: Int?
    var audenScrollLead: Int? = nil
    var audenScrollMilliseconds: Int64 = 400
}

struct LyricTimingLine {
    let start: Int64
    let end: Int64
    let holds: Bool
    let isGap: Bool
    var secondVoice = false

    static func start(nominal: Int64, firstLead: Int64?, firstBacking: Int64?) -> Int64 {
        if let firstLead { return min(firstLead, firstBacking ?? firstLead) }
        return nominal == 0 ? firstBacking ?? nominal : nominal
    }
}

/// Playback samples query a prepared index. Most provider sheets are ordered
/// and take one binary search plus any still-overlapping voices.
struct LyricTimingIndex {
    private let lines: [LyricTimingLine]
    private let chronological: Bool
    private let precedingVerse: [Int]
    private let maximumHoldEnd: [Int64]
    private let synced: Bool

    init(lines: [LyricTimingLine], synced: Bool) {
        self.lines = lines
        self.synced = synced
        chronological = zip(lines, lines.dropFirst()).allSatisfy { pair in pair.0.start <= pair.1.start }

        var lastVerse = -1
        var lastHoldEnd = Int64.min
        var verses: [Int] = []
        var holdEnds: [Int64] = []
        for (index, line) in lines.enumerated() {
            if !line.isGap {
                lastVerse = index
                if line.holds { lastHoldEnd = max(lastHoldEnd, line.end) }
            }
            verses.append(lastVerse)
            holdEnds.append(lastHoldEnd)
        }
        precedingVerse = verses
        maximumHoldEnd = holdEnds
    }

    private func lastStarted(by position: Int64) -> Int {
        // Keep the provider's original row ordering for out-of-order timestamps.
        guard chronological else { return lines.lastIndex { $0.start <= position } ?? -1 }

        var lower = 0
        var upper = lines.count
        while lower < upper {
            let midpoint = lower + (upper - lower) / 2
            if lines[midpoint].start <= position { lower = midpoint + 1 }
            else { upper = midpoint }
        }
        return lower - 1
    }

    func focus(at position: Int64, document: ObjectIdentifier?) -> LyricFocusState {
        guard synced, !lines.isEmpty else { return LyricFocusState(document: document) }
        let latest = lastStarted(by: position)
        var active: [Int] = []
        let currentGap = latest >= 0 && lines[latest].isGap ? latest : nil
        if latest >= 0, currentGap == nil {
            let current = lines[latest]
            // An explicit end releases the lead during silence. When a new
            // verse starts, only a genuinely overlapping other voice can
            // keep its emphasis. Inline backing vocals are drawn in one row.
            if !current.holds || position < current.end { active.append(latest) }
            var index = latest - 1
            while index >= 0, maximumHoldEnd[index] > position {
                let line = lines[index]
                if !line.isGap, line.start <= position, line.secondVoice != current.secondVoice {
                    if line.holds, position < line.end { active.insert(index, at: 0) }
                    break
                }
                index -= 1
            }
        }

        let lead: Int
        if let first = active.first {
            lead = first
        } else {
            let (ahead, overflow) = position.addingReportingOverflow(scrollLead(after: latest))
            let next = lastStarted(by: overflow ? .max : ahead)
            if chronological {
                lead = next < 0 ? -1 : precedingVerse[next]
            } else {
                lead = lines.lastIndex { !$0.isGap && $0.start <= (overflow ? .max : ahead) } ?? -1
            }
        }
        return LyricFocusState(document: document, active: active, lead: max(0, lead), gap: currentGap)
    }

    // Auden anticipates the next anchor. Keep the timing of the active voices,
    // lyric gap and attributed text on the undisturbed provider clock.
    func audenFocus(at position: Int64, document: ObjectIdentifier?) -> LyricFocusState {
        var current = focus(at: position, document: document)
        guard synced, !lines.isEmpty else { return current }
        let milliseconds = scrollLead(after: lastStarted(by: position))
        let (advanced, overflow) = position.addingReportingOverflow(milliseconds)
        let ahead = focus(at: overflow ? .max : advanced, document: document)
        current.audenScrollLead = ahead.active.first ?? ahead.gap ?? ahead.lead
        current.audenScrollMilliseconds = milliseconds
        return current
    }

    private func scrollLead(after index: Int) -> Int64 {
        guard index >= 0, index + 1 < lines.count else { return 350 }
        let (gap, overflow) = lines[index + 1].start.subtractingReportingOverflow(lines[index].end)
        if overflow { return lines[index + 1].start > lines[index].end ? 500 : 350 }
        return min(max(gap, 350), 500)
    }
}


enum AudenLyricMetrics {
    private static let phone = [1.0, 0.74, 0.60, 0.48, 0.40, 0.34]
    private static let wide = [1.0, 0.80, 0.70, 0.58, 0.46]
    private static let radii: [CGFloat] = [0, 3.5, 5, 7.5, 10]

    static func alpha(distance: Int, compact: Bool) -> Double {
        let steps = compact ? phone : wide
        return steps[min(max(0, distance), steps.count - 1)]
    }

    static func blur(distance: Int) -> CGFloat {
        radii[min(max(0, distance), radii.count - 1)]
    }

    static func sectionTitle(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (3...60).contains(trimmed.utf16.count), trimmed.first == "[", trimmed.last == "]" else { return nil }
        return trimmed.dropFirst().dropLast().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
