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

// The iPhone and iPad layouts: portrait, two-column and compact landscape.
extension NowPlayingView {
    // ---- The player's arrangements -----------------------------------------
    //
    // Upstream's portrait player is two things, and the port had them the wrong
    // way up. A *pinned bottom deck* — credits, scrubber, transport, toggles —
    // measured at its natural height and fixed to the foot of the screen, and the
    // space above it, which is whatever the artwork or an open panel needs.
    //
    // What this had instead was one `VStack`: the artwork at full size, then
    // everything else crammed beneath it, then lyrics and queue in a fixed
    // 220-point strip. That put the artwork's size in charge of the layout, left
    // the lyrics with a strip too short to read, and moved the transport
    // depending on what was on screen. Pinned to the foot instead, the deck is
    // in the same place on every screen, and all that is left above it is the
    // stage.
    //
    // There are three arrangements, and they are one set of slots arranged
    // differently: the portrait player, the compact two-column player (a short
    // landscape window), and the wide two-column player (the sleeve and the deck
    // beside an open pane — a landscape window, or a regular-width tablet held
    // upright, which is N1).
    //
    // Everything below this comment is shared by both platforms. Only the two
    // bodies and the two toolbars are platform-specific, and they are the
    // arrangement — which is the only thing that should differ.
    #if os(iOS)
    var iOSBody: some View {
        // The arrangement is the only thing that differs between the
        // shapes, so the arrangement is the only thing decided here. Every
        // slot below — the sleeve, the panes, the deck — is built once and
        // used by all of them, which is upstream's arrangement and the
        // reason rotating mid-song carries the open pane, the scrub and the
        // translation mode across instead of resetting them.
        GeometryReader { geo in
            let columns = showsTwoColumns(size: geo.size)
            let compactPortrait = !isIPad && !columns
            let fullBleed = compactPortrait && PlayerLayout.usesFullBleedArtwork(
                width: geo.size.width, preferenceEnabled: fullBleedOn
            )
            let blurred = usesBlurredArtworkBackdrop(width: geo.size.width, height: geo.size.height)
            let topInset = geo.safeAreaInsets.top + (usesFullscreenCover ? PlayerLayout.dismissalTopSpacing : 0)
            Group {
                if compactPortrait {
                    compactPortraitPlayer(width: geo.size.width, fullBleed: fullBleed, topInset: topInset)
                } else {
                    ZStack {
                        if columns {
                            twoColumnPlayer(size: geo.size)
                                .transition(.opacity)
                        } else {
                            portraitPlayer
                                .transition(.opacity)
                        }
                    }
                    .animation(Motion.playerPane(reduceMotion), value: pane)
                }
            }
            .modifier(PlayerDragDismissal(enabled: usesFullscreenCover, dismiss: { dismiss() }))
            .frame(width: geo.size.width, height: geo.size.height)
            .background {
                // This layer neither picks up the grabber's padding nor moves
                // with an interactive pull. Only decoration enters the safe area.
                playerBackdrop(width: geo.size.width, continuation: fullBleed,
                               compact: compactPortrait, blurred: blurred)
                    .ignoresSafeArea(.container)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbarTitleDisplayMode(.inline)
    }

    private func playerBackdrop(width: CGFloat, continuation: Bool, compact: Bool, blurred: Bool) -> some View {
        let fill = Color(red: 0.09, green: 0.09, blue: 0.10)
        return Group {
            if lyricBackdrop == .solid {
                LyricBackdrop.solidColor
            } else {
                ZStack {
                    MeshBackdrop(seed: controller.current?.id.hashValue ?? 0, artwork: controller.current?.artworkData,
                                 initialBase: fill)
                    if playerBackground == "artwork" && !reduceTransparency {
                        FullArtworkBlurBackdrop(entry: controller.current)
                    }
                    if continuation {
                        ArtworkContinuation(entry: controller.current, seam: width)
                            .opacity(pane == .main && !videoShowing ? 1 : 0)
                            .animation(Motion.playerPane(reduceMotion), value: blurred)
                    }
                    if lyricBackdrop == .artwork && (compact || blurred) {
                        FullArtworkBlurBackdrop(entry: controller.current)
                            .opacity(blurred ? 1 : 0)
                            .animation(Motion.playerPane(reduceMotion), value: blurred)
                    }
                }
                .background(fill)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
    #endif

    /// The shape test lives in [PlayerLayout] with the rest of the window rules,
    /// so the thresholds have one definition and can be checked without a window.

    /// Whether the player is arranged as two columns: always in a landscape
    /// window, and in a regular-width window while the lyrics or the queue are
    /// open, where the pane sits beside the sleeve rather than over its stage
    /// (`PlayerLayout.putsPaneBesideStage`, N1).
    ///
    /// The main pane is deliberately not two columns on a tablet held upright:
    /// with neither pane open there is nothing to put in the second column, and
    /// an empty one is dead space beside a sleeve that could have used it. That
    /// leaves the portrait player's main pane — the large sleeve and the pinned
    /// deck — exactly as it is.
    private func showsTwoColumns(size: CGSize) -> Bool {
        if PlayerLayout.takesLandscapeShape(width: size.width, height: size.height) {
            return true
        }
        return pane != .main && PlayerLayout.putsPaneBesideStage(
            width: size.width,
            regularWidth: isIPad
        )
    }

    var portraitPlayer: some View {
        VStack(spacing: 0) {
            stage
            deck
        }
    }

    #if os(iOS)
    private func compactPortraitPlayer(width: CGFloat, fullBleed: Bool, topInset: CGFloat) -> some View {
        let showsLyrics = pane == .lyrics
        let showsDeck = !showsLyrics || lyricsControlsOpen
        return ZStack(alignment: .top) {
            if showsLyrics {
                panel(lyricsChrome: EdgeInsets(top: max(lyricsHeaderHeight, PlayerLayout.sleeveCollapsedSide + 22), leading: 0, bottom: lyricsDeckHeight, trailing: 0))
                    .transition(.opacity)
            }

            // The deck has one identity on this screen. The lyrics are laid
            // out behind it and retain their viewport when it fades.
            VStack(spacing: 0) {
                ZStack {
                    compactCoverSlot(fullBleed: fullBleed)
                        .allowsHitTesting(pane == .main)
                        .accessibilityHidden(pane != .main)
                    if pane == .queue {
                        stage.transition(.opacity)
                    }
                }
                deck
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { lyricsDeckHeight = $0 }
                    .modifier(LyricPlaybackChrome(visible: showsDeck, reduceMotion: reduceMotion))
            }

            // Both geometry slots are measured before a transition starts.
            // The thumbnail button owns the hit area the artwork moves into.
            lyricsHeader(usesSharedArtwork: true)
                .opacity(showsLyrics ? 1 : 0)
                .allowsHitTesting(showsLyrics)
                .accessibilityHidden(!showsLyrics)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { lyricsHeaderHeight = $0 }
        }
        .overlay(alignment: .bottomTrailing) {
            if showsLyrics {
                lyricsToolsButton
                    .padding(.trailing, 20)
                    .padding(.bottom, lyricsDeckHeight + 8)
                    .modifier(LyricPlaybackChrome(visible: lyricsControlsOpen, reduceMotion: reduceMotion))
            }
        }
        .overlayPreferenceValue(PlayerArtworkFrames.self) { frames in
            GeometryReader { geometry in
                let target: PlayerArtworkSlot = showsLyrics ? .lyrics : .cover
                let frame = frames[target].map { geometry[$0] } ?? .zero
                compactMovingArtwork(frame: frame, sourceSide: width, fullBleed: fullBleed && !showsLyrics,
                                     topInset: topInset)
                    .opacity(pane == .queue || frame.isEmpty ? 0 : 1)
                    .animation(reduceMotion ? nil : .smooth(duration: 0.34), value: target)
            }
        }
        .animation(Motion.playerPane(reduceMotion), value: pane)
    }

    private func compactCoverSlot(fullBleed: Bool) -> some View {
        GeometryReader { geometry in
            let art = PlayerLayout.compactPortraitArtworkFrame(stage: geometry.size, fullBleed: fullBleed)
            Color.clear
                .frame(width: art.width, height: art.height)
                .anchorPreference(key: PlayerArtworkFrames.self, value: .bounds) { [.cover: $0] }
                .contentShape(Rectangle())
                .position(x: art.midX, y: art.midY)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 30).onEnded { value in
                let drag = value.translation
                guard pane == .main, drag.height < -60, abs(drag.height) > abs(drag.width) else { return }
                Haptics.play(.expand)
                pane = .queue
            }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(controller.current?.title ?? String(localized: "Nothing playing")))
        .accessibilityHint("Swipe up for Up Next")
    }

    private func compactMovingArtwork(frame: CGRect, sourceSide: CGFloat, fullBleed: Bool, topInset: CGFloat) -> some View {
        let main = pane == .main
        let artwork = PlayerLayout.extendedArtworkFrame(frame, topInset: fullBleed ? topInset : 0)
        let extraTop = frame.minY - artwork.minY
        // The player swaps art and video inside the same measured frame.
        // Only the buttons are inset from the status bar.
        return VideoSurface(
            cornerRadius: fullBleed ? 0 : 12,
            fillSlot: false,
            announcesLoading: true,
            presentation: fullBleed ? .fill : .card,
            presented: main && !frame.isEmpty,
            fadesToBackdrop: fullBleed,
            controlsTopInset: extraTop
        ) {
            MovingPlayerArtwork(
                entry: controller.current,
                canvasURL: controller.canvasURL,
                fallbackURL: controller.canvasFallbackURL,
                isPlaying: controller.isPlaying,
                canvasActive: pane != .queue && !(main && videoShowing),
                fullBleed: fullBleed,
                sourceSide: sourceSide
            )
        }
        .frame(width: artwork.width, height: artwork.height)
        .overlay(alignment: .top) {
            LinearGradient(colors: [.black.opacity(0.40), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: extraTop)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .overlay(alignment: .top) {
            if main, fullBleed, !videoShowing, let caption = playbackOriginCaption {
                Text(caption)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.68), in: Capsule())
                    .padding(.top, extraTop + 12)
                    .padding(.horizontal, 16)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .position(x: artwork.midX, y: artwork.midY)
    }
    #endif

    /// The two-column player: the sleeve and the deck on the left, the open pane
    /// on the right.
    ///
    /// A short landscape window takes the compact variant, where the pane's
    /// contents share the right column with the credits and the transport.
    /// Everything else — a landscape iPad or Mac window, and a regular-width iPad
    /// held upright with the lyrics or Up Next open — takes the wide variant:
    /// Apple Music's two-column player, transport always on the left and the pane
    /// on the right.
    func twoColumnPlayer(size: CGSize) -> some View {
        let compact = PlayerLayout.isCompactLandscape(width: size.width, height: size.height)
        let gutter = PlayerLayout.gutter(compact: compact)
        return Group {
            if compact {
                compactLandscapePlayer(size: size, gutter: gutter)
            } else {
                wideTwoColumnPlayer(size: size, gutter: gutter)
            }
        }
    }

    private func compactLandscapePlayer(size: CGSize, gutter: CGFloat) -> some View {
        HStack(spacing: 0) {
            VStack(spacing: 12) {
                GeometryReader { geo in
                    artworkStage(
                        side: max(80, min(geo.size.width, geo.size.height)),
                        collapsed: false
                    )
                }
                playerActionRow
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, gutter)

            Group {
                switch pane {
                case .main:
                    VStack(spacing: 14) {
                        creditsRow
                        currentLyricStrip
                        positionControls
                        playerTransport
                    }
                    .transition(.opacity)
                case .lyrics, .queue:
                    panel(showsQueueCurrentTrackHeader: true)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity)
            .animation(Motion.playerPane(reduceMotion), value: pane)
        }
        .frame(maxWidth: PlayerLayout.landscapeMaxWidth)
        .frame(maxWidth: .infinity)
    }

    private func wideTwoColumnPlayer(size: CGSize, gutter: CGFloat) -> some View {
#if os(macOS)
        let maximumWidth = PlayerLayout.macLandscapeMaxWidth
        let artworkMaximum: CGFloat = 460
        let artworkHeightFraction: CGFloat = 0.46
        let leftColumnMaximum: CGFloat = 480
#else
        let maximumWidth = PlayerLayout.ipadLandscapeMaxWidth
        let artworkMaximum: CGFloat = 560
        let artworkHeightFraction: CGFloat = 0.58
        let leftColumnMaximum: CGFloat = 600
#endif
        return HStack(spacing: 36) {
            // Left column: Large Album Artwork + Full Transport Deck
            VStack(spacing: 16) {
                Spacer(minLength: 0)

                GeometryReader { geo in
                    let side = min(geo.size.width, geo.size.height)
                    artworkStage(side: max(180, side), collapsed: false)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
                .frame(maxHeight: min(size.height * artworkHeightFraction, artworkMaximum))

                VStack(spacing: 12) {
                    creditsRow

                    // The line being sung, as the phone shows it, while the
                    // lyrics column is closed. With the column open it would
                    // print the same line twice, side by side.
                    if pane != .lyrics {
                        currentLyricStrip
                            .padding(.horizontal, 12)
                    }

                    positionControls
                        .padding(.horizontal, 12)

                    playerTransport

                    #if os(iOS)
                    if !controller.hideVolumeBar {
                        deckVolumeRow
                            .padding(.horizontal, 12)
                    }
                    #endif
                    // The pane-reactive pill lives on every platform: queue
                    // modes in the queue pane, output/party elsewhere. It used
                    // to sit inside the iOS gate below, so macOS never showed
                    // it at all.
                    actionRowPill
                    #if os(iOS)
                    Text(outputCaption)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                        .accessibilityLabel(outputCaption)
                    #endif
                }
                .frame(maxWidth: leftColumnMaximum - 40)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: leftColumnMaximum)
            // No leading inset when the player stands alone: it centers in
            // the full width rather than sitting gutter-shifted.
            .padding(.leading, pane == .main ? 0 : gutter)

            // Right column: Lyrics or Queue — and nothing in the main pane.
            // With neither panel selected the player takes the full width,
            // centered; an empty panel column would just leave dead space.
            if pane != .main {
                Group {
                    if pane == .queue {
                        UpNextPane(
                            showsCurrentTrackHeader: false,
                            onOpenLyrics: { pane = .lyrics }
                        )
                            .transition(.opacity)
                    } else {
                        desktopLyricsPane
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, 72)
                .padding(.trailing, gutter)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: maximumWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            if pane == .lyrics {
                lyricsToolsButton
                    .padding(.trailing, gutter)
                    .padding(.top, 18)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            landscapePaneSwitcher
                .padding(.trailing, gutter)
                .padding(.bottom, 12)
        }
        .animation(Motion.playerPane(reduceMotion), value: pane)
    }

    private var landscapePaneSwitcher: some View {
        // Two separate buttons with air between them, like Music: lyrics and
        // queue are mutually exclusive in function but not one joined
        // toggle — no shared capsule, no cramped spacing. Each one toggles:
        // tapping the highlighted pane returns to the main player, so the
        // switcher can always reach the neither-selected state.
        HStack(spacing: 18) {
            actionGlyph(.bchLyrics, selected: pane == .lyrics, label: "Lyrics") {
                Haptics.play(.expand)
                pane = pane == .lyrics ? .main : .lyrics
            }
            actionGlyph(.bchQueue, selected: pane == .queue, label: "Up Next") {
                Haptics.play(.expand)
                pane = pane == .queue ? .main : .queue
            }
        }
    }

    var lyricsToolsButton: some View {
        Menu {
            Button("Change Lyrics Source", systemImage: "text.magnifyingglass") {
                showLyricsSources = true
            }
            Button("Adjust Lyrics Timing", systemImage: "slider.horizontal.2.square") {
                showLyricsOffset = true
            }
        } label: {
            Image(systemName: "wand.and.stars")
                .scaledFont(size: 16, weight: .semibold)
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 42, height: 42)
                .chromeGlass(in: Circle())
                .contentShape(Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("Lyrics options")
        .accessibilityLabel("Lyrics options")
    }
}


private struct LyricPlaybackChrome: ViewModifier {
    let visible: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .allowsHitTesting(visible)
            .accessibilityHidden(!visible)
            .animation(LyricStyle.controlsFade(reduceMotion), value: visible)
    }
}
