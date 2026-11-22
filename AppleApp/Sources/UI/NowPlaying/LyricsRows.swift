import SwiftUI
import BitChordShared

// How the lyric list is drawn, and how little of it has to move.
//
// The list used to sit inside a frame clock: every display frame re-ran the
// whole pane, asked the shared module three times which lines were being sung
// (each call walking the bridged list), re-split every line's words and rebuilt
// every row. That was one core, flat out, for as long as the lyrics were open.
//
// Now the work is split by how often it actually changes:
// - the document (rows, words, timings) is prepared once per lyric;
// - which lines are sung is read thirty times a second by a ticker that draws
//   nothing and only hands the pane a new focus when it differs, which is once
//   per line;
// - only the line being sung reads the clock every frame, and it only redraws
//   its own glyphs through [LyricSweepRenderer] — no layout, no list.

/// Where the transport is, for the views that need to know between ticks.
///
/// Handed down rather than a position, so reading the clock is something only
/// the line being sung (and the ticker) does. A position parameter re-ran the
/// whole pane every time it moved.
struct LyricsClock {
    var playing: Bool
    var pausedPosition: Double? = nil
    var read: (Date) -> Double

    /// The lyric clock in milliseconds: the transport, `offsetMs` behind.
    func lyricMs(at date: Date, offsetMs: Int32) -> Int64 {
        LyricPlaybackTime.milliseconds(at: pausedPosition ?? read(date), offsetMs: offsetMs)
    }
}

/// Adapts provider DTOs to the same timeline used by the transcript and the
/// player snippet.
private enum LyricTimeline {
    /// `LyricFocus.startTimes`: an untimed line in a partly timed lyric sits
    /// between the timed lines around it (a few seconds a line past the last
    /// one) instead of reading as "started at zero", which made the last
    /// untimed line in the song the current one and threw the highlight to a
    /// chorus minutes away while BitChord was still timing the words.
    static func startTimes(_ lines: [LyricLineDto]) -> [Int64] {
        let raw = lines.map(startMs)
        let known = raw.indices.map { $0 == 0 || raw[$0] > 0 }
        if known.allSatisfy({ $0 }) { return raw }
        var starts = raw
        var previous = 0
        var index = 1
        while index < lines.count {
            if known[index] {
                previous = index
                index += 1
                continue
            }
            var next = index
            while next < lines.count, !known[next] { next += 1 }
            let base = raw[previous]
            for missing in index..<next {
                let steps = Int64(missing - previous)
                starts[missing] = next < lines.count
                    ? base + max(raw[next] - base, 0) * steps / Int64(next - previous)
                    : base + untimedLineMs * steps
            }
            index = next
        }
        return starts
    }

    private static let untimedLineMs: Int64 = 4_000

    /// Word-synced rows acquire focus at the first usable word. Some providers
    /// stamp the paragraph earlier than the first syllable of a verse.
    static func startMs(_ line: LyricLineDto) -> Int64 {
        guard !line.isGap else { return line.timeMs }
        let lead = firstWord(in: line.words)
        let backing = line.background.flatMap { firstWord(in: $0.words) }
        return LyricTimingLine.start(nominal: line.timeMs, firstLead: lead, firstBacking: backing)
    }

    private static func firstWord(in words: [LyricWordDto]) -> Int64? {
        words.lazy.filter { $0.endMs > $0.startMs }.map(\.startMs).min()
    }

}

/// One lyric line, prepared for drawing: everything the row needs that does not
/// depend on the clock.
struct LyricRow: Identifiable {
    let id: Int
    let isGap: Bool
    /// The line has its own timings. False for the rows of a transcript that
    /// on-device alignment has not reached yet; those stay crisp.
    let timed: Bool
    let secondVoice: Bool
    let rightToLeft: Bool
    /// Provider text used in both the static and timed render paths.
    let leadText: String
    let backingText: String?
    /// The same words with their timings attached, for the sweep. Built once
    /// here: the frame clock only changes how they are drawn.
    let leadSwept: Text?
    let backingSwept: Text?
    let timeMs: Int64
    /// Where the break that this row stands for ends, for its dots.
    let untilMs: Int64
}

