#if os(iOS)
import SwiftUI

extension NowPlayingView {
    // NowPlayingScreen.kt pins one deck below the artwork. The scrubbing,
    // volume and action controls are the existing Musicsk components.
    var audenDeck: some View {
        VStack(spacing: 0) {
            if pane == .main { creditsRow.padding(.bottom, 6) }
            if pane != .lyrics { currentLyricStrip.padding(.bottom, 6) }
            positionControls(showsStatus: pane == .main)
                .padding(.horizontal, 30)
                .padding(.bottom, 6)
            playerTransport.padding(.bottom, controller.hideVolumeBar ? 8 : 16)
            if !controller.hideVolumeBar {
                deckVolumeRow
                    .padding(.horizontal, 30)
                    .padding(.bottom, 12)
            }
            playerActionRow
        }
        .padding(.vertical, 6)
        .frame(maxWidth: 620)
        .frame(maxWidth: .infinity)
        .background {
            LinearGradient(colors: [.clear, .black.opacity(0.30), .black.opacity(0.55)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        }
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
                playerActionRow
            }
            .frame(maxWidth: .infinity)
            Group {
                if pane == .main {
                    ScrollView {
                        VStack(spacing: short ? 8 : 16) {
                            creditsRow
                            currentLyricStrip
                            positionControls(showsStatus: true).padding(.horizontal, 12)
                            playerTransport
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
