import Foundation

enum AudenLibrarySection: String, CaseIterable, Identifiable {
    case songs, albums, artists, playlists, recent, local, downloads, history, subscriptions, podcasts, webdav

    var id: Self { self }

    static func ordered(_ saved: String) -> [Self] {
        var seen: Set<Self> = []
        return (saved.split(separator: ",").compactMap { Self(rawValue: String($0)) } + allCases)
            .filter { seen.insert($0).inserted }
    }
}

#if os(iOS)
import SwiftUI

extension AudenLibrarySection {
    var title: LocalizedStringKey {
        switch self {
        case .songs: "Songs"
        case .albums: "Albums"
        case .artists: "Artists"
        case .playlists: "Playlists"
        case .recent: "Recent"
        case .local: "Local Music"
        case .downloads: "Downloads"
        case .history: "History"
        case .subscriptions: "Subscriptions"
        case .podcasts: "Podcasts"
        case .webdav: "WebDAV"
        }
    }

    var icon: String {
        switch self {
        case .songs: "music.note"
        case .albums: "square.stack"
        case .artists: "music.mic"
        case .playlists: "music.note.list"
        case .recent: "clock.arrow.circlepath"
        case .local: "folder"
        case .downloads: "arrow.down.circle"
        case .history: "clock"
        case .subscriptions: "bell"
        case .podcasts: "radio"
        case .webdav: "cloud"
        }
    }
}

struct AudenLibrarySectionList: View {
    let available: [AudenLibrarySection]
    let onPickFolder: () -> Void

    @AppStorage("musicsk.auden.library.order") private var order = ""
    @AppStorage("musicsk.auden.library.hidden") private var hidden = ""
    @State private var editing = false

    private var shown: [AudenLibrarySection] {
        let hiddenIDs = Set(hidden.split(separator: ",").map(String.init))
        return AudenLibrarySection.ordered(order).filter { available.contains($0) && !hiddenIDs.contains($0.rawValue) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Browse Library").font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Edit") { editing = true }
                    .accessibilityIdentifier("auden.library.edit")
            }
            .padding(.bottom, 6)
            ForEach(shown) { section in
                PushLink { destination(section) } label: {
                    HStack(spacing: 14) {
                        Image(systemName: section.icon).font(.system(size: 22)).frame(width: 27)
                            .accessibilityHidden(true)
                        Text(section.title).font(.body)
                        Spacer()
                        Image(systemName: "chevron.forward").font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary).accessibilityHidden(true)
                    }
                    .frame(minHeight: 49)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 41)
            }
        }
        .sheet(isPresented: $editing) {
            NavigationStack {
                List {
                    ForEach(AudenLibrarySection.ordered(order)) { section in
                        Toggle(isOn: visibility(section)) {
                            Label(section.title, systemImage: section.icon)
                        }
                    }
                    .onMove { from, to in
                        var sections = AudenLibrarySection.ordered(order)
                        sections.move(fromOffsets: from, toOffset: to)
                        order = sections.map(\.rawValue).joined(separator: ",")
                    }
                }
                .environment(\.editMode, .constant(.active))
                .navigationTitle("Browse Library")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { editing = false }
                    }
                }
            }
        }
    }

    private func visibility(_ section: AudenLibrarySection) -> Binding<Bool> {
        Binding {
            !hidden.split(separator: ",").contains { $0 == section.rawValue }
        } set: { visible in
            var keys = Set(hidden.split(separator: ",").map(String.init))
            if visible { keys.remove(section.rawValue) }
            else { keys.insert(section.rawValue) }
            hidden = keys.sorted().joined(separator: ",")
        }
    }

    @ViewBuilder
    private func destination(_ section: AudenLibrarySection) -> some View {
        switch section {
        case .songs: UnifiedSongsView(title: "Songs", onPickFolder: onPickFolder)
        case .albums: UnifiedAlbumsView(title: "Albums", onPickFolder: onPickFolder)
        case .artists: UnifiedArtistsView(title: "Artists", onPickFolder: onPickFolder)
        case .playlists: SavedPlaylistsView()
        case .recent: YoutubeLibraryView()
        case .local: LocalMusicView(onPickFolder: onPickFolder)
        case .downloads: DownloadsView()
        case .history: HistoryView()
        case .subscriptions: LibraryView(lockedSection: .subscriptions)
        case .podcasts: LibraryView(lockedSection: .podcasts)
        case .webdav: WebDavLibraryView()
        }
    }
}
#endif
