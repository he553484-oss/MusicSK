#if os(iOS)
import SwiftUI

struct AudenLocalHome: View {
    @Environment(PlaybackController.self) private var controller
    @State private var local = LocalLibrary.shared

    var body: some View {
        let tracks = Array(local.tracks.prefix(12)).audenUnique()
        if !tracks.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                PushLink { LibraryView(lockedSection: .ondevice) } label: {
                    Label("On this device", systemImage: "chevron.forward")
                        .labelStyle(.titleAndIcon)
                        .font(.title3.weight(.semibold))
                }
                .buttonStyle(.plain)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: AudenDesign.spacing) {
                        ForEach(tracks) { track in
                            LocalTrackCard(track: track) {
                                controller.play(tracks.map { QueueEntry.from($0) },
                                                at: tracks.firstIndex { $0.id == track.id } ?? 0,
                                                context: String(localized: "On this device"), contextID: "auden:local-home")
                            }
                            .frame(width: 126)
                        }
                    }
                }
            }
        }
    }
}
#endif