/// The lyric document as the pane draws it, rebuilt only when the lines do.
final class PreparedLyrics {
    let source: [LyricLineDto]
    let rows: [LyricRow]
    let timeline: LyricTimingIndex
    let synced: Bool
    /// Some line is sung from the other side, so both voices keep a lane.
    let duet: Bool
    /// Every lyric row has timings (no "partially synced" credit).
    let fullyTimed: Bool

    init(lines: [LyricLineDto]) {
        source = lines
        let synced = LyricFocus.shared.isSynced(lines: lines)
        self.synced = synced
        var rows: [LyricRow] = []
        rows.reserveCapacity(lines.count)
        let starts = LyricTimeline.startTimes(lines)
        timeline = LyricTimingIndex(lines: zip(starts, lines).map { start, line in
            LyricTimingLine(start: start, end: line.endMs,
                            holds: line.endMs > start && (line.hasKnownEnd || line.background?.hasKnownEnd == true),
                            isGap: line.isGap, secondVoice: line.alignment == .end)
        }, synced: synced)
        for (index, line) in lines.enumerated() {
            rows.append(Self.row(line, at: index, synced: synced,
                                 until: index + 1 < lines.count ? starts[index + 1] : line.endMs))
        }
        self.rows = rows
        duet = lines.contains { $0.alignment == .end }
        let lyricRows = rows.filter { !$0.isGap }
        fullyTimed = lyricRows.allSatisfy(\.timed)
    }

    private static func row(_ line: LyricLineDto, at index: Int, synced: Bool, until: Int64) -> LyricRow {
        let leadText: String
        let backingText: String?
        let leadWords: [LyricWord]
        let backingWords: [LyricWord]
        if let background = line.background, !background.text.isEmpty {
            leadText = line.text
            backingText = background.text
            leadWords = line.words.map(word)
            backingWords = background.words.map(word)
        } else {
            let split = splitBackground(line.text)
            leadText = split.lead
            backingText = split.backing
            leadWords = line.words.filter { !isBackingToken($0.text) }.map(word)
            backingWords = line.words.filter { isBackingToken($0.text) }.map(word)
        }
        let timed = line.timeMs > 0 || line.sungUntilMs != nil ||
            line.words.contains(where: { $0.startMs > 0 || $0.endMs > 0 }) ||
            (line.background?.timeMs ?? 0) > 0 ||
            line.background?.words.contains(where: { $0.startMs > 0 || $0.endMs > 0 }) == true ||
            // A timed document's first line may really start at zero.
            (index == 0 && synced)
        let shown = leadText.isEmpty ? leadWords.map(\.text).joined(separator: " ") : leadText
        let backingShown = backingText ?? (backingWords.isEmpty ? nil : backingWords.map(\.text).joined(separator: " "))
        return LyricRow(
            id: index,
            isGap: line.isGap,
            timed: timed,
            secondVoice: line.alignment == .end,
            rightToLeft: lyricTextIsRightToLeft(shown),
            leadText: shown.isEmpty ? "♪" : shown,
            backingText: backingShown.flatMap { $0.isEmpty ? nil : $0 },
            leadSwept: swept(shown, words: leadWords),
            backingSwept: backingShown.flatMap { swept($0, words: backingWords) },
            timeMs: line.timeMs,
            untilMs: until
        )
    }

    private static func word(_ dto: LyricWordDto) -> LyricWord {
        LyricWord(
            text: dto.text.replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: ""),
            startMs: dto.startMs,
            endMs: dto.endMs
        )
    }

    /// Build the attributed display text once, keeping the provider's wrapping
    /// opportunities and marking only word spans with a real duration.
    private static func swept(_ text: String, words: [LyricWord]) -> Text? {
        let spans = LyricTextSpans.make(text: text, words: words)
        guard spans.contains(where: { $0.timing != nil }) else { return nil }
        var rendered = Text(verbatim: "")
        for (index, span) in spans.enumerated() {
            let literal = Text(verbatim: span.text)
            let piece = span.timing.map {
                literal.customAttribute(LyricWordTiming(startMs: $0.startMs, endMs: $0.endMs))
            } ?? literal
            rendered = index == 0 ? piece : Text("\(rendered)\(piece)")
        }
        return rendered
    }

    private static func isBackingToken(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("(") || trimmed.hasSuffix(")")
    }

    /// Display-only split matching upstream `withBackgroundVocals`.
    static func splitBackground(_ text: String) -> (lead: String, backing: String?) {
        guard let open = text.firstIndex(of: "("), let close = text.lastIndex(of: ")"), close > open else {
            return (text, nil)
        }
        let inner = text[text.index(after: open)..<close].trimmingCharacters(in: .whitespaces)
        guard !inner.isEmpty else { return (text, nil) }
        let lead = (text[..<open] + text[text.index(after: close)...]).trimmingCharacters(in: .whitespaces)
        return (lead.isEmpty ? "♪" : String(lead), String(inner))
    }
}

