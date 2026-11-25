import SwiftUI
import BitChordShared
import ImageIO

/// Detail page for an album / artist / playlist browseId.
///
/// Album and artist pages pair the provider's artwork with a header that
/// scrolls into the collection. List content keeps its own readable width.
struct DetailView: View {
    let browseId: String
    let initialTitle: String
    @Environment(PlaybackController.self) private var controller
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif
    @State private var page: DetailPageModel?
    @State private var error: String?
    @State private var loading = true
    @State private var headerArt: Data?
    @State private var headerTint: (input: PaletteInput, value: ArtworkPalette.PageTint, aspect: CGFloat?)?
    @State private var filter = ""
    /// Owned-playlist reordering. A real mode with a control, not a forced
    /// `.active` — see `NowPlayingView.UpNextPane`.
    ///
    /// iOS-only, like `EditMode` itself. On macOS the list is reordered by
    /// click-to-move instead, which is the platform's own idiom.
    #if os(iOS)
    @State private var editMode: EditMode = .inactive
    #endif
    @State private var saved = false
    @State private var saving = false
    @State private var continuation: String?
    /// Whether a continuation fetch is in flight; the token stays put until it
    /// succeeds, so this is what keeps duplicate requests out.
    @State private var loadingMore = false
    @State private var loadMoreTask: Task<Void, Never>?
    @State private var pageRequestID = UUID()
    @State private var suggested: [DetailPageModel.SongPayload] = []
    @Environment(AuthController.self) private var auth
    @Environment(AppModel.self) private var appModel
    @Environment(ToastCenter.self) private var toast
    @State private var subscriptionOverride: Bool?
    @State private var subscribing = false
    @State private var renameTitle = ""
    @State private var renamePresented = false
    @State private var privacy = "PRIVATE"
    @State private var privacyPresented = false
    @State private var canvasURL: URL?
    @State private var canvasFallbackURL: URL?
    @State private var albumArtVisible = false
    @State private var measuredHeaderHeight: CGFloat = 0
    @State private var pinned = false
    @State private var scrollChrome = DetailHeaderLayout.ScrollChrome(offset: 0, headerHeight: 0)
    /// Narrows the track list in place, like upstream's search circle in the
    /// release header. Off until tapped, so a long list reads as a list first.
    @State private var searching = false
    /// Library state of the promoted latest release, read lazily (upstream's
    /// `releaseLibrary`) so its save circle reflects the truth without loading
    /// the whole release page up front.
    @State private var latestReleaseLibraryId: String?
    @State private var latestReleaseSaved = false
    @State private var savingLatestRelease = false
    /// The artist shelf whose "Show all" grid is pushed, if any. A stored value
    /// rather than a NavigationLink in the header, because the header's button
    /// is shared with Library rows that don't push (upstream's
    /// `onActiveShelfChange`). The pushed grid keeps its own scroll state, and
    /// popping back restores this page's shelf run underneath it.
    @State private var showAllGrid: ShowAllGrid?
    @State private var artistSignature: ArtistSignature?

    /// Whether the window is wide enough for the roomier header controls.
    ///
    /// A size class, not an idiom: an iPad in a narrow split view is a compact
    /// window, and a Mac window can be narrowed to the same width.
    private var isWide: Bool {
        #if os(macOS)
        true
        #else
        sizeClass == .regular
        #endif
    }

