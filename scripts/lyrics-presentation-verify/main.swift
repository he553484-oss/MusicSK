import Foundation

func appearance(
    _ distance: Int, timed: Bool = true, synced: Bool = true, active: Bool = false,
    browsing: Bool = false, blurEnabled: Bool = true, upcoming: Bool = false
) -> LyricRowLook {
    LyricRowLook.forLine(
        timed: timed, synced: synced, active: active, distance: distance,
        compact: true, browsing: browsing, blurEnabled: blurEnabled, upcoming: upcoming
    )
}

let active = appearance(0, active: true)
precondition(active.alpha == 1 && active.blur == 0)

let inactive = (1...5).map { appearance($0) }
for (near, far) in zip(inactive, inactive.dropFirst()) {
    precondition(near.alpha > far.alpha && near.blur < far.blur)
}
precondition(appearance(100) == inactive.last)
precondition(appearance(3, browsing: true).alpha > appearance(3).alpha)
precondition(appearance(3, browsing: true).blur < appearance(3).blur)
precondition(appearance(3, browsing: true).blur > 0)
precondition(appearance(3, blurEnabled: false).blur == 0)
precondition(appearance(3, timed: false).blur == 0)
precondition(appearance(3, synced: false).blur == 0)
precondition(appearance(1, upcoming: true).alpha < appearance(1).alpha)
precondition(appearance(1, upcoming: true).blur == appearance(1).blur)

let positions: [Int64] = [200, 1_000, 1_250, 1_500, 1_750, 2_000, 2_400]
let progress = positions.map { LyricWordProgress.at($0, start: 1_000, end: 2_000) }
precondition(progress == [0, 0, 0.25, 0.5, 0.75, 1, 1])
precondition(LyricWordProgress.at(1_200, start: 1_000, end: 1_000) == 0)
precondition(LyricWordProgress.at(0, start: .min, end: .max) == 0.5)
precondition(LyricWordProgress.glowEnvelope(0) == 0 && LyricWordProgress.glowEnvelope(1) == 0)
precondition(LyricWordProgress.glowEnvelope(0.25) < LyricWordProgress.glowEnvelope(0.5))
precondition(abs(LyricWordProgress.glowEnvelope(0.25) - LyricWordProgress.glowEnvelope(0.75)) < 0.000001)

print("PASS lyric focus separation, manual reading, blur preference, held word progress and glow")

var follow = LyricFollowState()
precondition(follow.follows)
follow.update(.touching)
precondition(!follow.follows && !follow.browsing)
follow.update(.resting)
precondition(follow.follows && follow.resumeTicket == nil)

follow.update(.touching)
follow.update(.moving)
precondition(follow.browsing && !follow.follows && follow.resumeTicket == nil)
follow.update(.moving) // Drag followed by native momentum.
precondition(follow.resumeTicket == nil)
follow.update(.resting)
let firstReturn = follow.resumeTicket!
follow.update(.touching)
follow.returnToPlayhead(ticket: firstReturn)
precondition(follow.browsing && !follow.follows && follow.resumeTicket == nil)
follow.update(.resting)
let secondReturn = follow.resumeTicket!
precondition(secondReturn != firstReturn)
follow.returnToPlayhead(ticket: secondReturn)
precondition(!follow.browsing && follow.follows && follow.returnRevision == 1)
follow.returnToPlayhead(ticket: secondReturn)
precondition(follow.returnRevision == 1)

follow.update(.moving)
follow.update(.resting)
let staleDocument = follow.resumeTicket!
follow.replaceDocument()
follow.returnToPlayhead(ticket: staleDocument)
precondition(follow.follows && follow.returnRevision == 1)
follow.update(.moving)
follow.replaceDocument()
precondition(!follow.follows) // Document changes respect ongoing user contact.
follow.update(.resting)
precondition(follow.follows)

print("PASS lyric follow waits for momentum, rejects stale timers and distinguishes a tap from a drag")

