import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import BitChordShared
import UniformTypeIdentifiers

/// Music saved to the account or the device, with browsing destinations and
/// device utilities below the collection preview.
struct LibraryLandingView: View {
    var onPickFolder: () -> Void
    @Environment(AuthController.self) private var auth
    @Environment(AppModel.self) private var appModel
    @Environment(PlaybackController.self) private var controller
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var downloadStore = DownloadStore.shared
    @State private var local = LocalLibrary.shared
    @State private var shelves: [FeedShelf] = []
    @State private var dataGeneration: Int64?
    @State private var loading = true
    @State private var error: String?
    @State private var contentWidth: CGFloat = 354

    private let gridSpacing: CGFloat = 14

    private var columnCount: Int {
        let minimum: CGFloat = dynamicTypeSize.isAccessibilitySize ? 192 : 136
        return max(1, min(4, Int((contentWidth + gridSpacing) / (minimum + gridSpacing))))
    }

    private var coverSide: CGFloat {
        floor((contentWidth - gridSpacing * CGFloat(columnCount - 1)) / CGFloat(columnCount))
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.fixed(coverSide), spacing: gridSpacing, alignment: .topLeading), count: columnCount)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
                collection
                categories
                onDeviceShelf
                ReplayHeroSection { page in appModel.openReplay(at: page) }
            }
            .frame(maxWidth: 860)
            .onGeometryChange(for: CGFloat.self) { floor($0.size.width) } action: { width in
                if width > 0 { contentWidth = width }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
        }
        .refreshable {
            downloadStore.refresh()
            await loadShelves(force: true)
        }
        .task(id: auth.sessionEpoch) {
            downloadStore.refresh()
            await loadShelves()
        }
    }

    @ViewBuilder
    private var collection: some View {
        let savedShelves = pinnedShelves(shelves).filter { !$0.items.isEmpty }

        if auth.signedIn && loading && savedShelves.isEmpty {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                ForEach(0..<min(columnCount * 2, 6), id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 8) {
                        SkeletonBlock(height: coverSide, cornerRadius: 10)
                        SkeletonBlock(height: 14, cornerRadius: 4).frame(width: coverSide * 0.72)
                    }
                }
            }
            .accessibilityLabel("Loading Library")
        } else if auth.signedIn && !savedShelves.isEmpty {
            ForEach(savedShelves) { shelf in
                shelfSection(shelf)
            }
        } else {
            let offline = offlineTracks()
            if !offline.isEmpty {
                heading("On this device")
                LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                    ForEach(offline) { track in
                        LocalTrackCard(track: track) {
                            controller.play(
                                [QueueEntry.from(track)],
                                context: track.title,
                                contextID: "local:\(track.path)"
                            )
                        }
                    }
                }
            }

            if !auth.signedIn {
                signedInPrompt
            } else if let error {
                EmptyStateView(
                    icon: Image(.bchLibrary), title: "Library couldn't load",
                    subtitle: error, buttonTitle: "Retry"
                ) { Task { await loadShelves() } }
            } else if offline.isEmpty {
                EmptyStateView(
                    icon: Image(.bchLibrary), title: "No saved music",
                    subtitle: "Save an album or playlist in YouTube Music, or choose a music folder on this device.",
                    buttonTitle: "Choose Folder", action: onPickFolder
                )
            }
        }
    }

    private func offlineTracks() -> [LocalTrack] {
        let limit = min(columnCount * 2, 6)
        let downloads = downloadStore.items.prefix(limit).map { track in
            LocalTrack(
                path: track.path, title: track.title, artist: track.artist, album: track.album,
                durationSeconds: 0, artwork: track.artwork, dateAdded: nil,
                dateModified: nil, artworkURL: track.artworkURL
            )
        }
        let paths = Set(downloads.map(\.path))
        let scanned = local.tracks.lazy.filter { !paths.contains($0.path) }
        return downloads + Array(scanned.prefix(limit - downloads.count))
    }

    private var categories: some View {
        VStack(alignment: .leading, spacing: 4) {
            heading("Browse Library").padding(.bottom, 6)
            category("Songs", image: "music.note") {
                UnifiedSongsView(title: "Songs", onPickFolder: onPickFolder)
            }
            category("Albums", image: "square.stack") {
                UnifiedAlbumsView(title: "Albums", onPickFolder: onPickFolder)
            }
            category("Artists", image: "music.mic") {
                UnifiedArtistsView(title: "Artists", onPickFolder: onPickFolder)
            }
            category("Playlists", image: "music.note.list") {
                SavedPlaylistsView()
            }
            if auth.signedIn {
                category("Recent", image: "clock.arrow.circlepath") {
                    YoutubeLibraryView()
                }
            }
        }
    }

    private func category<Destination: View>(
        _ title: LocalizedStringKey,
        image: String,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        PushLink(destination: destination) {
            HStack(spacing: 12) {
                Image(systemName: image)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.tint)
                    .frame(width: 28)
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func heading(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.title3.weight(.bold))
            .accessibilityAddTraits(.isHeader)
    }

    private var onDeviceShelf: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("On device")
                .font(.title3.weight(.bold))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    // Upstream's On-Device shelf leads with the playlists and
                    // albums downloaded whole, as artwork cards, before the
                    // folder destinations — they are the things a listener is
                    // actually going offline to play.
                    ForEach(downloadStore.collections) { collection in
                        if let browseId = collection.browseId {
                            OnDeviceCard(
                                title: collection.title,
                                subtitle: "\(collection.requests.count) saved",
                                systemImage: "square.and.arrow.down.fill",
                                tintColor: .green,
                                destination: DetailView(browseId: browseId, initialTitle: collection.title)
                            )
                        }
                    }

                    OnDeviceCard(
                        title: "Downloads",
                        subtitle: "\(downloadStore.items.count) downloaded song\(downloadStore.items.count == 1 ? "" : "s")",
                        systemImage: "arrow.down.circle.fill",
                        tintColor: .accentColor,
                        destination: DownloadsView()
                    )

                    OnDeviceCard(
                        title: "Local Music",
                        subtitle: local.scanned ? "\(local.tracks.count) song\(local.tracks.count == 1 ? "" : "s")" : "Choose folder",
                        systemImage: "folder.fill",
                        tintColor: .indigo,
                        destination: LocalMusicView(onPickFolder: onPickFolder)
                    )

                    OnDeviceCard(
                        title: "WebDAV",
                        subtitle: WebDavStore.shared.isConfigured ? "Connected" : "Not configured",
                        systemImage: "cloud.fill",
                        tintColor: .teal,
                        destination: WebDavLibraryView()
                    )

                    OnDeviceCard(
                        title: "History",
                        subtitle: "Listening history",
                        systemImage: "clock.fill",
                        tintColor: .orange,
                        destination: HistoryView()
                    )
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var signedInPrompt: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 56, height: 56)
                Image(systemName: "person.crop.circle.badge.plus")
                    .scaledFont(size: 26, weight: .semibold)
                    .foregroundStyle(.tint)
            }
            Text("Sign in for your library")
                .font(.headline)
            Text("Liked playlists, albums and artists you save show up here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Sign In") {
                auth.loginPresented = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.separator.opacity(0.5), lineWidth: 0.5)
        )
    }

    private func shelfSection(_ shelf: FeedShelf) -> some View {
        let isPlaylists = isPlaylistsShelf(shelf)
        let items = displayItems(shelf)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(shelf.title)
                    .font(.title3.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if shelf.items.count > items.count {
                    PushLink {
                        LibraryGridView(title: shelf.title, items: shelf.items, isPlaylists: isPlaylists)
                    } label: {
                        Label("Show all", systemImage: "chevron.forward")
                            .labelStyle(.titleOnly)
                            .font(.callout)
                            .foregroundStyle(.tint)
                    }
                }
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                ForEach(items) { card in
                    ShelfCardView(card: card, artworkSide: coverSide)
                }
            }
        }
    }

    private func pinnedShelves(_ shelves: [FeedShelf]) -> [FeedShelf] {
        let pinned = PlaylistPinning.pinnedIds()
        return shelves.map { shelf in
            guard isPlaylistsShelf(shelf) else { return shelf }
            let items = shelf.items.sorted { a, b in
                let ap = pinned.contains(a.browseId ?? "")
                let bp = pinned.contains(b.browseId ?? "")
                if ap == bp { return false }
                return ap && !bp
            }
            return FeedShelf(title: shelf.title, items: items, subtitle: shelf.subtitle)
        }
    }

    private func displayItems(_ shelf: FeedShelf) -> [ShelfCard] {
        var seen = Set<String>()
        return Array(shelf.items.lazy.filter { seen.insert($0.id).inserted }.prefix(columnCount))
    }

    private func isPlaylistsShelf(_ shelf: FeedShelf) -> Bool {
        shelf.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "playlists"
    }

    private func loadShelves(force: Bool = false) async {
        guard auth.signedIn else {
            loading = false
            shelves = []
            return
        }
        let generation = PageSession.generation()
        if dataGeneration != generation { shelves = []; dataGeneration = generation }
        loading = shelves.isEmpty
        error = nil
        do {
            let result = try await InnertubeFeed.shared.library(force: force)
            guard generation == PageSession.generation(), !Task.isCancelled else { return }
            shelves = result
        } catch {
            guard generation == PageSession.generation(), !Task.isCancelled else { return }
            AuthController.reportIfSessionExpired(error)
            self.error = error.localizedDescription
        }
        loading = false
    }
}

/// Upstream's card representation on the "On device" shelf.
struct OnDeviceCard<Destination: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tintColor: Color
    let destination: Destination

    var body: some View {
        PushLink(destination: destination) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(tintColor.opacity(0.12))
                        .frame(width: 160, height: 160)
                    Image(systemName: systemImage)
                        .scaledFont(size: 46, weight: .medium)
                        .foregroundStyle(tintColor)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.separator.opacity(0.4), lineWidth: 0.5)
                )

                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 160, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .modifier(MacCardHoverLift())
    }
}
