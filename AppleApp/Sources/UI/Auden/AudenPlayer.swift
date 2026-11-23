#if os(iOS)
import SwiftUI

extension NowPlayingView {
    // NowPlayingScreen.kt pins one deck below the artwork.
    var audenDeck: some View {
        VStack(spacing: 0) {
            if pane == .main { audenCredits.padding(.bottom, 6) }
            if pane != .lyrics { currentLyricStrip.padding(.bottom, 6) }
            audenScrubber
                .padding(.horizontal, 30)
                .padding(.bottom, 6)
            audenTransport(compact: false).padding(.bottom, controller.hideVolumeBar ? 22 : 16)
            if !controller.hideVolumeBar {
                deckVolumeRow
                    .frame(height: AudenPlayerMetrics.volumeRowHeight)
                    .padding(.horizontal, 30)
                    .padding(.bottom, 12)
            }
            audenActionRow
        }
        .padding(.vertical, 6)
        .frame(maxWidth: AudenPlayerMetrics.maxDeckWidth + 2 * AudenPlayerMetrics.gutter)
        .frame(maxWidth: .infinity)
        .background {
            LinearGradient(colors: [.clear, .black.opacity(0.30), .black.opacity(0.55)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        }
    }

    private var audenCredits: some View {
        let current = controller.current
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if current?.isExplicit == true { ExplicitMark(color: .white.opacity(0.55)) }
                    Marquee(enabled: pane == .main, onOverflowChange: { titleCrawls = $0 }) {
                        Text(current?.title ?? String(localized: "Nothing playing"))
                            .tracking(-0.2)
                            .scaledFont(size: 20, weight: .semibold)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if let album = current?.albumId {
                        appModel.openPage(browseId: album, title: current?.albumName ?? "Album")
                    }
                }
                .accessibilityAddTraits(current?.albumId == nil ? [] : .isButton)
                ArtistCreditText(credit: current?.artist ?? "", artistId: current?.artistId,
                                 font: .system(size: 20, weight: .medium),
                                 color: .white.opacity(0.55), marquee: (pane == .main, titleCrawls ? 3 : 0))
            }
            .id(current?.id)
            .transition(.opacity)
            .frame(maxWidth: .infinity, alignment: .leading)
            if auth.signedIn, current?.videoId != nil {
                GlassCircleButton(system: controller.isLiked ? "star.fill" : "star",
                                  selected: controller.isLiked, label: controller.isLiked ? "Remove from Liked" : "Like") {
                    Haptics.play(.tap)
                    controller.toggleLike()
                }
            }
            moreMenu
        }
        .foregroundStyle(.white)
        .padding(.horizontal, AudenPlayerMetrics.gutter)
        .animation(reduceMotion ? nil : .timingCurve(0.4, 0, 0.2, 1, duration: 0.2), value: current?.id)
    }

    private var audenActionRow: some View {
        VStack(spacing: 10) {
            GeometryReader { geo in
                ZStack {
                    if pane == .queue {
                        queueModesPill
                    } else {
                        audenOutputButton
                    }
                    HStack {
                        audenPaneButton(.lyrics, label: "Lyrics", image: .bchLyrics)
                        Spacer(minLength: 0)
                        audenPaneButton(.queue, label: "Up Next", image: .bchQueue)
                    }
                    .padding(.horizontal, pane == .queue
                             ? max(0, (geo.size.width - 300) / 4)
                             : AudenPlayerMetrics.actionInset(width: geo.size.width))
                }
            }
            .frame(height: AudenPlayerMetrics.centerTouch)

            Text(outputCaption)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
        }
        .animation(reduceMotion ? nil : .timingCurve(0.4, 0, 0.2, 1, duration: 0.22), value: pane)
    }

    private var audenOutputButton: some View {
        Button {
            Haptics.play(.tap)
            showOutputDevice = true
        } label: {
            Image(systemName: "headphones")
                .scaledFont(size: 23, weight: .regular)
                .frame(width: AudenPlayerMetrics.centerTouch, height: AudenPlayerMetrics.centerTouch)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.88))
        .modifier(AudenPanel())
        .accessibilityLabel("Audio output")
        .accessibilityHint("More actions are available in the context menu")
        .contextMenu {
            Button("Music Videos", systemImage: showMusicVideos ? "checkmark" : "play.rectangle") {
                showMusicVideos.toggle()
            }
            Button("Mix with Other Apps", systemImage: controller.mixWithOtherAudio ? "checkmark" : "waveform") {
                controller.setMixWithOtherAudio(!controller.mixWithOtherAudio)
            }
            Button(party.inParty ? "People listening" : "Listen Together", systemImage: "person.fill") {
                if party.inParty { appModel.partyMembersPresented = true }
                else { appModel.listenTogetherPresented = true }
            }
        }
    }

    private func audenPaneButton(_ target: PlayerPane, label: LocalizedStringKey, image: ImageResource) -> some View {
        let selected = pane == target
        return Button {
            Haptics.play(.expand)
            pane = selected ? .main : target
        } label: {
            Image(image).resizable().scaledToFit()
                .frame(width: AudenPlayerMetrics.paneIcon, height: AudenPlayerMetrics.paneIcon)
                .foregroundStyle(selected ? Color.black : Color.white.opacity(0.80))
                .frame(width: AudenPlayerMetrics.paneTile, height: AudenPlayerMetrics.paneTile)
                .background(.white.opacity(selected ? 0.62 : 0),
                            in: RoundedRectangle(cornerRadius: AudenPlayerMetrics.paneTileRadius))
                .frame(width: AudenPlayerMetrics.centerTouch, height: AudenPlayerMetrics.centerTouch)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    func audenColumnPlayer(size: CGSize) -> some View {
        let short = PlayerLayout.isCompactLandscape(width: size.width, height: size.height)
        return HStack(spacing: short ? 16 : 30) {
            VStack(spacing: 10) {
                GeometryReader { geometry in
                    let side = min(560, max(0, geometry.size.width), max(0, geometry.size.height - 32))
                    artworkStage(side: side, collapsed: false)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
                audenActionRow
            }
            .frame(maxWidth: .infinity)
            Group {
                if pane == .main {
                    ScrollView {
                        VStack(spacing: short ? 8 : 16) {
                            audenCredits
                            currentLyricStrip
                            audenScrubber.padding(.horizontal, 12)
                            audenTransport(compact: short)
                            if !controller.hideVolumeBar { deckVolumeRow.padding(.horizontal, 12) }
                        }
                        .padding(.vertical, 12)
                    }
                    .defaultScrollAnchor(.center, for: .alignment)
                } else {
                    panel(showsQueueCurrentTrackHeader: true)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, short ? 14 : 30)
        .frame(maxWidth: PlayerLayout.landscapeMaxWidth)
        .frame(maxWidth: .infinity)
        .animation(Motion.playerPane(reduceMotion), value: pane)
    }
}
#endif