// 590 px capture normalized to the equivalent 393 pt portrait viewport.
let phoneWidth: CGFloat = 590 / 1.5
let compactVerse = LyricRowGeometry(viewportWidth: phoneWidth, compact: true, duet: true)
let compactSolo = LyricRowGeometry(viewportWidth: phoneWidth, compact: true, duet: false)
precondition(compactVerse.effectInset >= 12 && compactVerse.duetInset <= 44)
precondition(compactSolo.textWidth > compactVerse.textWidth && compactSolo.duetInset == 0)
precondition(abs(compactVerse.textWidth + compactVerse.duetInset + 2 * compactVerse.effectInset
                 + 2 * compactVerse.documentInset - phoneWidth) < 0.001)
for width: CGFloat in [590, 320, 240, 96, 0] {
    for compact in [true, false] {
        let geometry = LyricRowGeometry(viewportWidth: width, compact: compact, duet: true)
        // Both alignments allot the same text width. The lane can be leading
        // or trailing in either layout direction without pushing glyphs out.
        let nearLeading = geometry.documentInset + geometry.effectInset
        let nearTrailing = nearLeading
        let farInset = nearLeading + geometry.duetInset
        precondition(geometry.textWidth >= 0)
        precondition(nearLeading + geometry.textWidth <= width - farInset + 0.001)
        precondition(farInset + geometry.textWidth <= width - nearTrailing + 0.001)
    }
}
let phoneViewport = LyricViewportGeometry(height: 720, topChrome: 78, bottomChrome: 230)
precondition(phoneViewport.topOcclusion == 78 && phoneViewport.compactFocusAnchor == 0.27)
let shortViewport = LyricViewportGeometry(height: 220, topChrome: 96, bottomChrome: 190)
precondition(shortViewport.topOcclusion == 96)
precondition(shortViewport.topOcclusion + shortViewport.bottomOcclusion <= 220 - 64)
precondition(shortViewport.compactFocusAnchor > 0.27)

// Match real provider word spans without changing line breaks, direction,
// accented glyphs, punctuation, or the spacing between timed words.
let rtlPhrase = "هَلّا يا صديقي،\nلا تتركني هنا"
let rtlWords = [
    LyricWord(text: "هلا", startMs: 700, endMs: 1000),
    LyricWord(text: "يا", startMs: 1050, endMs: 1250),
    LyricWord(text: "صديقي", startMs: 1400, endMs: 2200),
    LyricWord(text: "تتركني", startMs: 2450, endMs: 3200)
]
let rtlSpans = LyricTextSpans.make(text: rtlPhrase, words: rtlWords)
precondition(rtlSpans.map(\.text).joined() == rtlPhrase)
precondition(rtlSpans.compactMap(\.timing) == rtlWords)
precondition(rtlSpans.contains { $0.timing == nil && $0.text.contains("\n") })

let ltrPhrase = "7-3 — te dejo\nde estorbar…"
let ltrWords = [
    LyricWord(text: "te", startMs: 1010, endMs: 1200),
    LyricWord(text: "dejo", startMs: 1210, endMs: 2200),
    LyricWord(text: "de", startMs: 2200, endMs: 2200),
    LyricWord(text: "no existe", startMs: 2230, endMs: 2700)
]
let ltrSpans = LyricTextSpans.make(text: ltrPhrase, words: ltrWords)
precondition(ltrSpans.map(\.text).joined() == ltrPhrase)
precondition(ltrSpans.compactMap(\.timing) == Array(ltrWords.prefix(2)))
let cjkPhrase = "きみが好き"
let cjkWord = LyricWord(text: "好き", startMs: 500, endMs: 1200)
precondition(LyricTextSpans.make(text: cjkPhrase, words: [cjkWord]) ==
             [LyricTextSpan(text: "きみが", timing: nil), LyricTextSpan(text: "好き", timing: cjkWord)])
let lineTimedOnly = LyricTextSpans.make(text: ltrPhrase, words: [])
precondition(lineTimedOnly == [LyricTextSpan(text: ltrPhrase, timing: nil)])