/// Holds the prepared document between renders. Not observable: it is a memo,
/// and replacing its contents is never itself a reason to redraw.
final class LyricsDocumentCache {
    private var current: PreparedLyrics?

    func document(for lines: [LyricLineDto]) -> PreparedLyrics {
        if let current, current.source.count == lines.count,
           zip(current.source, lines).allSatisfy({ $0 === $1 }) {
            return current
        }
        let prepared = PreparedLyrics(lines: lines)
        current = prepared
        return prepared
    }
}

// MARK: - Look

enum LyricStyle {
    static func controlsFade(_ reduceMotion: Bool) -> Animation {
        .easeInOut(duration: reduceMotion ? 0.12 : 0.24)
    }
    static let unsungAlpha = 0.45
    static let backingAlpha = 0.72
    static let backingScale: CGFloat = 23.0 / 34.0
    static let wipeFeather: CGFloat = 30
    static let wordRise: CGFloat = 2
    /// A note held at least this long glows; quick syllables never do.
    static let heldNoteMs: Int64 = 900
    static let rowInset: CGFloat = 10
    static let headerTopPadding: CGFloat = 8
    static let headerBottomPadding: CGFloat = 14
    static var minimumHeaderHeight: CGFloat {
        PlayerLayout.sleeveCollapsedSide + headerTopPadding + headerBottomPadding
    }
}

// MARK: - Sweep

/// A word's timing, carried on its glyph run to the renderer.
struct LyricWordTiming: TextAttribute {
    let startMs: Int64
    let endMs: Int64
}

/// Draws the line being sung: words ahead of the singer held back, the sung
/// part lit by a feathered wavefront rather than a hard cut, each word lifting
/// a couple of points as it is reached, and a soft bloom only on notes that are
/// actually held. No underline, no change of weight — the text never reflows.
///
/// Drawing only: the layout is the `Text`'s own and is not redone per frame.
struct LyricSweepRenderer: TextRenderer {
    /// Nil draws the same attributed glyphs at rest.
    var ms: Int64?
    var glowAlpha: Double
    var glowRadius: CGFloat
    var reduceMotion: Bool

    var displayPadding: EdgeInsets {
        let halo = glowAlpha > 0 && !reduceMotion ? glowRadius * 2 : 0
        let lift = reduceMotion ? 0 : LyricStyle.wordRise
        return EdgeInsets(top: halo + lift, leading: halo, bottom: halo, trailing: halo)
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            guard let ms else {
                context.draw(line)
                continue
            }
            for run in line {
                if let timing = run[LyricWordTiming.self] {
                    draw(run, timing: timing, at: ms, in: context)
                } else {
                    // Unmatched words stay readable at the resting intensity.
                    // The renderer has no timestamp to justify illuminating them.
                    var resting = context
                    resting.opacity *= LyricStyle.unsungAlpha
                    resting.draw(run)
                }
            }
        }
    }

    private func draw(_ run: Text.Layout.Run, timing: LyricWordTiming, at ms: Int64, in base: GraphicsContext) {
        let progress = LyricWordProgress.at(ms, start: timing.startMs, end: timing.endMs)
        var context = base
        if reduceMotion {
            context.opacity *= LyricStyle.unsungAlpha + (1 - LyricStyle.unsungAlpha) * progress
            context.draw(run)
            return
        }
        if progress > 0 {
            // Up in the first third of the word, and it stays up for the rest of
            // the line.
            let rise = 1 - pow(1 - min(1, progress * 3), 3)
            context.translateBy(x: 0, y: -LyricStyle.wordRise * rise)
        }
        if progress >= 1 {
            context.draw(run)
            return
        }
        var dim = context
        dim.opacity *= LyricStyle.unsungAlpha
        dim.draw(run)
        guard progress > 0 else { return }

        let rect = run.typographicBounds.rect
        let feather = min(LyricStyle.wipeFeather, max(8, rect.width * 0.55))
        let travel = rect.width + feather
        let rtl = run.layoutDirection == .rightToLeft
        let edge = rtl ? rect.maxX + feather - progress * travel : rect.minX - feather + progress * travel
        let band = rect.insetBy(dx: -feather, dy: -glowRadius)
        var lit = context
        lit.clipToLayer { mask in
            mask.fill(
                Path(band),
                with: .linearGradient(
                    Gradient(colors: [.white, .white.opacity(0)]),
                    startPoint: CGPoint(x: edge, y: band.midY),
                    endPoint: CGPoint(x: rtl ? edge - feather : edge + feather, y: band.midY)
                )
            )
        }
        // The same mask advances both the highlight and the held-note glow.
        // Unreached characters never light up from the halo.
        if glowAlpha > 0, Double(timing.endMs) - Double(timing.startMs) >= Double(LyricStyle.heldNoteMs) {
            var halo = lit
            halo.addFilter(.blur(radius: glowRadius))
            halo.opacity *= glowAlpha * LyricWordProgress.glowEnvelope(progress)
            halo.draw(run)
        }
        lit.draw(run)
    }
}

