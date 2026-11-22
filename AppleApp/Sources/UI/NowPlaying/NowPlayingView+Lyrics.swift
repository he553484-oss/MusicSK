import SwiftUI
import BitChordShared
import UniformTypeIdentifiers
import AVKit
import CoreImage
import CoreImage.CIFilterBuiltins
#if os(iOS)
import UIKit
import AVFAudio
#else
import AppKit
#endif

// The lyrics header, the current-line strip, and showing their controls.
extension NowPlayingView {
    /// Compact credits and return to artwork. This row stays accessible while
    /// the phone's transport fades out beneath the lyrics.
    var lyricsHeader: some View {
        lyricsHeader(usesSharedArtwork: false)
    }

    func lyricsHeader(usesSharedArtwork: Bool) -> some View {
        HStack(spacing: 12) {
            Button {
                Haptics.play(.tap)
                pane = .main
            } label: {
                if usesSharedArtwork {
                    Color.clear
                        .frame(width: PlayerLayout.sleeveCollapsedSide, height: PlayerLayout.sleeveCollapsedSide)
                        .anchorPreference(key: PlayerArtworkFrames.self, value: .bounds) { [.lyrics: $0] }
                        .contentShape(Rectangle())
                } else {
                    SleeveArt(
                        entry: controller.current,
                        canvasURL: controller.canvasURL,
                        fallbackURL: controller.canvasFallbackURL,
                        isPlaying: controller.isPlaying,
                        side: PlayerLayout.sleeveCollapsedSide
                    )
                    .id(controller.current?.id)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to player")

            VStack(alignment: .leading, spacing: 3) {
                Text(controller.current?.title ?? String(localized: "Nothing playing"))
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                ArtistCreditText(
                    credit: controller.current?.artist ?? "",
                    artistId: controller.current?.artistId,
                    font: .subheadline,
                    color: .white.opacity(0.7)
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if auth.signedIn, controller.current?.videoId != nil {
                GlassCircleButton(
                    icon: controller.isLiked ? .bchHeartFilled : .bchHeart,
                    label: controller.isLiked ? "Remove Like" : "Like"
                ) { controller.toggleLike() }
            }
            if controller.displayedLyrics.isEmpty {
                moreMenu
            } else {
                // Upstream 89912638/aa5ff748: with lyrics up the header's
                // three-dot becomes the share entry, since a card quotes *this*
                // lyric — and becomes the way out while lines are picked.
                GlassCircleButton(
                    system: sharePicking ? "xmark" : "square.and.arrow.up",
                    label: sharePicking ? "Stop picking lyrics" : "Share lyrics"
                ) {
                    Haptics.play(.tap)
                    sharePicking.toggle()
                }
                .help(sharePicking ? "Stop picking lyrics" : "Share lyrics")
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, LyricStyle.headerTopPadding)
        .padding(.bottom, LyricStyle.headerBottomPadding)
        .foregroundStyle(.white)
    }

    /// A short readout of the currently sung verse and an entry to the transcript.
    @ViewBuilder
    var currentLyricStrip: some View {
        if showsLyricLine {
            CompactLyricStrip(
                lines: controller.displayedLyrics,
                hasTrack: controller.current != nil,
                loading: controller.lyricsLoading,
                unavailable: controller.lyricsUnavailable,
                clock: lyricsClock,
                offsetMs: lyricsOffsetMs,
                presentation: lyricStyle.presentation,
                onOpen: {
                    Haptics.play(.expand)
                    pane = pane == .lyrics ? .main : .lyrics
                }
            )
        }
    }

    func revealLyricsControls() {
        lyricsControlsOpen = true
        lyricsControlActivity += 1
    }

    func hideLyricsControls() {
        guard !lyricsScrubbing, !volumeDragging, !sharePicking else { return }
        lyricsControlsOpen = false
    }
}


private struct CompactLyricStrip: View {
    let lines: [LyricLineDto]
    let hasTrack: Bool
    let loading: Bool
    let unavailable: Bool
    let clock: LyricsClock
    let offsetMs: Int32
    let presentation: LyricPresentation
    let onOpen: () -> Void

    @State private var cache = LyricsDocumentCache()
    @State private var latestFocus = LyricFocusState()
    @ScaledMetric(relativeTo: .subheadline) private var stripHeight = 20.0

    var body: some View {
        let document = cache.document(for: lines)
        let id = ObjectIdentifier(document)
        let focus = latestFocus.document == id ? latestFocus : document.timeline.focus(
            at: clock.lyricMs(at: .now, offsetMs: offsetMs), document: id
        )
        let row = focus.active.first.flatMap { document.rows.indices.contains($0) ? document.rows[$0] : nil }
        Button(action: onOpen) {
            Group {
                if let row {
                    HStack(spacing: 6) {
                        LyricGlyphs(
                            plain: row.leadText, swept: row.leadSwept, active: true, glow: false,
                            offsetMs: offsetMs, clock: clock, presentation: presentation
                        )
                        .foregroundStyle(.white.opacity(0.92))
                        .multilineTextAlignment(.leading)
                        .layoutPriority(1)
                        Image(.bchChevronRight)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 9, height: 9)
                            .foregroundStyle(.white.opacity(0.55))
                            .scaleEffect(x: row.rightToLeft ? -1 : 1)
                            .accessibilityHidden(true)
                    }
                    .environment(\.layoutDirection, row.rightToLeft ? .rightToLeft : .leftToRight)
                } else if loading {
                    Text("Looking for lyrics…")
                        .foregroundStyle(.white.opacity(0.5))
                } else if unavailable {
                    Text("No lyrics for this track")
                        .foregroundStyle(.white.opacity(0.5))
                } else if !document.synced {
                    Text(hasTrack ? "Lyrics off" : "")
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .font(.subheadline.weight(.medium))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .center)
            .shadow(color: .black.opacity(0.45), radius: 5, y: 1)
            .padding(.horizontal, 24)
            .frame(height: stripHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(row == nil)
        .accessibilityLabel(voiceOverLabel(for: row))
        .accessibilityHint("Opens the lyrics")
        .background {
            if document.synced {
                LyricsFocusTicker(document: document, clock: clock, offsetMs: offsetMs) { focus in
                    if latestFocus != focus { latestFocus = focus }
                }
            }
        }
    }

    private func voiceOverLabel(for row: LyricRow?) -> String {
        if let row {
            let line = row.leadText
            return String(localized: "Now singing: \(line)")
        }
        return loading ? String(localized: "Looking for lyrics") : String(localized: "No lyrics")
    }
}
