import Foundation
import BitChordShared
import os
#if os(iOS)
import UIKit
#if DEBUG
import AVFoundation
#endif
#else
import AppKit
#endif

// Animated artwork for the active catalogue track.
extension PlaybackController {
    /// Re-read feature and network preferences after a settings change.
    func refreshCanvasLookup() {
        guard let current else { return }
        fetchCanvas(for: current)
    }

    func prepareCanvasSelection(_ entry: QueueEntry) {
        let identity = CanvasTrackIdentity(entry)
        guard canvasIdentity != identity else { return }
        canvasIdentity = identity
        canvasLookupGeneration &+= 1
        clearCanvas()
    }

    func fetchCanvas(for entry: QueueEntry) {
        let identity = CanvasTrackIdentity(entry)
        prepareCanvasSelection(entry)
        let allowed = NetworkQuality.shared.canvasAllowed && identity.usesCatalogue
        if !allowed { clearCanvas() }
        canvasLookupGeneration &+= 1
        let generation = canvasLookupGeneration
        publishCanvas(for: entry.id)
        guard allowed else { return }

        CanvasBridge.shared.lookup(
            title: entry.title, artist: entry.artist, album: entry.albumName,
            callback: CanvasAdapter { [weak self] json in
                Task { @MainActor in
                    guard let self, self.canvasLookupIsCurrent(identity, generation: generation) else { return }
                    if self.applyCanvas(json, for: entry) { return }
                    // A song lookup can miss even when the release has artwork.
                    // The shared catalogue lookup independently verifies album and artist.
                    guard let album = entry.albumName, !identity.album.isEmpty else { return }
                    CanvasBridge.shared.lookupAlbum(album: album, artist: entry.artist, callback: CanvasAdapter { [weak self] json in
                        Task { @MainActor in
                            guard let self, self.canvasLookupIsCurrent(identity, generation: generation) else { return }
                            if !self.applyCanvas(json, for: entry) {
                                NSLog("[BitChord] no animated artwork found for '%@' by '%@'", entry.title, entry.artist)
                            }
                        }
                    })
                }
            }
        )

        if identity.album.isEmpty {
            // Some queue paths enrich the active entry after playback begins.
            // Use exactly the same identity checks and fallback on the retry.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(350))
                guard let self, self.canvasLookupGeneration == generation,
                      let latest = self.current, latest.id == entry.id,
                      !CanvasTrackIdentity(latest).album.isEmpty else { return }
                self.fetchCanvas(for: latest)
            }
        }
    }

    private func canvasLookupIsCurrent(_ identity: CanvasTrackIdentity, generation: UInt64) -> Bool {
        canvasLookupGeneration == generation
            && current.map(CanvasTrackIdentity.init) == identity
            && NetworkQuality.shared.canvasAllowed
    }

    private func applyCanvas(_ json: String?, for entry: QueueEntry) -> Bool {
        guard let data = json?.data(using: .utf8),
              let payload = try? JSONDecoder().decode(CanvasPayload.self, from: data),
              let url = URL(string: payload.url) else { return false }
        canvasURL = url
        canvasFallbackURL = payload.fallbackUrl.flatMap(URL.init(string:))
        canvasSource = payload.source
        publishCanvas(for: entry.id)
        NSLog("[BitChord] animated artwork source=%@ host=%@ for '%@'",
              payload.source, url.host ?? "unknown", entry.title)
        return true
    }

    private func clearCanvas() {
        canvasURL = nil
        canvasFallbackURL = nil
        canvasSource = nil
    }

    private func publishCanvas(for id: String) {
        #if os(iOS)
        let source = canvasURL.map { NowPlayingArtworkSource(primary: $0, fallback: canvasFallbackURL) }
        nowPlaying.setAnimatedArtwork(id: id, source: source)
        #endif
    }

    private struct CanvasPayload: Codable {
        let url: String
        let source: String
        let fallbackUrl: String?
    }
}