// MARK: - Views

/// Reads the clock thirty times a second and reports the focus when it changes.
/// Draws nothing, so its own updates cost almost nothing.
struct LyricsFocusTicker: View {
    let document: PreparedLyrics
    let clock: LyricsClock
    let offsetMs: Int32
    let onChange: (LyricFocusState) -> Void

    var body: some View {
        Group {
            if clock.playing {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    sample(at: timeline.date)
                }
            } else {
                sample(at: Date())
            }
        }
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func sample(at date: Date) -> some View {
        let focus = document.timeline.focus(
            at: clock.lyricMs(at: date, offsetMs: offsetMs),
            document: ObjectIdentifier(document)
        )
        return Color.clear.onChange(of: focus, initial: true) { _, focus in onChange(focus) }
    }
}

/// What a tap on a row does. Part of the row's equality, so a row that is not
/// redrawn never keeps an out-of-date tap.
enum LyricTapMode: Equatable {
    case reveal, pick, seek
}

struct LyricRowView: View, Equatable {
    let row: LyricRow
    let document: ObjectIdentifier
    let active: Bool
    let look: LyricRowLook
    let fontSize: CGFloat
    let geometry: LyricRowGeometry
    let presentation: LyricPresentation
    let picked: Bool
    let picking: Bool
    let tapMode: LyricTapMode
    let offsetMs: Int32
    let clock: LyricsClock
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static func == (lhs: LyricRowView, rhs: LyricRowView) -> Bool {
        lhs.row.id == rhs.row.id && lhs.document == rhs.document && lhs.active == rhs.active &&
            lhs.look == rhs.look && lhs.fontSize == rhs.fontSize && lhs.geometry == rhs.geometry &&
            lhs.presentation == rhs.presentation &&
            lhs.picked == rhs.picked && lhs.picking == rhs.picking && lhs.tapMode == rhs.tapMode &&
            lhs.offsetMs == rhs.offsetMs && (!lhs.active ||
                (lhs.clock.playing == rhs.clock.playing && lhs.clock.pausedPosition == rhs.clock.pausedPosition))
    }

    private var position: LyricTextPosition { presentation.alignment.resolved(secondVoice: row.secondVoice) }

    private var scaleAnchor: UnitPoint {
        if position == .center { return .center }
        let physicalTrailing = (position == .trailing) != row.rightToLeft
        return UnitPoint(x: physicalTrailing ? 1 : 0, y: 0.5)
    }

