#if os(iOS)
import SwiftUI

struct AudenShell: View {
    @Binding var selection: Int
    let feed: FeedLoader

    @Environment(AppModel.self) private var appModel
    @Environment(PlaybackController.self) private var controller
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var visited: Set<AppModel.Tab> = []
    @State private var rememberedTab: AppModel.Tab = .home
    @State private var dockState = AudenDockState()

    private static let destinations: [AppModel.Tab] = [.home, .explore, .library, .search]

    private var current: AppModel.Tab {
        let tab = AppModel.Tab(rawValue: selection) ?? .home
        return Self.destinations.contains(tab) ? tab : .library
    }

    var body: some View {
        ZStack {
            AudenDesign.canvas(scheme).ignoresSafeArea()
            ForEach(Self.destinations, id: \.self) { tab in
                if current == tab || visited.contains(tab) {
                    page(tab)
                        .opacity(current == tab ? 1 : 0)
                        .allowsHitTesting(current == tab)
                        .accessibilityHidden(current != tab)
                        .environment(\.audenTabActive, current == tab)
                        .environment(\.audenDockState, current == tab ? dockState : nil)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { dock }
        #if targetEnvironment(simulator)
        .onAppear {
            if UserDefaults.standard.bool(forKey: "musicsk_capture_render_edition") {
                PlaybackDebugLog.shared.record("auden fixture mounted Auden")
            }
        }
        #endif
        .onChange(of: current, initial: true) { _, value in
            visited.insert(value)
            if value != .search { rememberedTab = value }
            dockState.expand(reduceMotion: reduceMotion)
        }
    }

    @ViewBuilder
    private func page(_ tab: AppModel.Tab) -> some View {
        switch tab {
        case .home: HomeView(feed: feed)
        case .explore: ExploreView()
        case .search: SearchView()
        default: LibraryView()
        }
    }

    private var dock: some View {
        let compact = dockState.folded && !textSize.isAccessibilitySize
        return ZStack(alignment: .bottom) {
            HStack(spacing: compact ? AudenPlayerMetrics.inlineGap : 8) {
                if compact {
                    tabButton(rememberedTab, compact: true) { dockState.expand(reduceMotion: reduceMotion) }
                        .frame(width: AudenPlayerMetrics.inlineNavSide)
                        .modifier(AudenPanel())
                    Spacer(minLength: 0)
                } else {
                    HStack(spacing: 2) {
                        tabButton(.home)
                        tabButton(.explore)
                        tabButton(.library)
                    }
                    .padding(.horizontal, 4)
                    .modifier(AudenPanel())
                }
                tabButton(.search, compact: compact)
                    .frame(width: compact ? AudenPlayerMetrics.inlineNavSide : 70)
                    .modifier(AudenPanel())
            }
            if controller.current != nil {
                // Retain the same drag state and zoom source during the fold.
                AudenMiniPlayer(compact: compact)
                    .padding(.horizontal, compact ? AudenPlayerMetrics.inlineNavSide + AudenPlayerMetrics.inlineGap : 0)
                    .animation(reduceMotion ? nil : AudenDesign.dockMotion(
                        stiffness: compact ? 600 : 300, delay: compact ? 0 : 0.06), value: compact)
                    .padding(.bottom, compact ? 0 : AudenPlayerMetrics.expandedNavHeight + AudenPlayerMetrics.miniGap)
                    .animation(reduceMotion ? nil : AudenDesign.dockMotion(
                        stiffness: compact ? 340 : 520, delay: compact ? 0.08 : 0), value: compact)
                    .transition(.opacity)
            }
        }
        .modifier(AudenGlassGroup())
        .padding(.horizontal, compact ? 28 : AudenDesign.gutter)
        .padding(.bottom, compact ? 7 : 4)
        .frame(maxWidth: 750)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("auden.dock")
    }

    private func tabButton(_ tab: AppModel.Tab, compact: Bool = false, action: (() -> Void)? = nil) -> some View {
        let info = tabLabel(tab)
        let selected = tab == current
        return Button {
            if let action { action(); return }
            if selected, tab == .search { appModel.searchFocusTrigger &+= 1 }
            selection = tab.rawValue
        } label: {
            VStack(spacing: 3) {
                Image(systemName: info.icon).font(.system(size: 19, weight: selected ? .semibold : .regular))
                if !compact { Text(info.label).font(.caption2.weight(selected ? .semibold : .regular)).lineLimit(1) }
            }
            .foregroundStyle(selected ? .primary : .secondary)
            .frame(maxWidth: .infinity, minHeight: compact ? AudenPlayerMetrics.inlineNavSide : AudenPlayerMetrics.expandedNavHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(info.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("auden.tab.\(info.id)")
    }

    private func tabLabel(_ tab: AppModel.Tab) -> (label: LocalizedStringKey, icon: String, id: String) {
        switch tab {
        case .home: ("Home", "house", "home")
        case .explore: ("Explore", "square.grid.2x2", "explore")
        case .search: ("Search", "magnifyingglass", "search")
        default: ("Library", "square.stack", "library")
        }
    }


}

private struct AudenMiniPlayer: View {
    var compact = false

    @Environment(PlaybackController.self) private var controller
    @Environment(AppModel.self) private var appModel
    @Environment(PartyStore.self) private var party
    @Environment(\.nowPlayingZoomNamespace) private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var drag = CGSize.zero

    var body: some View {
        zoomSource
            .offset(y: lift)
            .animation(drag == .zero && !reduceMotion ? .spring(response: 0.32, dampingFraction: 0.87) : nil, value: drag)
            .gesture(DragGesture(minimumDistance: 12, coordinateSpace: .global)
                .updating($drag) { value, state, transaction in
                    transaction.animation = nil
                    state = value.translation
                }
                .onEnded { value in
                    switch PlayerPanAxis(translation: value.translation) {
                    case .vertical:
                        if MiniPlayerMotion.shouldOpen(translation: value.translation, projected: value.predictedEndTranslation) {
                            appModel.nowPlayingPresented = true
                        }
                    case .horizontal:
                        guard !party.state.controlsLocked else { return }
                        if value.translation.width <= -72, controller.canPlayNext { controller.next() }
                        if value.translation.width >= 72, controller.canPlayPrevious { controller.previous() }
                    case nil: break
                    }
                })
            .accessibilityIdentifier("auden.mini")
    }

    private var lift: CGFloat {
        guard !reduceMotion, drag.height < 0, PlayerPanAxis(translation: drag) == .vertical else { return 0 }
        return -MiniPlayerMotion.lift(drag)
    }

    @ViewBuilder
    private var zoomSource: some View {
        if let namespace, !reduceMotion {
            card.matchedTransitionSource(id: NowPlayingZoom.sourceID, in: namespace)
        } else {
            card
        }
    }

    private var card: some View {
        HStack(spacing: 2) {
            Button {
                appModel.nowPlayingPresented = true
            } label: {
                HStack(spacing: compact ? 7 : 10) {
                    ArtworkView(entry: controller.current, side: AudenPlayerMetrics.miniArt, reusesPlayerThumbnail: true)
                        .clipShape(RoundedRectangle(cornerRadius: AudenPlayerMetrics.miniArtRadius))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(controller.current?.title ?? "")
                            .tracking(0.15).scaledFont(size: 13, weight: .semibold).lineLimit(1)
                        if let artist = controller.current?.artist, !artist.isEmpty {
                            Text(artist).tracking(0.35).scaledFont(size: 12, weight: .regular)
                                .foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens Now Playing")
            Button {
                controller.togglePlayPause()
            } label: {
                Group {
                    if controller.isBuffering { ProgressView().controlSize(.small) }
                    else {
                        Image(controller.isPlaying ? .bchTransportPause : .bchTransportPlay)
                            .resizable().scaledToFit().frame(width: 29, height: 29)
                    }
                }.frame(width: 44, height: 44)
            }
            .accessibilityLabel(controller.isPlaying ? "Pause" : "Play")
            .buttonStyle(.plain)
            .disabled(party.state.controlsLocked)
            if !compact {
                Button("Next", systemImage: "forward.end.fill") { controller.next() }
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
                    .buttonStyle(.plain)
                    .disabled(!controller.canPlayNext || party.state.controlsLocked)
            }
        }
        .padding(.horizontal, compact ? 6 : 10)
        .frame(minHeight: AudenDesign.miniHeight)
        .modifier(AudenPanel())
        .contentShape(Rectangle())
        .contextMenu {
            Button("Up Next", systemImage: "list.bullet") {
                appModel.queueRevealRequested = true
                appModel.nowPlayingPresented = true
            }
            Button("Lyrics", systemImage: "quote.bubble") {
                appModel.lyricsRevealRequested = true
                appModel.nowPlayingPresented = true
            }
        }
    }
}
#endif
