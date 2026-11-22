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

/// The transcript allocates text, effects and the opposite voice's lane from
/// the scroll viewport's proposed width.
struct LyricRowGeometry: Equatable {
    let documentInset: CGFloat
    let rowWidth: CGFloat
    let effectInset: CGFloat
    let duetInset: CGFloat
    let textWidth: CGFloat

    init(viewportWidth: CGFloat, compact: Bool, duet: Bool) {
        let viewport = max(0, viewportWidth)
        documentInset = min(compact ? 12 : 2, viewport * 0.10)
        rowWidth = viewport - 2 * documentInset
        effectInset = min(14, rowWidth * 0.10)
        let interior = rowWidth - 2 * effectInset
        duetInset = duet ? min(44, interior * 0.18) : 0
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

    init(height: CGFloat, topChrome: CGFloat, bottomChrome: CGFloat) {
        let viewport = max(0, height)
        topOcclusion = min(max(0, topChrome), viewport)
        bottomOcclusion = min(max(0, bottomChrome), max(0, viewport - topOcclusion - 64))
        edgeFade = min(16, (viewport - topOcclusion - bottomOcclusion) / 2)
        let belowHeader = viewport > 0 ? (topOcclusion + 24) / viewport : 0
        compactFocusAnchor = max(0.27, min(0.72, belowHeader))
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
}

struct LyricTimingLine {
    let start: Int64
    let end: Int64
    let holds: Bool
    let isGap: Bool
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
        if latest >= 0, currentGap == nil { active.append(latest) }

        var index = latest - 1
        while index >= 0, maximumHoldEnd[index] > position {
            let line = lines[index]
            if !line.isGap, line.holds, line.start <= position, position < line.end {
                active.append(index)
            }
            index -= 1
        }
        active.reverse()

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

    private func scrollLead(after index: Int) -> Int64 {
        guard index >= 0, index + 1 < lines.count else { return 350 }
        let (gap, overflow) = lines[index + 1].start.subtractingReportingOverflow(lines[index].end)
        if overflow { return lines[index + 1].start > lines[index].end ? 500 : 350 }
        return min(max(gap, 350), 500)
    }
}