    var body: some View {
        VStack(alignment: position.horizontal, spacing: 2) {
            line(row.leadText, swept: row.leadSwept, size: fontSize, glow: true)
            if let backing = row.backingText {
                line(backing, swept: row.backingSwept, size: fontSize * LyricStyle.backingScale, glow: false)
                    .opacity(LyricStyle.backingAlpha)
            }
        }
        .frame(width: geometry.textWidth, alignment: position.frame)
        .padding(.leading, row.secondVoice ? geometry.duetInset : 0)
        .padding(.trailing, row.secondVoice ? 0 : geometry.duetInset)
        .padding(.vertical, LyricStyle.rowInset * 0.8)
        .padding(.horizontal, geometry.effectInset)
        .frame(width: geometry.rowWidth, alignment: position.frame)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(picked ? 0.16 : (picking ? 0.05 : 0)))
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture(perform: onTap)
        .environment(\.layoutDirection, row.rightToLeft ? .rightToLeft : .leftToRight)
        // Commit the intensity with the glyph state. Delaying it would show
        // the outgoing row's resting glyphs at their old full intensity.
        .opacity(look.alpha)
        .animation(presentation.emphasis(reduceMotion: reduceMotion)) { content in
            content.scaleEffect(reduceMotion ? 1 : look.scale, anchor: scaleAnchor)
        }
        .animation(active ? nil : presentation.emphasis(reduceMotion: reduceMotion)) { content in
            content.blur(radius: look.blur)
        }
    }

    private func line(_ plain: String, swept: Text?, size: CGFloat, glow: Bool) -> some View {
        LyricGlyphs(plain: plain, swept: swept, active: active, glow: glow, offsetMs: offsetMs, clock: clock,
                    presentation: presentation)
            .scaledFont(size: size, weight: presentation.weight.fontWeight, design: .default)
            .foregroundStyle(.white)
            .multilineTextAlignment(position.text)
            .lineSpacing(size * 0.06)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: geometry.textWidth, alignment: position.frame)
    }
}

/// Both lyric surfaces use the same word renderer and adjusted transport time.
struct LyricGlyphs: View {
    let plain: String
    let swept: Text?
    let active: Bool
    let glow: Bool
    let offsetMs: Int32
    let clock: LyricsClock
    var presentation: LyricPresentation = .init()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var simpleMotion: Bool { reduceMotion || presentation.reduceEffects }

    var body: some View {
        if presentation.wordHighlight, let swept {
            if active && clock.playing {
                TimelineView(.animation(minimumInterval: simpleMotion ? 1.0 / 30.0 : nil)) { timeline in
                    rendered(swept, at: clock.lyricMs(at: timeline.date, offsetMs: offsetMs))
                }
            } else {
                // Keep the same attributed text and renderer padding. Inactive
                // rows and paused playback don't install a display schedule.
                rendered(swept, at: active ? clock.lyricMs(at: .now, offsetMs: offsetMs) : nil)
            }
        } else {
            Text(verbatim: plain)
        }
    }

    private func rendered(_ text: Text, at ms: Int64?) -> some View {
        text.textRenderer(LyricSweepRenderer(ms: ms, glowAlpha: glow ? presentation.glowAlpha : 0,
                                              glowRadius: presentation.glowRadius, reduceMotion: simpleMotion))
    }
}

/// A small fixed slot for a provider's instrumental break. The dots fade in
/// without relaying out the surrounding lyric text during automatic scrolling.
struct LyricGapRow: View {
    let row: LyricRow
    let open: Bool
    let look: LyricRowLook
    let offsetMs: Int32
    let clock: LyricsClock
    let presentation: LyricPresentation
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let dot: CGFloat = 13
    private let spacing: CGFloat = 5

    var body: some View {
        Group {
            if open && clock.playing {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    dots(through: through(at: timeline.date))
                }
            } else {
                dots(through: open ? through(at: .now) : 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: presentation.alignment.resolved(secondVoice: row.secondVoice).frame)
        .frame(height: dot + LyricStyle.rowInset * 2)
        .padding(.horizontal, LyricStyle.rowInset)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .allowsHitTesting(open)
        .opacity(open ? look.alpha : 0)
        .animation(presentation.emphasis(reduceMotion: reduceMotion), value: open)
        .accessibilityLabel("Instrumental")
        .accessibilityHidden(!open)
    }

    private func through(at date: Date) -> Double {
        let now = clock.lyricMs(at: date, offsetMs: offsetMs)
        let span = max(1, row.untilMs - row.timeMs)
        return min(1, max(0, Double(now - row.timeMs) / Double(span)))
    }

    private func dots(through: Double) -> some View {
        HStack(spacing: spacing) {
            ForEach(0..<3, id: \.self) { index in
                let lit = min(1, max(0, through * 3 - Double(index)))
                Circle()
                    .fill(.white.opacity(0.25 + 0.75 * lit))
                    .frame(width: dot, height: dot)
            }
        }
    }
}