    var body: some View {
        Group {
            if loading {
                // The page as it is about to be, from the id alone — the same
                // kind fallback `kind(of:)` uses when the payload is absent —
                // so opening a detail moves nothing but the artwork and words
                // arriving (upstream `detailSkeleton(isArtist:)`).
                DetailSkeleton(
                    isArtist: preLoadKind == .artist,
                    immersive: usesImmersiveHeader(preLoadKind),
                    wide: isWide
                )
            } else if let error {
                EmptyStateView(icon: Image(.bchMusicNote), title: "Couldn't load", subtitle: error, buttonTitle: "Retry") {
                    Task { await load() }
                }
            } else if let page {
                loadedPage(page)
            }
        }
        .refreshable { await load(force: true) }
        .navigationTitle(scrollChrome.showsInlineTitle ? (page?.title.isEmpty == false ? page!.title : initialTitle) : "")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(toolbarBackgroundVisibility, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                detailActionsMenu(page: page)
                TopBarAccountButton()
            }
        }
        #endif
        .alert("Rename Playlist", isPresented: $renamePresented) {
            TextField("Title", text: $renameTitle)
            Button("Save") {
                Task {
                    _ = await LibraryActions.renamePlaylist(playlistId: browseId, title: renameTitle)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Playlist privacy", isPresented: $privacyPresented, titleVisibility: .visible) {
            Button("Private") { Task { await setPrivacy("PRIVATE") } }
            Button("Unlisted") { Task { await setPrivacy("UNLISTED") } }
            Button("Public") { Task { await setPrivacy("PUBLIC") } }
            Button("Cancel", role: .cancel) {}
        }
        .task(id: auth.sessionEpoch) {
            page = nil; continuation = nil; headerArt = nil
            canvasURL = nil; canvasFallbackURL = nil; albumArtVisible = false
            measuredHeaderHeight = 0
            scrollChrome = DetailHeaderLayout.ScrollChrome(offset: 0, headerHeight: 0)
            saving = false; subscribing = false; subscriptionOverride = nil
            pinned = PlaylistPinning.pinnedIds().contains(browseId)
            await load()
        }
        .onAppear { mirrorPlaybackContext() }
        .onChange(of: controller.playbackContextRevision) { _, _ in mirrorPlaybackContext() }
        .task(id: signatureLookupKey) {
            await loadArtistSignature()
        }
        // The shelf's "Show all" grid is a normal push, so the grid keeps its
        // own scroll state and popping back restores this page's carousels
        // underneath it (upstream's `parentShelf` restore).
        .navigationDestination(item: $showAllGrid) { grid in
            LibraryGridView(title: grid.title, items: grid.items)
        }
    }

    #if os(iOS)
    private var toolbarBackgroundVisibility: Visibility {
        let immersive = page.map { usesImmersiveHeader(kind(of: $0)) } ?? usesImmersiveHeader(preLoadKind)
        guard immersive, error == nil else { return .automatic }
        return scrollChrome.showsToolbarBackground || reduceTransparency || colorSchemeContrast == .increased
            ? .visible : .hidden
    }
    #endif

    /// The kind before the page loads, from the id alone.
    private var preLoadKind: Kind {
        if browseId.hasPrefix("UC") { return .artist }
        if browseId.hasPrefix("MPREb") || browseId.hasPrefix("OLAK") { return .album }
        if browseId.hasPrefix("VL") || browseId.hasPrefix("PL") { return .playlist }
        return .other
    }

    private var signatureLookupKey: String {
        let enabled = PlatformSettings.shared.getBoolean(key: "artist_signatures_enabled", default: true)
        let endpoint = PlatformSettings.shared.getString(key: "artist_signatures_wikimedia_url", default: "")
        return "\(browseId)|\(page?.title ?? initialTitle)|\(enabled)|\(endpoint)"
    }

    private func loadArtistSignature() async {
        artistSignature = nil
        guard PlatformSettings.shared.getBoolean(key: "artist_signatures_enabled", default: true),
              let page, kind(of: page) == .artist else { return }
        let endpoint = PlatformSettings.shared.getString(key: "artist_signatures_wikimedia_url", default: "")
        let title = page.title.isEmpty ? initialTitle : page.title
        for delaySeconds in [0, 5, 15, 30] {
            if delaySeconds > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delaySeconds) * 1_000_000_000)
            }
            guard !Task.isCancelled else { return }
            switch await ArtistSignatureRepository.shared.signature(for: title, endpointOverride: endpoint) {
            case .found(let found):
                artistSignature = found
                return
            case .notFound:
                return
            case .failed:
                continue
            }
        }
    }

    private struct PaletteInput: Equatable, Sendable {
        var artwork: Data?
        var seed: Int
        var dark: Bool
    }

    private func loadedPage(_ page: DetailPageModel) -> some View {
        let input = PaletteInput(artwork: headerArt, seed: page.title.hashValue, dark: colorScheme == .dark)
        let fallback = ArtworkPalette.pageTint(from: nil, seed: input.seed, dark: input.dark)
        let palette = headerTint?.input == input ? headerTint : nil
        let tint = palette?.value ?? fallback
        let pageKind = kind(of: page)
        let isArtist = pageKind == .artist
        let immersive = usesImmersiveHeader(pageKind)
        let surface = readableHeaderSurface(tint)

        return GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let leading = immersive ? geo.safeAreaInsets.leading : 0
            let trailing = immersive ? geo.safeAreaInsets.trailing : 0
            let artWidth = DetailHeaderLayout.albumWidth(in: width + leading + trailing)
            ScrollView {
                VStack(spacing: 0) {
                    Group {
                        if immersive {
                            immersiveHeader(page, tint: tint, surface: surface, hero: isArtist ? .artist : .album,
                                            width: artWidth, height: height, sourceAspect: palette?.aspect,
                                            leading: leading, trailing: trailing)
                        } else if isArtist {
                            artistHeader(page, tint: tint, width: width, height: height)
                        } else {
                            releaseHeader(page, tint: tint, width: width)
                        }
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measuredHeaderHeight = $0 }

                    VStack(alignment: .leading, spacing: 0) {
                        if isArtist, let shelf = latestReleaseShelf(page), let card = shelf.items.first {
                            latestReleaseCard(card)
                                .frame(maxWidth: DetailHeaderLayout.maxContentWidth)
                                .padding(.horizontal, 16)
                                .padding(.top, 12)
                                .padding(.bottom, 14)
                                .task(id: card.browseId) {
                                    await loadLatestReleaseLibrary(card)
                                }
                        }

                        if !page.songs.isEmpty {
                            if searching {
                                searchField(tint: tint)
                            }
                            trackList(page, width: width)
                                .padding(.horizontal, 16)

                            if !isArtist {
                                Text(playtimeSummary(page.songs))
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.top, 16)
                                    .padding(.bottom, 8)
                            }
                        } else if page.sections.isEmpty {
                            if pageKind == .playlist, page.playlistOwned == true, auth.signedIn {
                                // An empty playlist of one's own: deleting it is
                                // the likeliest thing to want, so it is a button
                                // here rather than only a row in the menu.
                                EmptyStateView(
                                    icon: Image(.bchMusicNote),
                                    title: "No tracks",
                                    subtitle: "This playlist is empty.",
                                    buttonTitle: "Delete Playlist",
                                    action: { confirmDelete(page) }
                                )
                            } else {
                                EmptyStateView(icon: Image(.bchMusicNote), title: "No tracks", subtitle: "This page has no playable tracks.", buttonTitle: nil, action: nil)
                            }
                        }

                        if !suggested.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Suggested")
                                    .font(.headline)
                                    .padding(.horizontal, 28)
                                    .padding(.top, 20)
                                ForEach(suggested, id: \.videoId) { song in
                                    SongRow(
                                        entry: toEntry(song, fallbackArt: fallbackArt(page)),
                                        play: { controller.playRadio(toEntry(song, fallbackArt: fallbackArt(page))) },
                                        playNext: { controller.playNext(toEntry(song, fallbackArt: fallbackArt(page))) },
                                        addToQueue: { controller.addToQueue(toEntry(song, fallbackArt: fallbackArt(page))) }
                                    )
                                    .padding(.horizontal, 16)
                                }
                            }
                        }

                        if !isArtist {
                            aboutSection(page, isArtist: false)
                        }

                        ForEach(page.sections) { shelf in
                            let cards = carouselItems(shelf, page: page)
                            if !cards.isEmpty {
                                // An artist shelf stops at five cards and offers
                                // the rest as a grid (upstream ARTIST_ROW_MAX_ITEMS);
                                // a release page has no such shelf to cap.
                                let canShowAll = isArtist && cards.count > 5
                                ShelfCarousel(
                                    shelf: shelf,
                                    items: canShowAll ? Array(cards.prefix(5)) : cards,
                                    onShowAll: canShowAll
                                        ? { showAllGrid = ShowAllGrid(title: shelf.title, items: cards) }
                                        : nil,
                                    inset: 28
                                )
                                .padding(.horizontal, 28)
                                .padding(.top, 28)
                            }
                        }

                        // On an artist page About closes the page, after the
                        // shelves, with the counts under the text (upstream).
                        if isArtist {
                            aboutSection(page, isArtist: true)
                        }
                    }
                    .frame(maxWidth: DetailHeaderLayout.maxContentWidth)
                    .frame(width: width)
                    .padding(.leading, leading)
                    .padding(.trailing, trailing)
                    .background(alignment: .top) {
                        if immersive {
                            LinearGradient(colors: [surface, surface.opacity(0)], startPoint: .top, endPoint: .bottom)
                                .frame(height: 130)
                                .allowsHitTesting(false)
                        }
                    }
                }
                .padding(.bottom, 36)
            }
            .onScrollGeometryChange(for: DetailHeaderLayout.ScrollChrome.self) { geo in
                DetailHeaderLayout.ScrollChrome(offset: geo.contentOffset.y + geo.contentInsets.top,
                                                headerHeight: measuredHeaderHeight)
            } action: { _, chrome in
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                    scrollChrome = chrome
                }
            }
            #if os(iOS)
            .ignoresSafeArea(.container, edges: immersive ? [.top, .horizontal] : [])
            #endif
            .background {
                if immersive {
                    Rectangle().fill(.background).ignoresSafeArea()
                } else {
                    pageWash(tint: tint)
                }
            }
        }
        .task(id: page.thumbnailUrl) {
            let art = await loadHeaderArt(page.thumbnailUrl)
            guard !Task.isCancelled else { return }
            headerArt = art
        }
        .task(id: CanvasInput(accountEpoch: auth.sessionEpoch, album: page.title, credit: headerLines(page).credit.ifBlank { page.songs.first?.artist ?? "" })) {
            await loadCanvas(page)
        }
        .task(id: input) {
            guard let artwork = input.artwork else { return }
            let (tint, aspect) = await Task.detached(priority: .utility) {
                (ArtworkPalette.pageTint(from: artwork, seed: input.seed, dark: input.dark),
                 Self.sourceArtworkAspect(artwork))
            }.value
            guard !Task.isCancelled else { return }
            headerTint = (input, tint, aspect)
        }
    }

    private struct CanvasInput: Equatable {
        let accountEpoch: Int
        let album: String
        let credit: String
    }

    nonisolated private static func sourceArtworkAspect(_ data: Data) -> CGFloat? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let values = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = values[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = values[kCGImagePropertyPixelHeight] as? NSNumber,
              width.doubleValue > 0, height.doubleValue > 0 else { return nil }
        let rotated = (5...8).contains((values[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1)
        return CGFloat(rotated ? height.doubleValue / width.doubleValue : width.doubleValue / height.doubleValue)
    }

    @ViewBuilder
    private func detailActionsMenu(page: DetailPageModel?) -> some View {
        if let page {
            Menu {
                if let urlString = page.url, let url = URL(string: urlString) {
                    ShareLink(item: url) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    if kind(of: page) == .artist {
                        Link(destination: url) {
                            Label("Open in YouTube Music", systemImage: "arrow.up.right.square")
                        }
                    }
                }
                if !pinned {
                    Button {
                        if PlaylistPinning.toggle(browseId: browseId) {
                            pinned = true
                        } else {
                            appModel.pinLimitAlert = true
                        }
                    } label: {
                        Label("Pin to Library", systemImage: "pin")
                    }
                } else {
                    Button {
                        if PlaylistPinning.toggle(browseId: browseId) {
                            pinned = false
                        }
                    } label: {
                        Label("Unpin from Library", systemImage: "pin.slash")
                    }
                }
                if kind(of: page) == .playlist, page.playlistOwned == true {
                    Button {
                        renameTitle = page.title
                        renamePresented = true
                    } label: {
                        Label("Rename Playlist", systemImage: "pencil")
                    }
                    Button {
                        privacyPresented = true
                    } label: {
                        Label("Playlist Privacy…", systemImage: "lock")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 34, height: 34)
                    .toolbarChrome(in: Circle())
            }
            .buttonStyle(ProfileCircleButtonStyle())
            .accessibilityLabel("More Options")
        }
    }

    private func artistHeader(
        _ page: DetailPageModel,
        tint: ArtworkPalette.PageTint,
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        let title = page.title.isEmpty ? initialTitle : page.title
        let artHeight = DetailHeaderLayout.artistArtworkHeight(width: width, viewportHeight: height, immersive: false)
        let overlaysTitle = !dynamicTypeSize.isAccessibilitySize && artHeight >= 200

        return VStack(alignment: .leading, spacing: 0) {
            ArtworkView(url: page.thumbnailUrl, data: headerArt, side: max(width, artHeight), fill: true)
                .frame(width: width, height: artHeight)
                .clipped()
                .overlay {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.42),
                            .init(color: .black.opacity(0.34), location: 0.67),
                            .init(color: .black.opacity(0.86), location: 1)
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                    .allowsHitTesting(false)
                }
                .overlay(alignment: .bottom) {
                    if overlaysTitle {
                        artistIdentity(title)
                            .foregroundStyle(.white)
                            .frame(maxWidth: DetailHeaderLayout.maxContentWidth, alignment: .leading)
                            .padding(.horizontal, 22)
                            .padding(.bottom, 18)
                    }
                }

            VStack(alignment: .leading, spacing: 12) {
                if !overlaysTitle { artistIdentity(title) }
                if !page.songs.isEmpty {
                    artistActions(page, tint: tint)
                }
            }
            .frame(maxWidth: DetailHeaderLayout.maxContentWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background {
                LinearGradient(colors: [tint.elevated, tint.elevated.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .allowsHitTesting(false)
            }
        }
    }

    private func artistIdentity(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)
            if let signature = artistSignature, signature.artistName == title {
                AsyncImage(url: signature.imageURL) { image in
                    image.resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                } placeholder: {
                    Color.clear
                }
                .frame(width: 144, height: 36, alignment: .leading)
                .accessibilityLabel("Artist signature for \(title)")
            }
        }
    }

    private func artistActions(_ page: DetailPageModel, tint: ArtworkPalette.PageTint) -> some View {
        let isPlaying = controller.isPlaybackContextPlaying(browseId)
        let subscription = auth.signedIn ? page.subscription : nil
        let subscribed = subscription.map { subscriptionOverride ?? $0.subscribed } ?? false
        return HStack(spacing: 10) {
            ViewThatFits(in: .horizontal) {
                PlayPill(iconOnly: false, isPlaying: isPlaying) { playContext(page) }
                PlayPill(iconOnly: true, isPlaying: isPlaying) { playContext(page) }
            }

            CircleIconButton(icon: Image(.bchShuffle), label: "Shuffle", veiled: true) {
                playContext(page, shuffled: true)
            }

            Spacer(minLength: 4)

            CircleIconButton(
                icon: Image(systemName: subscribed ? "star.fill" : "star"),
                label: subscribed ? "Unsubscribe" : "Subscribe",
                veiled: true,
                active: subscribed,
                activeColor: tint.accent,
                disabled: subscription == nil || subscribing
            ) {
                if let subscription {
                    Task { await toggleSubscription(subscription, artistName: page.title) }
                }
            }
        }
    }

    private func usesImmersiveHeader(_ kind: Kind) -> Bool {
        #if os(iOS)
        kind == .album || kind == .artist
        #else
        false
        #endif
    }

    private var readableSurface: Color {
        #if os(iOS)
        Color(uiColor: .systemBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    private func readableHeaderSurface(_ tint: ArtworkPalette.PageTint) -> Color {
        reduceTransparency || colorSchemeContrast == .increased ? readableSurface : tint.wash
    }

    private func immersiveHeader(
        _ page: DetailPageModel,
        tint: ArtworkPalette.PageTint,
        surface: Color,
        hero: DetailHeaderLayout.Hero,
        width: CGFloat,
        height: CGFloat,
        sourceAspect: CGFloat?,
        leading: CGFloat,
        trailing: CGFloat
    ) -> some View {
        let artHeight = hero == .album
            ? DetailHeaderLayout.albumArtworkHeight(width: width, viewportHeight: height)
            : DetailHeaderLayout.artistArtworkHeight(width: width, viewportHeight: height)
        let field = CGSize(width: width, height: artHeight)
        let title = page.title.isEmpty ? initialTitle : page.title
        let overlap = DetailHeaderLayout.identityOverlap(artHeight: artHeight,
                                                          usesExpandedText: dynamicTypeSize.isAccessibilitySize)

        return VStack(spacing: 0) {
            immersiveArtwork(page, hero: hero, field: field, sourceAspect: sourceAspect, surface: surface)

            VStack(alignment: .leading, spacing: 12) {
                if hero == .artist {
                    artistIdentity(title)
                    if !page.songs.isEmpty { artistActions(page, tint: tint) }
                } else {
                    albumIdentity(page, title: title)
                    if !page.songs.isEmpty {
                        immersiveAlbumActions(page, tint: tint)
                    } else {
                        releaseMoreMenu(page)
                    }
                }
            }
            .frame(maxWidth: DetailHeaderLayout.maxContentWidth, alignment: .leading)
            .padding(.horizontal, DetailHeaderLayout.contentInset)
            .padding(.leading, leading)
            .padding(.trailing, trailing)
            .frame(maxWidth: .infinity)
            .padding(.top, 3 - overlap)
            .padding(.bottom, 18)
        }
        .frame(width: width)
        .foregroundStyle(.primary)
        .background(surface)
    }

    private func immersiveArtwork(
        _ page: DetailPageModel,
        hero: DetailHeaderLayout.Hero,
        field: CGSize,
        sourceAspect: CGFloat?,
        surface: Color
    ) -> some View {
        let image = DetailHeaderLayout.artworkSize(in: field, sourceAspect: sourceAspect, hero: hero)
        return ZStack(alignment: .top) {
            surface

            ArtworkView(url: page.thumbnailUrl, data: headerArt, side: max(image.width, image.height), fill: true)
                .frame(width: image.width, height: image.height)
                .mask {
                    if image.width < field.width - 1 {
                        containedArtMask(from: .leading, to: .trailing)
                    } else if image.height < field.height - 1 {
                        containedArtMask(from: .top, to: .bottom)
                    } else {
                        Rectangle()
                    }
                }
                .frame(width: field.width, height: field.height)

            if hero == .album, let canvasURL, albumArtVisible, !reduceMotion {
                CanvasPlayer(url: canvasURL, fallbackURL: canvasFallbackURL, isPlaying: true)
                    .frame(width: field.width, height: field.height)
                    .accessibilityHidden(true)
            }

            LinearGradient(
                stops: [
                    .init(color: surface.opacity(0), location: 0.40),
                    .init(color: surface.opacity(0.22), location: 0.62),
                    .init(color: surface, location: 0.90)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .allowsHitTesting(false)

            if !reduceTransparency && colorSchemeContrast != .increased {
                // Match the system bar's color scheme so native controls stay
                // distinguishable against both very pale and saturated art.
                LinearGradient(
                    colors: [readableSurface.opacity(0.76), readableSurface.opacity(0.44), .clear],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: min(116, field.height * 0.62))
                .allowsHitTesting(false)
            }
        }
        .frame(width: field.width, height: field.height)
        .clipped()
        .onScrollVisibilityChange(threshold: 0.12) { visible in
            if hero == .album { albumArtVisible = visible }
        }
        .accessibilityHidden(true)
    }

    private func containedArtMask(from start: UnitPoint, to end: UnitPoint) -> LinearGradient {
        LinearGradient(
            stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.10),
                    .init(color: .black, location: 0.90), .init(color: .clear, location: 1)],
            startPoint: start, endPoint: end
        )
    }

    private func albumIdentity(_ page: DetailPageModel, title: String) -> some View {
        let credit = headerLines(page).credit.ifBlank { page.songs.first?.artist ?? "" }
        let info = releaseInfoLine(page)
        return VStack(alignment: isWide ? .leading : .center, spacing: 6) {
            Text(title)
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)

            if !credit.isEmpty {
                if let artistId = page.songs.first?.artistId {
                    PushLink(destination: DetailView(browseId: artistId, initialTitle: credit)) {
                        Text(credit).font(.headline).underline()
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(.isLink)
                } else {
                    Text(credit).font(.headline)
                }
            }

            if !info.isEmpty {
                Text(info)
                    .font(.subheadline)
                    .foregroundStyle(colorSchemeContrast == .increased ? .primary : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .multilineTextAlignment(isWide ? .leading : .center)
        .frame(maxWidth: .infinity, alignment: isWide ? .leading : .center)
    }

    private func immersiveAlbumActions(_ page: DetailPageModel, tint: ArtworkPalette.PageTint) -> some View {
        let isPlaying = controller.isPlaybackContextPlaying(browseId)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                PlayPill(iconOnly: false, isPlaying: isPlaying) { playContext(page) }
                ShufflePill { playContext(page, shuffled: true) }
                Spacer(minLength: 4)
                releaseSecondaryActions(page, tint: tint)
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    ViewThatFits(in: .horizontal) {
                        PlayPill(iconOnly: false, isPlaying: isPlaying) { playContext(page) }
                        PlayPill(iconOnly: true, isPlaying: isPlaying) { playContext(page) }
                    }
                    CircleIconButton(icon: Image(.bchShuffle), label: "Shuffle", veiled: true) {
                        playContext(page, shuffled: true)
                    }
                }
                HStack(spacing: 8) { releaseSecondaryActions(page, tint: tint) }
            }
        }
    }

    /// A release header: the sleeve centred on its own shadow, the title, a
    /// tappable credit, the "year · songs · length" line, then Play and Shuffle.
    ///
    /// This is the layout for both an album and a playlist, at every width —
    /// Apple Music centres the sleeve on a phone and on a Mac alike; only the
    /// sleeve and the controls' shape change with the room available.
    private func releaseHeader(
        _ page: DetailPageModel,
        tint: ArtworkPalette.PageTint,
        width: CGFloat
    ) -> some View {
        let lines = headerLines(page)
        // Only an album borrows its first track's artist when the header names
        // nobody: a playlist's first song is not its author.
        let borrowsCredit = lines.credit.isEmpty && kind(of: page) == .album
        let credit = borrowsCredit ? (page.songs.first?.artist ?? "") : lines.credit
        let artistId = kind(of: page) == .album ? page.songs.first?.artistId : nil
        let sleeve = releaseSleeve(width)
        let info = releaseInfoLine(page)

        return VStack(spacing: 14) {
            ZStack {
                ArtworkView(url: page.thumbnailUrl, data: headerArt, side: sleeve)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: .black.opacity(0.24), radius: 18, y: 9)
                if let canvasURL {
                    CanvasPlayer(url: canvasURL, fallbackURL: canvasFallbackURL, isPlaying: true)
                        .frame(width: sleeve, height: sleeve)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }

            VStack(spacing: 5) {
                Text(page.title.isEmpty ? initialTitle : page.title)
                    .font(.largeTitle.bold())
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)

                if !credit.isEmpty {
                    if let artistId {
                        PushLink(destination: DetailView(browseId: artistId, initialTitle: credit)) {
                            Text(credit)
                                .font(.title3)
                                .foregroundStyle(tint.accent)
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(credit)
                            .font(.title3)
                            .foregroundStyle(tint.accent)
                            .lineLimit(1)
                    }
                }

                if !info.isEmpty {
                    Text(info)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)

            if !page.songs.isEmpty {
                releaseActions(page, tint: tint)
                    .padding(.top, 6)
            } else if kind(of: page) == .playlist {
                // Nothing to play, but an empty playlist is still one to
                // rename or delete — and empty is when that is usually wanted.
                releaseMoreMenu(page)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: 860)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, isWide ? 24 : 10)
        .padding(.bottom, 22)
    }

    private func releaseActions(_ page: DetailPageModel, tint: ArtworkPalette.PageTint) -> some View {
        HStack(spacing: 12) {
            if isWide {
                ShufflePill { playContext(page, shuffled: true) }
                PlayPill(iconOnly: false, isPlaying: controller.isPlaybackContextPlaying(browseId)) {
                    playContext(page)
                }
            } else {
                CircleIconButton(icon: Image(.bchShuffle), label: "Shuffle") {
                    playContext(page, shuffled: true)
                }
                PlayPill(iconOnly: true, isPlaying: controller.isPlaybackContextPlaying(browseId)) {
                    playContext(page)
                }
            }

            releaseSecondaryActions(page, tint: tint)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private func releaseSecondaryActions(_ page: DetailPageModel, tint: ArtworkPalette.PageTint) -> some View {
        if auth.signedIn, page.libraryPlaylistId != nil {
            CircleIconButton(
                icon: Image(systemName: saved ? "checkmark" : "plus"),
                label: saved ? "Remove from Library" : "Add to Library",
                active: saved,
                activeColor: tint.accent,
                disabled: saving
            ) {
                Task { await toggleSave(page) }
            }
        }

        if !page.songs.isEmpty {
            CircleIconButton(
                icon: Image(systemName: searching ? "xmark" : "magnifyingglass"),
                label: searching ? "Close search" : "Search this list",
                active: searching,
                activeColor: tint.accent
            ) {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    if searching { filter = "" }
                    searching.toggle()
                }
            }
        }

        releaseMoreMenu(page)
    }

    /// Plays or pauses this page as a context, with the current shuffle state.
    private func playContext(_ page: DetailPageModel, shuffled: Bool = false) {
        let entries = page.songs.map { toEntry($0, fallbackArt: fallbackArt(page)) }
        if shuffled {
            controller.play(
                entries, context: page.title, contextID: browseId,
                shuffleRequested: true, shuffleStart: true,
                boundedContext: true, continuationToken: handoffContinuation(page)
            )
        } else {
            controller.togglePlaybackContext(
                entries, title: page.title, contextID: browseId,
                shuffleRequested: controller.shuffleEnabled,
                continuationToken: handoffContinuation(page)
            )
        }
    }

    /// An artist's overflow: the page's own actions, none of which belong in the
    /// top bar because the bar is about the page and this is about the artist.
    /// A release's overflow: the queue rows upstream's page-level sheet keeps
    /// (MainActivity.kt:3855, `fromCard = false` — play next and add to queue
    /// without taking over playback), the collection's download state, and
    /// for a playlist of one's own the management rows.
    private func releaseMoreMenu(_ page: DetailPageModel) -> some View {
        CircleMenuButton(label: "More actions") {
            Button("Play Next") {
                controller.playNext(page.songs.map { toEntry($0, fallbackArt: fallbackArt(page)) })
                toast.queueNotice("Playing next: \(page.title)")
            }
            .disabled(page.songs.isEmpty)
            Button("Add to Queue") {
                for entry in page.songs.map({ toEntry($0, fallbackArt: fallbackArt(page)) }) {
                    controller.addToQueue(entry)
                }
                toast.queueNotice("Added \(page.songs.count) tracks to the queue")
            }
            .disabled(page.songs.isEmpty)
            Button(pinned ? "Unpin" : "Pin") {
                if PlaylistPinning.toggle(browseId: browseId) {
                    pinned.toggle()
                } else {
                    appModel.pinLimitAlert = true
                }
            }
            CollectionDownloadActions(browseId: browseId, title: page.title)
            if kind(of: page) == .playlist, page.playlistOwned == true {
                // Reordering is EditMode's drag, which is iOS-only; the Mac
                // list reorders by click-to-move and needs no door to it.
                #if os(iOS)
                Button("Reorder Songs") {
                    editMode = .active
                }
                .disabled(page.songs.isEmpty)
                #endif
                Button("Rename Playlist…") {
                    renameTitle = page.title
                    renamePresented = true
                }
                Button("Privacy: \(privacy.capitalized)") {
                    privacyPresented = true
                }
                Button("Remove Duplicates") {
                    Task { await removeDuplicates(page) }
                }
                Button("Delete Playlist", role: .destructive) {
                    confirmDelete(page)
                }
            }
        }
    }

    private func confirmDelete(_ page: DetailPageModel) {
        toast.requestConfirmation(ConfirmationRequest(
            title: "Delete this playlist?",
            message: "“\(page.title)” will be removed from your YouTube Music account. This cannot be undone.",
            confirm: "Delete Playlist"
        ) {
            Task { await deletePlaylist(page) }
        })
    }

    /// Deletes an owned playlist and leaves the dead page behind it.
    private func deletePlaylist(_ page: DetailPageModel) async {
        if let failure = await LibraryActions.deletePlaylist(playlistId: browseId) {
            toast.show("Couldn't delete it — \(failure)", kind: .failure)
            return
        }
        NotificationCenter.default.post(name: .libraryPlaylistsChanged, object: nil)
        // The Mac's split view has no stack to pop: its detail column keeps the
        // deleted page unless the shell moves the sidebar selection. Carry the
        // id so only the page that was deleted is replaced.
        NotificationCenter.default.post(
            name: .playlistDeleted, object: nil, userInfo: ["browseId": browseId]
        )
        toast.show("Deleted \(page.title)")
        dismiss()
    }

    /// Sleek inline filter bar displayed when searching is toggled on.
    private func searchField(tint: ArtworkPalette.PageTint) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
            TextField("Search this list", text: $filter)
                .textFieldStyle(.plain)
            if !filter.isEmpty {
                Button {
                    filter = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear Search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
        }
        .chromeGlass(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }

    /// "About the artist" / "About the album". An artist's section also holds
    /// the subscriber and listener counts, so a page with no blurb still gets
    /// it; the signature goes here only when the header could not show it.
    @ViewBuilder
    private func aboutSection(_ page: DetailPageModel, isArtist: Bool) -> some View {
        let desc = page.description.flatMap { $0.isEmpty ? nil : $0 }
        let hasStats = isArtist && (page.subscriberCountText != nil || page.monthlyListenerCount != nil)
        let title = page.title.isEmpty ? initialTitle : page.title
        let footerSignature = isArtist ? artistSignature.flatMap { $0.artistName == title ? nil : $0 } : nil
        if kind(of: page) != .playlist, desc != nil || hasStats || footerSignature != nil {
            VStack(alignment: .leading, spacing: 10) {
                Text(isArtist ? "About the artist" : "About the album")
                    .font(.title3.bold())
                if let desc {
                    Text(desc)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if hasStats {
                    artistStatsRow(page: page)
                        .padding(.top, 2)
                }
                if let signature = footerSignature {
                    AsyncImage(url: signature.imageURL) { image in
                        image.resizable()
                            .renderingMode(.template)
                            .scaledToFit()
                            .foregroundStyle(.primary)
                    } placeholder: {
                        Color.clear
                    }
                    .frame(maxWidth: 260, maxHeight: 100, alignment: .leading)
                    .accessibilityLabel("Artist signature for \(signature.artistName)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 28)
        }
    }

    /// Upstream's `ArtistStatsRow`: the two counts stacked and left-aligned
    /// with the About text above them. YouTube's count already says
    /// "1.2M subscribers", so only the number is kept and the label re-said.
    private func artistStatsRow(page: DetailPageModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let sub = page.subscriberCountText, !sub.isEmpty {
                let text = sub.components(separatedBy: " ").first ?? sub
                statChip(icon: "person.2.fill", text: "\(text) subscribers")
            }
            if let monthly = page.monthlyListenerCount, !monthly.isEmpty {
                let text = monthly.components(separatedBy: " ").first ?? monthly
                statChip(icon: "waveform", text: "\(text) monthly listeners")
            }
        }
    }

    private func statChip(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background {
            Capsule()
                .fill(.clear)
                .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
        }
        .chromeGlass(in: Capsule())
    }

    private func pageWash(tint: ArtworkPalette.PageTint) -> some View {
        ZStack(alignment: .top) {
            Rectangle().fill(.background)
            LinearGradient(
                colors: [tint.wash, tint.wash.opacity(0.35), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 520)
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }

    /// The sleeve size a release header uses at this window width.
    private func releaseSleeve(_ width: CGFloat) -> CGFloat {
        isWide ? 240 : min(210, max(140, width * 0.5))
    }

    /// "2023 · 12 songs · 48 minutes" — the line under a release's credit.
    ///
    /// The year comes from the subtitle YouTube already sends; the count and the
    /// length are this page's own rows, so a playlist shows its real running
    /// time rather than a catalogue figure (F10).
    private func releaseInfoLine(_ page: DetailPageModel) -> String {
        let songs = page.songs
        let partial = hasMoreSongs
        var pieces: [String] = []
        if let year = releaseYear(page) { pieces.append(year) }
        if !songs.isEmpty {
            // A long playlist arrives a page at a time. Until the last page has
            // landed, the count is "at least this many" and the length is a
            // fragment, so neither is presented as if it were the total.
            pieces.append(partial
                ? String(localized: "\(songs.count)+ songs", locale: locale)
                : String(localized: "\(songs.count) songs", locale: locale))
            if !partial {
                let total = songs.reduce(0) { $0 + durationToSeconds($1.durationText) }
                if total > 0 { pieces.append(lengthText(total)) }
            }
        }
        return pieces.joined(separator: " · ")
    }

    /// Whether YouTube still has rows for this page that haven't been fetched.
    ///
    /// The detail page loads one page and asks for the next when the list is
    /// scrolled to its end, so the songs in memory are a window onto the
    /// playlist until this is false.
    private var hasMoreSongs: Bool {
        !(continuation ?? "").isEmpty
    }

    /// The four-digit year in a page subtitle, when it has one.
    private func releaseYear(_ page: DetailPageModel) -> String? {
        page.subtitle
            .split(whereSeparator: { $0 == "•" || $0 == "·" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.count == 4 && $0.allSatisfy(\.isNumber) }
    }

    /// Format catalogue durations using the app's locale and unit grammar.
    private func lengthText(_ seconds: Int) -> String {
        if seconds < 60 {
            return Duration.seconds(seconds).formatted(.units(allowed: [.seconds], width: .wide).locale(locale))
        }
        return Duration.seconds(seconds / 60 * 60)
            .formatted(.units(allowed: [.hours, .minutes], width: .wide).locale(locale))
    }

    /// An artist's "Latest release" carousel, which the header promotes to a
    /// card of its own when there is one.
    private func latestReleaseShelf(_ page: DetailPageModel) -> FeedShelf? {
        page.sections.first {
            $0.title.localizedCaseInsensitiveContains("latest release") && !$0.items.isEmpty
        }
    }

    /// The cards a shelf should draw.
    ///
    /// An artist's latest release is promoted to the card under the header, so
    /// its first card is not drawn twice — but only that card. The shelf itself
    /// keeps its title and the rest of its releases, which used to disappear
    /// with it.
    private func carouselItems(_ shelf: FeedShelf, page: DetailPageModel) -> [ShelfCard] {
        guard shelf.id == latestReleaseShelf(page)?.id else { return shelf.items }
        return Array(shelf.items.dropFirst())
    }

    /// The promoted latest release: sleeve, title, credit, tappable through to
    /// the release's own page.
    @ViewBuilder
    private func latestReleaseCard(_ card: ShelfCard) -> some View {
        HStack(spacing: 14) {
            if let id = card.browseId, !id.isEmpty {
                PushLink(destination: DetailView(browseId: id, initialTitle: card.title)) {
                    latestReleaseBody(card)
                }
                .buttonStyle(.plain)
            } else {
                latestReleaseBody(card)
            }

            // The save circle is a sibling of the link, never inside its label:
            // a Button nested in a NavigationLink label is unreliable (the tap
            // opens the release or is swallowed), so the circle sits beside it.
            if auth.signedIn, latestReleaseLibraryId != nil {
                CircleIconButton(
                    icon: Image(systemName: latestReleaseSaved ? "checkmark" : "plus"),
                    label: latestReleaseSaved ? "Remove from Library" : "Add to Library",
                    size: 40,
                    active: latestReleaseSaved,
                    disabled: savingLatestRelease
                ) {
                    Task { await toggleLatestReleaseSave() }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: 860)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func latestReleaseBody(_ card: ShelfCard) -> some View {
        HStack(spacing: 14) {
            ArtworkView(url: card.thumbnailUrl, data: nil, side: 72)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .shadow(color: .black.opacity(0.16), radius: 6, y: 3)
            VStack(alignment: .leading, spacing: 3) {
                Text("Latest Release")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.6)
                    .textCase(.uppercase)
                Text(card.title)
                    .font(.headline)
                    .lineLimit(1)
                if let subtitle = card.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Image(.bchChevronRight)
                .resizable()
                .scaledToFit()
                .frame(width: 12)
                .foregroundStyle(.tertiary)
        }
        .contentShape(.rect)
    }

    /// A partial list reports a minimum count until pagination finishes.
    private func playtimeSummary(_ songs: [DetailPageModel.SongPayload]) -> String {
        if hasMoreSongs {
            return String(localized: "\(songs.count)+ songs", locale: locale)
        }
        let count = String(localized: "\(songs.count) songs", locale: locale)
        let seconds = songs.reduce(0) { $0 + durationToSeconds($1.durationText) }
        guard seconds > 0 else { return count }
        return String(localized: "\(count), \(lengthText(seconds))", locale: locale)
    }

    private func durationToSeconds(_ text: String?) -> Int {
        guard let text else { return 0 }
        let parts = text.split(separator: ":").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        switch parts.count {
        case 2: return parts[0] * 60 + parts[1]
        case 3: return parts[0] * 3600 + parts[1] * 60 + parts[2]
        default: return 0
        }
    }

    @ViewBuilder
    private func trackList(_ page: DetailPageModel, width: CGFloat) -> some View {
        let fallback = page.thumbnailUrl
        let rows = page.songs.enumerated().filter { _, song in
            filter.isEmpty || song.title.localizedCaseInsensitiveContains(filter) || song.artist.localizedCaseInsensitiveContains(filter)
        }
        let songs = rows.map(\.element)
        let owned = page.playlistOwned == true && filter.isEmpty

        if kind(of: page) == .artist {
            VStack(alignment: .leading, spacing: 8) {
                Text("Top songs")
                    .font(.title3.bold())
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                artistTopSongs(page, songs: songs, width: width, fallback: fallback)
            }
        } else if owned {
                List {
                    ForEach(Array(songs.enumerated()), id: \.offset) { index, song in
                        SongRow(
                            entry: toEntry(song, fallbackArt: fallback),
                            play: {
                                controller.play(
                                    page.songs.map { toEntry($0, fallbackArt: fallback) },
                                    at: page.songs.firstIndex(where: { $0.videoId == song.videoId }) ?? index,
                                    context: page.title, contextID: browseId,
                                    shuffleRequested: controller.shuffleEnabled,
                                    boundedContext: true, continuationToken: handoffContinuation(page)
                                )
                            },
                            playNext: { controller.playNext(toEntry(song, fallbackArt: fallback)) },
                            addToQueue: { controller.addToQueue(toEntry(song, fallbackArt: fallback)) },
                            playlistBrowseId: browseId,
                            playlistOwned: true
                        )
                        .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                        .listRowBackground(Color.clear)
                        .onAppear {
                            if song.videoId == songs.last?.videoId {
                                requestMoreIfNeeded()
                            }
                        }
                    }
                    .onMove { source, dest in
                        Task { await reorder(from: source, to: dest) }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .frame(minHeight: CGFloat(max(songs.count, 1)) * 58)
                #if os(iOS)
                // Owned playlists are reorderable, so they get a real edit mode
                // with an explicit Reorder control rather than being permanently
                // in one — see the note in `NowPlayingView.UpNextPane`.
                .environment(\.editMode, $editMode)
                .safeAreaInset(edge: .top, spacing: 0) {
                    if songs.count > 1 {
                        HStack {
                            Spacer()
                            Button(editMode == .active ? "Done" : "Reorder") {
                                withAnimation {
                                    editMode = editMode == .active ? .inactive : .active
                                }
                            }
                            .font(.callout)
                            .padding(.trailing, 16)
                            .padding(.bottom, 4)
                        }
                    }
                }
                #endif
                // ↑/↓ walk this page's tracks, so a release can be read without
                // reaching for the mouse: the keyboard focus follows the selection
                // and Return plays whatever the arrows landed on.
                .rowKeyboardNavigation(ids: songs.map { toEntry($0, fallbackArt: fallback).id })
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(rows, id: \.offset) { index, song in
                        SongRow(
                            entry: toEntry(song, fallbackArt: fallback),
                            play: {
                                controller.play(
                                    page.songs.map { toEntry($0, fallbackArt: fallback) },
                                    at: index,
                                    context: page.title, contextID: browseId,
                                    shuffleRequested: controller.shuffleEnabled,
                                    boundedContext: true, continuationToken: handoffContinuation(page)
                                )
                            },
                            playNext: { controller.playNext(toEntry(song, fallbackArt: fallback)) },
                            addToQueue: { controller.addToQueue(toEntry(song, fallbackArt: fallback)) },
                            playlistBrowseId: browseId,
                            playlistOwned: page.playlistOwned == true
                        )
                        .overlay(alignment: .bottom) {
                            if kind(of: page) == .album, index != rows.last?.offset {
                                Divider().padding(.leading, 56).allowsHitTesting(false)
                            }
                        }
                        .onAppear {
                            if index == rows.last?.offset {
                                requestMoreIfNeeded()
                            }
                        }
                    }
                }
                .rowKeyboardNavigation(ids: songs.map { toEntry($0, fallbackArt: fallback).id })
            }
    }

    /// An artist's top songs as upstream lays them out: columns of four, at most
    /// twenty songs, in a carousel that snaps column by column. The next column
    /// peeks in at the edge so the reader can tell there is more. A tap plays
    /// the twenty in order from that song.
    private func artistTopSongs(
        _ page: DetailPageModel,
        songs: [DetailPageModel.SongPayload],
        width: CGFloat,
        fallback: String?
    ) -> some View {
        let top = Array(songs.prefix(20))
        let columns = stride(from: 0, to: top.count, by: 4).map { Array(top[$0..<min($0 + 4, top.count)]) }
        // One column fills the width minus a peek on a phone; wider layouts
        // fit as many 360 pt columns as there is room for.
        let columnWidth = min(max(width - 32 - 36, 260), 360)
        let queue = top.map { toEntry($0, fallbackArt: fallback) }
        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(Array(columns.enumerated()), id: \.offset) { columnIndex, column in
                    VStack(spacing: 0) {
                        ForEach(Array(column.enumerated()), id: \.element.videoId) { rowIndex, song in
                            SongRow(
                                entry: toEntry(song, fallbackArt: fallback),
                                play: {
                                    controller.play(
                                        queue, at: columnIndex * 4 + rowIndex,
                                        context: page.title, contextID: browseId,
                                        shuffleRequested: controller.shuffleEnabled,
                                        boundedContext: true, continuationToken: handoffContinuation(page)
                                    )
                                },
                                playNext: { controller.playNext(toEntry(song, fallbackArt: fallback)) },
                                addToQueue: { controller.addToQueue(toEntry(song, fallbackArt: fallback)) }
                            )
                        }
                    }
                    .frame(width: columnWidth, alignment: .top)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        // The track list is padded 16 on each side; the carousel runs to the
        // screen edge and insets its content instead, so columns scroll under
        // the margin rather than being clipped at it.
        .padding(.horizontal, -16)
        .contentMargins(.horizontal, 16, for: .scrollContent)
    }

    private func toEntry(_ s: DetailPageModel.SongPayload, fallbackArt: String? = nil) -> QueueEntry {
        s.asEntry(fallbackArt: fallbackArt)
    }

    private func fallbackArt(_ page: DetailPageModel) -> String? {
        page.thumbnailUrl
    }

    private enum Kind { case album, artist, playlist, other }

    /// One shelf's "Show all" destination: a snapshot of the same cards the
    /// carousel drew, so the promoted latest release is not repeated in the
    /// grid (the carousel drops it; the shelf itself still carries it).
    private struct ShowAllGrid: Hashable {
        let title: String
        let items: [ShelfCard]
    }

    private func kind(of page: DetailPageModel) -> Kind {
        switch page.type?.uppercased() {
        case "ALBUM": return .album
        case "ARTIST": return .artist
        case "PLAYLIST": return .playlist
        default:
            if browseId.hasPrefix("UC") { return .artist }
            if browseId.hasPrefix("MPREb") || browseId.hasPrefix("OLAK") { return .album }
            if browseId.hasPrefix("VL") || browseId.hasPrefix("PL") { return .playlist }
            return .other
        }
    }

    /// Splits "Album • Artist • 2023" into the credit line and the metadata
    /// line Music shows under the title. Port of upstream `headerLines`.
    private func headerLines(_ page: DetailPageModel) -> (credit: String, meta: String) {
        let parts = page.subtitle
            .split(whereSeparator: { $0 == "•" || $0 == "·" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let kinds = Set(["album", "single", "ep", "playlist", "artist", "podcast", "episode", "song", "video"])
        let year = parts.last { $0.count == 4 && $0.allSatisfy(\.isNumber) }
        let kindWord = parts.first { kinds.contains($0.lowercased()) }
        // A playlist you own lists its privacy where others list an author;
        // it is not a name to credit or link.
        let privacy = Set(["private", "unlisted", "public"])
        let credit = parts
            .filter { $0 != year && $0 != kindWord && !privacy.contains($0.lowercased()) }
            .joined(separator: ", ")
        let kindLabel = kindWord ?? {
            switch kind(of: page) {
            case .album: return "Album"
            case .playlist: return "Playlist"
            case .artist: return "Artist"
            case .other: return nil
            }
        }()
        let count = page.songs.count
        let countText = count > 0 ? "\(count) \(count == 1 ? "song" : "songs")" : nil
        let meta = [kindLabel, year, countText].compactMap { $0 }.joined(separator: "  ·  ")
        return (credit, meta)
    }

    private func loadHeaderArt(_ url: String?) async -> Data? {
        guard let url else { return nil }
        let sized = SharedArtwork.sized(url, 720) ?? url
        let headers = WebDavBridge.shared.playbackHeaders(fileUrl: sized)
        return await ArtworkRequests.shared.data(url: sized, headers: headers)
    }

    private func load(force: Bool = false) async {
        let request = UUID(); pageRequestID = request
        let generation = PageSession.generation()
        loading = page == nil
        error = nil
        subscriptionOverride = nil
        // Offline-first: a collection saved to this device opens from the
        // store before the network answers, and the network replaces it only
        // when it succeeds (upstream e99edae0). Without this, a saved
        // playlist opened offline was an error page over songs that are on
        // the disk.
        if page == nil, !browseId.hasPrefix("UC"),
           let downloaded = DetailPageModel.downloadedCopy(browseId: browseId, from: DownloadStore.shared) {
            page = downloaded
            // The Save button keeps whatever the last page said until the
            // network answers: guessing here flickers a wrong state in.
            continuation = nil
            suggested = []
            loading = false
        }
        do {
            if browseId.hasPrefix("UC") {
                let result = try await InnertubeDetail.shared.browseArtist(browseId: browseId, force: force)
                guard generation == PageSession.generation(), pageRequestID == request, !Task.isCancelled else { return }
                page = result
                if page?.songs.isEmpty == true {
                    let result = try await InnertubeDetail.shared.browse(browseId: browseId, force: force)
                guard generation == PageSession.generation(), pageRequestID == request, !Task.isCancelled else { return }
                page = result
                }
            } else {
                let result = try await InnertubeDetail.shared.browse(browseId: browseId, force: force)
                guard generation == PageSession.generation(), pageRequestID == request, !Task.isCancelled else { return }
                page = result
            }
            saved = page?.librarySaved ?? false
            continuation = page?.continuation
            suggested = page?.suggestedSongs ?? []
        } catch {
            guard generation == PageSession.generation(), pageRequestID == request, !Task.isCancelled else { return }
            AuthController.reportIfSessionExpired(error)
            if page == nil { self.error = error.localizedDescription }
        }
        guard generation == PageSession.generation(), pageRequestID == request, !Task.isCancelled else { return }
        loading = false
        mirrorPlaybackContext()
        if error == nil { await DownloadStore.shared.syncIfOwned(browseId: browseId) }
    }

    private func loadMore() async {
        // The token is kept until a page actually arrives, because it is what the
        // retry and the "12+ songs" count both read. Clearing it before the await
        // made a slow page — and a failed one for ever — look like the end of the
        // playlist. `loadingMore` is what stops the last row asking twice.
        guard !loadingMore, !controller.ownsPlaybackContextWindow(browseId),
              let token = continuation, !token.isEmpty else { return }
        loadingMore = true
        defer { loadingMore = false }
        let generation = PageSession.generation()
        let request = pageRequestID
        guard let extra = try? await InnertubeDetail.shared.more(token: token),
              generation == PageSession.generation(), !Task.isCancelled,
              pageRequestID == request, !controller.ownsPlaybackContextWindow(browseId), var page else { return }
        var known = Set(page.songs.map(\.videoId))
        let additions = extra.songs.filter { known.insert($0.videoId).inserted }
        page.songs.append(contentsOf: additions)
        suggested.append(contentsOf: extra.suggestedSongs)
        continuation = extra.continuation == token || additions.isEmpty ? nil : extra.continuation
        page.continuation = continuation
        self.page = page
    }

    private func requestMoreIfNeeded() {
        guard !controller.ownsPlaybackContextWindow(browseId), loadMoreTask == nil else { return }
        loadMoreTask = Task { @MainActor in
            await loadMore()
            loadMoreTask = nil
        }
    }

    /// Playback becomes the sole owner of paging once this page starts a
    /// context. Cancelling an in-flight view request leaves the token intact;
    /// the controller takes that token and mirrors completed pages back here.
    private func handoffContinuation(_ page: DetailPageModel) -> String? {
        loadMoreTask?.cancel()
        loadMoreTask = nil
        loadingMore = false
        return continuation
    }

    private func mirrorPlaybackContext() {
        guard controller.ownsPlaybackContextWindow(browseId), var page else { return }
        page.songs = controller.playbackContextEntries.compactMap { entry in
            guard let videoId = entry.videoId else { return nil }
            return DetailPageModel.SongPayload(
                videoId: videoId,
                title: entry.title,
                artist: entry.artist,
                thumbnailUrl: entry.thumbnailUrl,
                durationText: entry.durationText,
                albumName: entry.albumName,
                isVideo: entry.isVideo,
                artistId: entry.artistId,
                albumId: entry.albumId,
                setVideoId: entry.setVideoId
            )
        }
        continuation = controller.playbackContextContinuation
        page.continuation = continuation
        self.page = page
    }

    private func toggleSave(_ page: DetailPageModel) async {
        guard let pid = page.libraryPlaylistId else { return }
        guard !saving else { return }
        let generation = PageSession.generation()
        saving = true
        defer { saving = false }
        let wasSaved = saved
        let next = !wasSaved
        // Optimistic, like the subscribe button beside it: flip now so the
        // control answers instantly, and roll back if the server refuses.
        // Waiting on the network made the two library toggles disagree in feel.
        saved = next
        let failure = await LibraryActions.ratePlaylist(playlistId: pid, saved: next)
        guard generation == PageSession.generation(), !Task.isCancelled else { return }
        if let failure {
            saved = wasSaved
            toast.show("Couldn’t update library: \(failure)", kind: .failure)
        }
    }

    /// Reads the latest release's library id + saved state by fetching its page,
    /// the same way upstream's `releaseLibraryState(browseId)` does. The full
    /// page is cached, so this costs nothing extra if the release is opened.
    private func loadLatestReleaseLibrary(_ card: ShelfCard) async {
        guard let browseId = card.browseId, !browseId.isEmpty else { return }
        let generation = PageSession.generation()
        let request = pageRequestID
        guard let result = try? await InnertubeDetail.shared.browse(browseId: browseId, force: false),
              generation == PageSession.generation(), pageRequestID == request, !Task.isCancelled else { return }
        latestReleaseLibraryId = result.libraryPlaylistId
        latestReleaseSaved = result.librarySaved ?? false
    }

    private func toggleLatestReleaseSave() async {
        guard let pid = latestReleaseLibraryId, !savingLatestRelease else { return }
        let generation = PageSession.generation()
        savingLatestRelease = true
        defer { savingLatestRelease = false }
        let wasSaved = latestReleaseSaved
        let next = !wasSaved
        latestReleaseSaved = next
        let failure = await LibraryActions.ratePlaylist(playlistId: pid, saved: next)
        guard generation == PageSession.generation(), !Task.isCancelled else { return }
        if let failure {
            latestReleaseSaved = wasSaved
            toast.show("Couldn’t update library: \(failure)", kind: .failure)
        }
    }

    private func toggleSubscription(_ subscription: ArtistSubscriptionPayload, artistName: String) async {
        guard !subscribing else { return }
        let generation = PageSession.generation()
        subscribing = true
        defer { subscribing = false }
        let wasSubscribed = subscriptionOverride ?? subscription.subscribed
        let next = !wasSubscribed
        subscriptionOverride = next
        let failure = await LibraryActions.setSubscribed(channelId: subscription.channelId, subscribed: next)
        guard generation == PageSession.generation(), !Task.isCancelled else { return }
        if let failure {
            subscriptionOverride = wasSubscribed
            toast.show("Couldn’t update subscription: \(failure)", kind: .failure)
        } else {
            toast.show(next ? "Subscribed to \(artistName)" : "Unsubscribed from \(artistName)")
        }
    }

    private func setPrivacy(_ value: String) async {
        privacy = value
        _ = await LibraryActions.setPlaylistPrivacy(playlistId: browseId, privacy: value)
    }

    private func removeDuplicates(_ page: DetailPageModel) async {
        let generation = PageSession.generation()
        let pairs = page.songs.compactMap { song -> (setVideoId: String, videoId: String)? in
            guard let setVideoId = song.setVideoId else { return nil }
            return (setVideoId, song.videoId)
        }
        let failure = await LibraryActions.removeDuplicates(playlistId: browseId, songs: pairs)
        guard generation == PageSession.generation(), !Task.isCancelled, failure == nil else { return }
        var seen = Set<String>()
        var kept: [DetailPageModel.SongPayload] = []
        for song in page.songs {
            if seen.insert(song.videoId).inserted { kept.append(song) }
        }
        var next = page
        next.songs = kept
        self.page = next
    }

    private func reorder(from source: IndexSet, to dest: Int) async {
        guard var page else { return }
        page.songs.move(fromOffsets: source, toOffset: dest)
        self.page = page
        guard let from = source.first else { return }
        let movedIndex = dest > from ? dest - 1 : dest
        guard page.songs.indices.contains(movedIndex), let setVideoId = page.songs[movedIndex].setVideoId else { return }
        let successor = page.songs.indices.contains(movedIndex + 1) ? page.songs[movedIndex + 1].setVideoId : nil
        _ = await LibraryActions.movePlaylistItem(playlistId: browseId, setVideoId: setVideoId, successorSetVideoId: successor)
    }

    private func loadCanvas(_ page: DetailPageModel) async {
        guard kind(of: page) == .album,
              PlatformSettings.shared.getBoolean(key: "animated_canvas", default: true) else {
            canvasURL = nil
            canvasFallbackURL = nil
            return
        }
        let credit = headerLines(page).credit.ifBlank { page.songs.first?.artist ?? "" }
        let title = page.title
        let json: String? = await withCheckedContinuation { cont in
            CanvasBridge.shared.lookupAlbum(album: title, artist: credit, callback: DetailCanvasCB { cont.resume(returning: $0) })
        }
        guard !Task.isCancelled, let json, let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let url = (obj["url"] as? String).flatMap(URL.init(string:)) else { return }
        canvasURL = url
        canvasFallbackURL = (obj["fallbackUrl"] as? String).flatMap(URL.init(string:))
    }
}

private extension String {
    func ifBlank(_ fallback: () -> String) -> String {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback() : self
    }
}

private final class DetailCanvasCB: CanvasBridgeCanvasCallback {
    let handler: (String?) -> Void
    init(_ handler: @escaping (String?) -> Void) { self.handler = handler }
    func onResult(json: String?) { handler(json) }
}

/// The loading detail page, shaped like the one coming (upstream
/// `detailSkeleton(isArtist:)`): the sleeve or hero block at its real size
/// (`releaseSleeve`'s and the artist hero's own formulas), the title lines,
/// the action row's controls and the song rows beneath.
private struct DetailSkeleton: View {
    var isArtist: Bool
    var immersive: Bool
    var wide: Bool

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ScrollView {
                if isArtist {
                    artist(width: width, height: geo.size.height)
                } else if immersive {
                    album(width: width, height: geo.size.height)
                } else {
                    release(width: width)
                }
            }
            #if os(iOS)
            .ignoresSafeArea(.container, edges: immersive ? .top : [])
            #endif
            .scrollDisabled(true)
        }
        .accessibilityElement()
        .accessibilityLabel("Loading")
    }

    private func artist(width: CGFloat, height: CGFloat) -> some View {
        let artHeight = DetailHeaderLayout.artistArtworkHeight(width: width, viewportHeight: height)
        return VStack(spacing: 0) {
            SkeletonBlock(height: artHeight, cornerRadius: 0)
                .overlay(alignment: .bottomLeading) {
                    SkeletonBlock(height: 32, cornerRadius: 7)
                        .frame(width: min(width * 0.56, 320))
                        .padding(22)
                }
            HStack(spacing: 10) {
                SkeletonBlock(height: 46, cornerRadius: 23).frame(width: 96)
                Circle().fill(.quaternary).frame(width: 46, height: 46)
                Spacer()
                Circle().fill(.quaternary).frame(width: 46, height: 46)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .frame(maxWidth: DetailHeaderLayout.maxContentWidth)

            VStack(alignment: .leading, spacing: 8) {
                SkeletonBlock(height: 20, cornerRadius: 6).frame(width: 110)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                VStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { _ in SkeletonSongRow() }
                }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: DetailHeaderLayout.maxContentWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func album(width: CGFloat, height: CGFloat) -> some View {
        let artworkWidth = DetailHeaderLayout.albumWidth(in: width)
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                SkeletonBlock(height: DetailHeaderLayout.albumArtworkHeight(width: width, viewportHeight: height), cornerRadius: 0)
                VStack(alignment: .leading, spacing: 8) {
                    SkeletonBlock(height: 32, cornerRadius: 6).frame(width: min(artworkWidth * 0.70, 300))
                    SkeletonBlock(height: 17, cornerRadius: 5).frame(width: min(artworkWidth * 0.48, 190))
                    SkeletonBlock(height: 13, cornerRadius: 4).frame(width: min(artworkWidth * 0.53, 230))
                }
                .padding(18)
            }
            .background(.quaternary.opacity(0.35))
            HStack(spacing: 8) {
                SkeletonBlock(height: 46, cornerRadius: 23).frame(width: 96)
                SkeletonBlock(height: 46, cornerRadius: 23).frame(width: 110)
            }
            ForEach(0..<4, id: \.self) { _ in SkeletonSongRow() }
        }
        .frame(width: artworkWidth)
    }

    /// `releaseHeader`'s stack: the sleeve (`releaseSleeve`), title, credit and
    /// info lines, and the action row as wide or narrow draws it.
    private func release(width: CGFloat) -> some View {
        let sleeve = wide ? 240 : min(210, max(140, width * 0.5))
        return VStack(spacing: 14) {
            SkeletonBlock(height: sleeve, cornerRadius: 12)
                .frame(width: sleeve)
            VStack(spacing: 8) {
                SkeletonBlock(height: 22, cornerRadius: 6).frame(width: min(width * 0.55, 280))
                SkeletonBlock(height: 16, cornerRadius: 5).frame(width: min(width * 0.35, 170))
                SkeletonBlock(height: 11, cornerRadius: 4).frame(width: min(width * 0.45, 200))
            }
            HStack(spacing: 12) {
                if wide {
                    SkeletonBlock(height: 46, cornerRadius: 23).frame(width: 111)
                    SkeletonBlock(height: 46, cornerRadius: 23).frame(width: 95)
                } else {
                    Circle().fill(.quaternary).frame(width: 46, height: 46)
                    Circle().fill(.quaternary).frame(width: 46, height: 46)
                }
                Circle().fill(.quaternary).frame(width: 46, height: 46)
                Circle().fill(.quaternary).frame(width: 46, height: 46)
            }
            .padding(.top, 6)
            VStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { _ in SkeletonSongRow() }
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: 860)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, wide ? 24 : 10)
    }
}

// MARK: - Circular Action Buttons

private struct CircleIconButton: View {
    let icon: Image
    let label: String
    var size: CGFloat = 46
    /// Upstream's artist-row look: a light veil with a hairline edge rather
    /// than the flat grey disc.
    var veiled: Bool = false
    var active: Bool = false
    var activeColor: Color? = nil
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(active ? (activeColor ?? .accentColor) : Color.primary.opacity(veiled ? 0.10 : 0.12))
                .overlay {
                    if veiled {
                        Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                    }
                }
                .overlay {
                    icon
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: size * 0.44, height: size * 0.44)
                        .foregroundStyle(active ? Color.white : Color.primary)
                }
                .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .accessibilityLabel(label)
        .help(label)
    }
}

private struct PlayPill: View {
    var iconOnly: Bool = true
    var size: CGFloat = 46
    var isPlaying: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if iconOnly {
                    Circle()
                        .fill(Color.white)
                        .overlay {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: size * 0.40, height: size * 0.40)
                                .offset(x: isPlaying ? 0 : 1.5)
                                .foregroundStyle(Color.black)
                        }
                        .frame(width: size, height: size)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.body.weight(.bold))
                            .foregroundStyle(Color.black)
                        Text(isPlaying ? "Pause" : "Play")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.black)
                    }
                    .padding(.horizontal, 24)
                    .frame(height: size)
                    .background(Color.white, in: Capsule())
                }
            }
            .shadow(color: .black.opacity(0.20), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
        .help(isPlaying ? "Pause" : "Play")
    }
}

/// The secondary half of a release header's Play/Shuffle pair.
///
/// A capsule rather than a circle, so it reads as the peer of Play at a wide
/// width; the phone layout keeps a circle, which fits beside the sleeve's title.
private struct ShufflePill: View {
    var size: CGFloat = 46
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(.bchShuffle)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size * 0.38, height: size * 0.38)
                Text("Shuffle")
                    .font(.body.weight(.semibold))
            }
            .padding(.horizontal, 20)
            .frame(height: size)
            .background(.thinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.primary.opacity(0.12), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Shuffle")
        .help("Shuffle")
    }
}

private struct CircleMenuButton<Content: View>: View {
    let label: String
    var size: CGFloat = 46
    @ViewBuilder let content: () -> Content

    var body: some View {
        Menu {
            content()
        } label: {
            Circle()
                .fill(Color.primary.opacity(0.12))
                .overlay {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.primary)
                }
                .frame(width: size, height: size)
        }
        #if os(macOS)
        // AppKit's borderless menu draws only a label's text and image, so
        // the circle came out as a bare ellipsis glyph. The button style with
        // a plain button draws the label as built.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        #else
        .buttonStyle(.plain)
        .menuStyle(.borderlessButton)
        #endif
        .accessibilityLabel(label)
        .help(label)
    }
}