precondition(LyricPlaybackTime.milliseconds(at: 1.25, offsetMs: 80) == 1170)
precondition(LyricPlaybackTime.milliseconds(at: 1.25, offsetMs: -80) == 1330)
precondition(LyricPlaybackTime.milliseconds(at: 0.02, offsetMs: 80) == 0)
precondition(LyricPlaybackTime.milliseconds(at: .infinity, offsetMs: 0) == 0)

func referenceFocus(in lines: [LyricTimingLine], at position: Int64) -> LyricFocusState {
    let latest = lines.lastIndex { $0.start <= position } ?? -1
    var active: [Int] = []
    if latest >= 0, !lines[latest].isGap {
        let line = lines[latest]
        let otherVoice = lines.indices.last { index in
            index < latest && !lines[index].isGap && lines[index].start <= position &&
                lines[index].secondVoice != line.secondVoice
        }
        if let otherVoice, lines[otherVoice].holds, position < lines[otherVoice].end {
            active.append(otherVoice)
        }
        if !line.holds || position < line.end { active.append(latest) }
    }
    let preview: Int64
    if latest >= 0, latest + 1 < lines.count {
        preview = min(max(lines[latest + 1].start - lines[latest].end, 350), 500)
    } else {
        preview = 350
    }
    let lead = active.first ?? lines.lastIndex { !$0.isGap && $0.start <= position + preview } ?? 0
    return LyricFocusState(active: active, lead: lead, gap: latest >= 0 && lines[latest].isGap ? latest : nil)
}

let timedLines = [
    LyricTimingLine(start: 0, end: 480, holds: false, isGap: true),
    LyricTimingLine(start: 480, end: 1880, holds: true, isGap: false),
    LyricTimingLine(start: 760, end: 1610, holds: true, isGap: false, secondVoice: true),
    LyricTimingLine(start: 760, end: 1900, holds: false, isGap: false),
    LyricTimingLine(start: 1900, end: 5100, holds: false, isGap: true),
    LyricTimingLine(start: 5100, end: 5600, holds: false, isGap: false)
]
for lines in [timedLines, [timedLines[3], timedLines[2], timedLines[0]] + Array(timedLines.dropFirst(4))] {
    let index = LyricTimingIndex(lines: lines, synced: true)
    for position in stride(from: Int64(5600), through: 0, by: -13) {
        precondition(index.focus(at: position, document: nil) == referenceFocus(in: lines, at: position))
    }
}
precondition(LyricTimingIndex(lines: timedLines, synced: false).focus(at: 900, document: nil).active.isEmpty)

let firstActualWord = LyricTimingLine.start(nominal: 2_000, firstLead: 2_350, firstBacking: nil)
precondition(firstActualWord == 2_350)
precondition(LyricTimingLine.start(nominal: 2_000, firstLead: nil, firstBacking: nil) == 2_000)
precondition(LyricTimingLine.start(nominal: 0, firstLead: nil, firstBacking: 2_250) == 2_250)
let solo = LyricTimingIndex(lines: [
    LyricTimingLine(start: 1_000, end: 2_800, holds: true, isGap: false),
    LyricTimingLine(start: firstActualWord, end: 2_700, holds: true, isGap: false)
], synced: true)
precondition(solo.focus(at: 2_349, document: nil).active == [0])
precondition(solo.focus(at: 2_350, document: nil).active == [1])
precondition(solo.focus(at: 2_700, document: nil).active.isEmpty)
precondition(solo.focus(at: 2_100, document: nil).active == [0]) // seek back
let duetIndex = LyricTimingIndex(lines: timedLines, synced: true)
precondition(duetIndex.focus(at: 760, document: nil).active == [2, 3])
precondition(duetIndex.focus(at: 1610, document: nil).active == [3])
precondition(duetIndex.focus(at: 1900, document: nil).active.isEmpty)

print("PASS bounded widths for both voice alignments, header occlusion, real RTL/multiline spans, and focused timeline equivalence")
