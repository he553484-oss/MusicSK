import Foundation
import Observation
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import MediaPlayer
import BitChordShared
#if os(iOS)
import NowPlaying
import AVFoundation
#if DEBUG
import Synchronization
#endif
#endif

/// Lock-screen / media-key / Bluetooth controls (spec §3.2 NowPlayingController).
/// iOS 27 uses NowPlaying; older iOS and macOS use MediaPlayer.
@MainActor
final class NowPlayingController {
    private var metadataKey: String?
    private var metadataProgress = NowPlayingPlaybackState()
    private var artwork: MPMediaItemArtwork?
    /// URL that `artwork` was built from — not the in-flight request.
    private var artworkURL: String?
    private var lastRequestedURL: String?
    private var handlers: [Any] = []
#if os(iOS)
    private var modern: AnyObject?
    private var animatedSource: NowPlayingArtworkSource?
    private var artworkTask: Task<Void, Never>?
    private var requestedSource: NowPlayingArtworkSource?
    private var artworkGeneration = UUID()
    private var installedClips: [NowPlayingArtworkShape: NowPlayingClip] = [:]
    private var legacyAnimatedMetadata: [String: Any] = [:]
    private var artworkObservers: [NSObjectProtocol] = []
#endif

    init() {
#if os(iOS)
        NowPlayingActivityController.endLegacyActivities()
        if #available(iOS 26, *) { observeArtworkPolicy() }
        if #available(iOS 27, *) {
            resetModernModel()
            // iOS 27+: metadata and commands live EXCLUSIVELY on the
            // MediaSession. Publishing this playback through
            // MPNowPlayingInfoCenter / MPRemoteCommandCenter alongside it is
            // undefined behavior per Apple ("Don't mix the Now Playing
            // framework with ... MPNowPlayingInfoCenter and
            // MPRemoteCommandCenter ... for local playback"). No MP handlers here.
            return
        }
        DispatchQueue.main.async {
            UIApplication.shared.beginReceivingRemoteControlEvents()
        }
#endif
        // MP path: macOS, and iOS versions without the NowPlaying framework.
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        handlers.append(center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.onPlay?() }
            return .success
        })
        center.pauseCommand.isEnabled = true
        handlers.append(center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.onPause?() }
            return .success
        })
        center.togglePlayPauseCommand.isEnabled = true
        handlers.append(center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.onToggle?() }
            return .success
        })
        center.nextTrackCommand.isEnabled = true
        handlers.append(center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.onNext?() }
            return .success
        })
        center.previousTrackCommand.isEnabled = true
        handlers.append(center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.onPrevious?() }
            return .success
        })
        center.changePlaybackPositionCommand.isEnabled = true
        handlers.append(center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let position = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime else {
                return .commandFailed
            }
            Task { @MainActor [weak self] in self?.onSeek?(position) }
            return .success
        })
    }

    var onPlay: (() -> Void)?
#if os(iOS)
    var onPlayAsync: (() async throws -> Void)?
#endif
    var onPause: (() -> Void)?
    var onToggle: (() -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onSeek: ((Double) -> Void)?

#if os(iOS)
    @available(iOS 27, *)
    private func resetModernModel() {
        let model = ModernNowPlaying()
        model.delegate = self
        modern = model
    }
#if DEBUG
    func verifyModernObservation() -> [String: Bool] {
        if #available(iOS 27, *) { return ModernNowPlaying.verifyObservation() }
        return [:]
    }
#endif
#endif

    /// Called only for an explicit play intent, after activation and a paused
    /// engine load have succeeded, before engine.play().
    func prepareForPlayback(id: String, title: String, artist: String, album: String? = nil, duration: Double,
                            artworkData: Data?, thumbnailUrl: String?, position: Double,
                            canNext: Bool, canPrevious: Bool, canSeek: Bool) {
#if os(iOS)
        if #available(iOS 27, *), let model = modern as? ModernNowPlaying {
            prepareMetadata(for: id)
            model.prepare(id: id, title: title, artist: artist, album: album, duration: duration,
                          artworkData: artworkData, thumbnailUrl: thumbnailUrl, position: position,
                          canNext: canNext, canPrevious: canPrevious, canSeek: canSeek)
        }
#endif
    }

    func update(id: String, title: String, artist: String, album: String? = nil, duration: Double,
                artworkData: Data?, thumbnailUrl: String?, isPlaying: Bool,
                position: Double? = nil) {
        prepareMetadata(for: id)
        // iOS 27 publishes exclusively through the MediaSession (see init:
        // mixing in MPNowPlayingInfoCenter yields undefined behavior).
#if os(iOS)
        if #available(iOS 27, *), let model = modern as? ModernNowPlaying {
            model.update(id: id, title: title, artist: artist, album: album, duration: duration,
                         artworkData: artworkData, thumbnailUrl: thumbnailUrl,
                         isPlaying: isPlaying, position: position)
            return
        }
#endif
        let rate = isPlaying ? Double(PlatformSettings.shared.getFloat(key: "playback_speed", default: 1)) : 0
        let elapsed = position ?? metadataProgress.predictedPosition(at: Date())
        metadataProgress = metadataProgress.updating(rate: rate, position: elapsed)
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: artist,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyPlaybackRate: metadataProgress.rate,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: metadataProgress.position,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let album { info[MPMediaItemPropertyAlbumTitle] = album }
        #if os(iOS)
        info.merge(legacyAnimatedMetadata, uniquingKeysWith: { _, animated in animated })
        #endif
        if lastRequestedURL != thumbnailUrl { lastRequestedURL = nil }
        if let item = artworkFromBytes(artworkData) {
            info[MPMediaItemPropertyArtwork] = item
            artworkURL = thumbnailUrl
            lastRequestedURL = thumbnailUrl
        } else if let artwork, artworkURL == thumbnailUrl {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
#if os(macOS)
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
#endif
        if let thumbnailUrl, !thumbnailUrl.isEmpty, artworkData == nil,
           artworkURL != thumbnailUrl, lastRequestedURL != thumbnailUrl {
            fetchArtwork(
                id: id, url: thumbnailUrl, title: title, artist: artist,
                duration: duration, isPlaying: isPlaying
            )
        }
    }

    func updateCommands(canNext: Bool, canPrevious: Bool, canSeek: Bool) {
#if os(iOS)
        if #available(iOS 27, *), let model = modern as? ModernNowPlaying {
            model.canNext = canNext
            model.canPrevious = canPrevious
            model.canSeek = canSeek
            return
        }
#endif
        let commands = MPRemoteCommandCenter.shared()
        commands.nextTrackCommand.isEnabled = canNext
        commands.previousTrackCommand.isEnabled = canPrevious
        commands.changePlaybackPositionCommand.isEnabled = canSeek
    }

    /// A native progress clock interpolates between anchors. Periodic engine
    /// samples are needed only to correct observable drift.
    func synchronizePosition(_ position: Double) {
#if os(iOS)
        if #available(iOS 27, *), let model = modern as? ModernNowPlaying {
            model.synchronizePosition(position)
            return
        }
#endif
        guard metadataKey != nil, metadataProgress.needsCorrection(position: position) else { return }
        update(position: position)
    }

    func update(position: Double) {
#if os(iOS)
        if #available(iOS 27, *), let model = modern as? ModernNowPlaying {
            model.updatePosition(position)
            return
        }
#endif
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        metadataProgress = metadataProgress.updating(position: position)
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = metadataProgress.position
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func updateRate(_ rate: Double, position: Double? = nil) {
#if os(iOS)
        if #available(iOS 27, *), let model = modern as? ModernNowPlaying {
            model.updateRate(rate, position: position)
            return
        }
#endif
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        metadataProgress = metadataProgress.updating(rate: rate, position: position ?? metadataProgress.predictedPosition(at: Date()))
        info[MPNowPlayingInfoPropertyPlaybackRate] = metadataProgress.rate
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = metadataProgress.position
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
#if os(macOS)
        MPNowPlayingInfoCenter.default().playbackState = rate > 0 ? .playing : .paused
#endif
    }

    /// Called after audio activation and engine playback have succeeded.
    func playbackDidStart() {
#if os(iOS)
        if #available(iOS 27, *), let model = modern as? ModernNowPlaying {
            model.playbackDidStart()
        }
#endif
        requestPrimaryIfPossible(reason: "playback")
    }

    func requestPrimaryIfPossible(reason: String = "foreground") {
#if os(iOS)
        if #available(iOS 27, *), let model = modern as? ModernNowPlaying {
            model.requestPrimaryIfPossible(reason: reason)
        }
#endif
    }

    func audioSessionUnavailable() {
#if os(iOS)
        if #available(iOS 27, *), let model = modern as? ModernNowPlaying {
            model.suspendClaims()
        }
#endif
    }

    func stop() {
        clearMetadata()
#if os(iOS)
        if #available(iOS 27, *), let model = modern as? ModernNowPlaying {
            model.stop()
            // A suspended framework call can retain the old representation.
            // It must never observe metadata or deliver commands for new play.
            resetModernModel()
            return
        }
#endif
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
#if os(macOS)
        MPNowPlayingInfoCenter.default().playbackState = .stopped
#endif
    }

    private func prepareMetadata(for id: String) {
        guard metadataKey != id else { return }
        clearMetadata()
        metadataKey = id
    }

    private func clearMetadata() {
        metadataKey = nil
        metadataProgress = NowPlayingPlaybackState()
        artwork = nil
        artworkURL = nil
        lastRequestedURL = nil
        #if os(iOS)
        artworkGeneration = UUID()
        artworkTask?.cancel()
        artworkTask = nil
        requestedSource = nil
        animatedSource = nil
        installedClips = [:]
        legacyAnimatedMetadata = [:]
        #endif
    }

    #if os(iOS)
    func setAnimatedArtwork(id: String, source: NowPlayingArtworkSource?) {
        guard #available(iOS 26, *), metadataKey == id else { return }
        animatedSource = source
        refreshAnimatedArtwork()
    }

    @available(iOS 26, *)
    private func observeArtworkPolicy() {
        let names: [Notification.Name] = [
            .NSProcessInfoPowerStateDidChange,
            ProcessInfo.thermalStateDidChangeNotification,
            UIAccessibility.reduceMotionStatusDidChangeNotification
        ]
        artworkObservers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refreshAnimatedArtwork() }
            }
        }
        observeArtworkNetwork()
    }

    @available(iOS 26, *)
    private func observeArtworkNetwork() {
        withObservationTracking {
            _ = NetworkQuality.shared.pathChanges
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.observeArtworkNetwork()
                self.refreshAnimatedArtwork()
            }
        }
    }

    @available(iOS 26, *)
    private var artworkPolicyAllowsMotion: Bool {
        let device = ProcessInfo.processInfo
        return NetworkQuality.shared.canvasAllowed && !NetworkQuality.shared.constrained
            && !UIAccessibility.isReduceMotionEnabled && !device.isLowPowerModeEnabled
            && device.thermalState.rawValue < ProcessInfo.ThermalState.serious.rawValue
    }

    @available(iOS 26, *)
    private func refreshAnimatedArtwork() {
        let allowedSource = artworkPolicyAllowsMotion ? animatedSource : nil
        if allowedSource == requestedSource,
           artworkTask != nil || !installedClips.isEmpty || allowedSource == nil { return }
        artworkTask?.cancel()
        artworkTask = nil
        let generation = UUID()
        artworkGeneration = generation
        requestedSource = allowedSource
        // Settings changes and a genuinely different rendition clear the old
        // metadata before beginning any new download.
        installAnimatedClips([:])
        guard let source = allowedSource else { return }
        let shapes: Set<NowPlayingArtworkShape>
        if #available(iOS 27, *) {
            shapes = Set(AnimatedArtwork.compatibleAspectRatios.compactMap {
                switch $0 {
                case .square: .square
                case .tall: .tall
                @unknown default: nil
                }
            })
        } else {
            let keys = MPNowPlayingInfoCenter.supportedAnimatedArtworkKeys
            shapes = Set(NowPlayingArtworkShape.allCases.filter { keys.contains($0.mediaPlayerKey) })
        }
        guard !shapes.isEmpty else { return }
        let allowDownload = NetworkQuality.shared.connected
        artworkTask = Task(priority: .utility) { [weak self] in
            let clips = await NowPlayingArtworkLoader.prepare(source, shapes: shapes, allowDownload: allowDownload)
            guard !Task.isCancelled, let self, self.artworkGeneration == generation else { return }
            self.artworkTask = nil
            guard self.artworkPolicyAllowsMotion else { return }
            self.installAnimatedClips(clips)
        }
    }

    @available(iOS 26, *)
    private func installAnimatedClips(_ clips: [NowPlayingArtworkShape: NowPlayingClip]) {
        guard clips.mapValues(\.id) != installedClips.mapValues(\.id) else { return }
        installedClips = clips
        if #available(iOS 27, *), let model = modern as? ModernNowPlaying {
            model.animatedClips = clips
            return
        }

        let center = MPNowPlayingInfoCenter.default()
        var info = center.nowPlayingInfo
        for key in legacyAnimatedMetadata.keys { info?.removeValue(forKey: key) }
        legacyAnimatedMetadata.removeAll(keepingCapacity: true)
        for (shape, clip) in clips {
            guard let preview = UIImage(data: clip.preview) else { continue }
            let animated = MPMediaItemAnimatedArtwork(
                artworkID: clip.id, previewImageRequestHandler: { _ async in preview },
                videoAssetFileURLRequestHandler: { _ async in clip.file.url }
            )
            legacyAnimatedMetadata[shape.mediaPlayerKey] = animated
            info?[shape.mediaPlayerKey] = animated
        }
        if let info {
            publishLegacyArtwork(info)
        }
    }
    #endif

    private func publishLegacyArtwork(_ info: [String: Any]) {
        // Replacing nowPlayingInfo restarts the system's interpolation from
        // the elapsed value in the dictionary. Keep that anchor current even
        // when the only incoming change is artwork prepared asynchronously.
        var info = info
        metadataProgress = metadataProgress.reanchored(at: Date())
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = metadataProgress.position
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func artworkFromBytes(_ data: Data?) -> MPMediaItemArtwork? {
        guard let data else { return nil }
#if os(iOS)
        guard let image = UIImage(data: data) else { return nil }
        let size = image.size
        let item = MPMediaItemArtwork(boundsSize: size) { _ in image }
        artwork = item
        return item
#else
        guard let image = NSImage(data: data) else { return nil }
        let size = image.size
        let item = MPMediaItemArtwork(boundsSize: size) { requested in
            let canvas = NSImage(size: requested)
            canvas.lockFocus()
            image.draw(in: NSRect(origin: .zero, size: requested))
            canvas.unlockFocus()
            return canvas
        }
        artwork = item
        return item
#endif
    }

    /// Fetch the thumbnail off-main, then publish it. `lastRequestedURL` is
    /// the in-flight cache key so a later track cannot land artwork on this one.
    private func fetchArtwork(
        id: String, url: String, title: String, artist: String, duration: Double, isPlaying: Bool
    ) {
        lastRequestedURL = url
        let sized = SharedArtwork.sized(url, 544) ?? url
        let headers = LocalArtwork.isReference(sized) ? [:] : WebDavBridge.shared.playbackHeaders(fileUrl: sized)
        Task.detached(priority: .utility) { [weak self] in
            guard let data = await ArtworkRequests.shared.data(url: sized, headers: headers),
                  !data.isEmpty else { return }
            await MainActor.run { [weak self] in
                guard let self, self.metadataKey == id, self.lastRequestedURL == url else { return }
                guard let item = self.artworkFromBytes(data) else { return }
                self.artworkURL = url
                guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
                info[MPMediaItemPropertyArtwork] = item
                self.publishLegacyArtwork(info)
            }
        }
    }
}

#if os(iOS)
@available(iOS 26, *)
private extension NowPlayingArtworkShape {
    var mediaPlayerKey: String {
        switch self {
        case .square: MPNowPlayingInfoProperty1x1AnimatedArtwork
        case .tall: MPNowPlayingInfoProperty3x4AnimatedArtwork
        }
    }
}

/// iOS 27 publishes an explicit media session, including its playback state.
/// Keep it separate from the legacy MediaPlayer path: Apple says not to publish
/// the same local playback through both APIs.
@available(iOS 27, *)
@Observable
@MainActor
private final class ModernNowPlaying: MediaSessionRepresentable {
    let id = "bitchord-player-\(UUID().uuidString)"
    weak var delegate: NowPlayingController?
    var title = ""
    var artist = ""
    var album = ""
    var duration: Double = 0
    @ObservationIgnored private var playback = NowPlayingPlaybackState()
    // Observe the actual framework value. Getters must not mutate diagnostic
    // state or accidentally make command availability depend on playback.
    private(set) var playbackSnapshot: MediaPlaybackSnapshot?
    var position: Double { playback.position }
    var rate: Double { playback.rate }
    var preparing: Bool { playback.preparing }
    var artworkData: Data?
    var artworkURL: String?
    var animatedClips: [NowPlayingArtworkShape: NowPlayingClip] = [:]
    var canNext = false
    var canPrevious = false
    var canSeek = false
    var contentID: String?
    @ObservationIgnored private var lastSnapshotState: String?
    @ObservationIgnored private lazy var lifecycle = NowPlayingLifecycle(
        makeSession: { [weak self] in
            guard let self else { return nil }
            return ModernNowPlayingSession(MediaSession(self))
        },
        audioReady: { AudioSessionManager.isActive },
        // Control Center makes a foreground app inactive. It is still in the
        // foreground; native selection there must not be treated as background.
        foreground: { UIApplication.shared.applicationState != .background },
        log: { message in
            PlaybackDebugLog.shared.record(message)
            NSLog("[BitChord] %@", message)
        }
    )

    var content: (any MediaContentRepresentable)? {
        guard let contentID else { return nil }
        let imageData = artworkData
        let imageURL = artworkURL
        let staticArtwork: Artwork? = (imageData != nil || imageURL != nil)
            ? Artwork(id: "\(contentID)|\(imageURL ?? "embedded")") { _ in
                if let imageData { return try ArtworkRepresentation(data: imageData) }
                guard let imageURL
                else { throw ArtworkRepresentation.ArtworkRepresentationError.noRepresentationAvailable }
                let sized = SharedArtwork.sized(imageURL, 544) ?? imageURL
                let headers = LocalArtwork.isReference(sized) ? [:] : WebDavBridge.shared.playbackHeaders(fileUrl: sized)
                guard let data = await ArtworkRequests.shared.data(url: sized, headers: headers)
                else { throw ArtworkRepresentation.ArtworkRepresentationError.noRepresentationAvailable }
                return try ArtworkRepresentation(data: data)
            }
            : nil
        let total = duration > 0 ? MediaDuration.finite(duration) : nil
        if !animatedClips.isEmpty {
            let variants = animatedClips
            let sortedShapes = NowPlayingArtworkShape.allCases.filter { variants[$0] != nil }
            let identity = sortedShapes.compactMap { variants[$0]?.id }.joined(separator: "|")
            let animated = AnimatedArtwork(
                id: identity,
                supportedAspectRatios: sortedShapes.map { $0 == .square ? .square : .tall },
                preview: { _, aspect in
                    let clip = try Self.clip(for: aspect, in: variants)
                    return try ArtworkRepresentation(data: clip.preview)
                },
                video: { _, aspect in
                    try Self.clip(for: aspect, in: variants).file.url
                }
            )
            if let primary = sortedShapes.first.flatMap({ variants[$0] }) {
                let preview = Artwork(id: "preview|\(primary.id)") { _ in
                    try ArtworkRepresentation(data: primary.preview)
                }
                return MusicContent(
                    id: contentID, songTitle: title, artistName: artist, albumName: album,
                    type: .audio, duration: total, artwork: staticArtwork ?? preview,
                    animatedArtwork: animated
                )
            }
        }
        return MusicContent(
            id: contentID, songTitle: title, artistName: artist, albumName: album,
            type: .audio, duration: total, artwork: staticArtwork
        )
    }

    nonisolated private static func clip(for aspect: AnimatedArtwork.AspectRatio,
                                         in clips: [NowPlayingArtworkShape: NowPlayingClip]) throws -> NowPlayingClip {
        let shape: NowPlayingArtworkShape
        switch aspect {
        case .square: shape = .square
        case .tall: shape = .tall
        @unknown default:
            throw ArtworkRepresentation.ArtworkRepresentationError.noRepresentationAvailable
        }
        guard let clip = clips[shape] else {
            throw ArtworkRepresentation.ArtworkRepresentationError.noRepresentationAvailable
        }
        return clip
    }

    private func publishPlayback(_ value: NowPlayingPlaybackState) {
        playback = value
        guard contentID != nil else {
            playbackSnapshot = nil
            return
        }
        let state = value.preparing ? "buffering" : (value.rate > 0 ? "playing" : "paused")
        let snapshot = MediaPlaybackSnapshot(
            state: value.preparing ? .buffering : (value.rate > 0 ? .playing(rate: Float(value.rate)) : .paused),
            elapsedTime: value.position, timestamp: value.timestamp
        )
        if playbackSnapshot != snapshot { playbackSnapshot = snapshot }
        if lastSnapshotState != state {
            lastSnapshotState = state
            record("snapshot published state=\(state) position=\(value.position)")
        }
    }

    var commands: [MediaCommand] {
        return [
            .play { [weak self] in
                guard let self else { throw CancellationError() }
                try await self.performPlay()
            },
            .pause { [weak self] in try self?.perform("pause", action: self?.delegate?.onPause) },
            .next { [weak self] in try self?.perform("next", action: self?.delegate?.onNext) }.enabled(canNext),
            .previous { [weak self] in try self?.perform("previous", action: self?.delegate?.onPrevious) }.enabled(canPrevious),
            .seekToPosition { [weak self] seconds in
                guard let self else { throw CancellationError() }
                try self.perform("seek position=\(seconds)", action: self.delegate?.onSeek.map { seek in { seek(seconds) } })
            }.enabled(canSeek),
        ]
    }

    private func performPlay() async throws {
        guard let contentID, let action = delegate?.onPlayAsync else {
            throw CancellationError()
        }
        record("command received play")
        do {
            try await NowPlayingCommandCompletion.perform(action: action) {
                self.contentID == contentID && self.rate > 0 && !self.preparing
            }
            record("command completed play")
        } catch {
            record("command failed play: \(error)")
            throw error
        }
    }

    private func perform(_ command: String, action: (() -> Void)?) throws {
        guard contentID != nil, let action else {
            record("command rejected \(command): inactive session or missing handler")
            throw CancellationError()
        }
        record("command received \(command)")
        action()
        record("command dispatched \(command)")
    }

    private func record(_ event: String) {
        let message = "Now Playing \(event) session=\(id) content=\(contentID ?? "none") "
            + "rate=\(rate) preparing=\(preparing) appState=\(UIApplication.shared.applicationState.rawValue)"
        PlaybackDebugLog.shared.record(message)
        NSLog("[BitChord] %@", message)
    }

    func prepare(id: String, title: String, artist: String, album: String?, duration: Double,
                 artworkData: Data?, thumbnailUrl: String?, position: Double,
                 canNext: Bool, canPrevious: Bool, canSeek: Bool) {
        update(id: id, title: title, artist: artist, album: album, duration: duration,
               artworkData: artworkData, thumbnailUrl: thumbnailUrl,
               isPlaying: false, position: position)
        self.canNext = canNext
        self.canPrevious = canPrevious
        self.canSeek = canSeek
        // Ordinary resume keeps the published paused snapshot until playback
        // actually starts. A buffering snapshot is only needed for registration.
        publishPlayback(playback.updating(preparing: !lifecycle.hasSession))
        lifecycle.prepare()
    }

    func playbackDidStart() {
        publishPlayback(playback.updating(preparing: false))
        lifecycle.update(contentID: contentID, playing: rate > 0)
        record("audio playback started")
    }

    func update(id: String, title: String, artist: String, album: String? = nil, duration: Double,
                artworkData: Data?, thumbnailUrl: String?, isPlaying: Bool,
                position: Double?) {
        let trackChanged = contentID != id
        let elapsed = position ?? (trackChanged ? 0 : nil)
        if trackChanged {
            animatedClips = [:]
            contentID = id
        }
        self.title = title
        self.artist = artist
        self.album = album ?? ""
        self.duration = duration
        self.artworkData = artworkData
        self.artworkURL = thumbnailUrl
        let speed = Double(PlatformSettings.shared.getFloat(key: "playback_speed", default: 1))
        updateRate(isPlaying ? speed : 0, position: elapsed)
    }

    func updateRate(_ rate: Double, position: Double? = nil) {
        let validRate = rate.isFinite ? max(0, rate) : 0
        // One write publishes a consistent state/time pair. Unchanged metadata
        // keeps the original timestamp instead of restarting native progress.
        publishPlayback(playback.updating(rate: validRate, position: position))
        lifecycle.update(contentID: contentID, playing: self.rate > 0)
    }

    func synchronizePosition(_ position: Double) {
        guard playback.needsCorrection(position: position) else { return }
        updatePosition(position)
    }

    func updatePosition(_ position: Double) {
        publishPlayback(playback.updating(position: position))
    }

    func requestPrimaryIfPossible(reason: String) {
        lifecycle.request(reason: reason)
    }

    func suspendClaims() {
        lifecycle.suspend()
    }

    func stop() {
        lifecycle.stop()
        playback = NowPlayingPlaybackState()
        playbackSnapshot = nil
        title = ""
        contentID = nil
    }

#if DEBUG
    /// Exercise the actual SDK adapter's observation dependencies, without
    /// creating another media session or touching the user's audio session.
    static func verifyObservation() -> [String: Bool] {
        let model = ModernNowPlaying()
        model.update(id: "observation-fixture", title: "Fixture", artist: "Fixture", duration: 40,
                     artworkData: nil, thumbnailUrl: nil, isPlaying: true, position: 2)
        let snapshotChanged = Mutex(false)
        let commandsChanged = Mutex(false)
        withObservationTracking { _ = model.playbackSnapshot } onChange: {
            snapshotChanged.withLock { $0 = true }
        }
        withObservationTracking { _ = model.commands } onChange: {
            commandsChanged.withLock { $0 = true }
        }
        model.updateRate(0, position: 2)
        var checks = [
            "observation.pauseSnapshot": snapshotChanged.withLock { $0 },
            "observation.pauseKeepsCommands": !commandsChanged.withLock { $0 },
            "observation.pausedValue": model.playbackSnapshot == MediaPlaybackSnapshot(
                state: .paused, elapsedTime: 2, timestamp: model.playback.timestamp)
        ]
        let positionChangedCommands = Mutex(false)
        withObservationTracking { _ = model.commands } onChange: {
            positionChangedCommands.withLock { $0 = true }
        }
        model.updatePosition(3)
        checks["observation.positionKeepsCommands"] = !positionChangedCommands.withLock { $0 }
        let resumedSnapshot = Mutex(false)
        withObservationTracking { _ = model.playbackSnapshot } onChange: {
            resumedSnapshot.withLock { $0 = true }
        }
        model.updateRate(1, position: 3)
        checks["observation.resumeSnapshot"] = resumedSnapshot.withLock { $0 }
        checks["observation.playingValue"] = model.playbackSnapshot == MediaPlaybackSnapshot(
            state: .playing(), elapsedTime: 3, timestamp: model.playback.timestamp)
        checks["observation.noPublication"] = !model.lifecycle.hasSession
        return checks
    }
#endif
}

/// Keep framework-specific observation and errors outside the tested policy.
@available(iOS 27, *)
@MainActor
private final class ModernNowPlayingSession: NowPlayingSessionDriver {
    private let session: MediaSession<ModernNowPlaying>
    private var observing = false
    private var lastEligibility = false
    private var lastApplicationPrimary = false
    private var eligibilityChanged: (@MainActor () -> Void)?

    init(_ session: MediaSession<ModernNowPlaying>) { self.session = session }
    var canBecomeApplicationPrimary: Bool { session.canBecomeApplicationPrimary }
    var isApplicationPrimary: Bool { session.isApplicationPrimary }
    var isSystemPrimary: Bool { session.isSystemPrimary }
    func publish() async throws { try await session.requestToBecomeApplicationPrimary() }
    func promote() async throws { try await session.requestToBecomeSystemPrimary() }

    func classify(_ error: Error) -> NowPlayingClaimFailure {
        switch error as? MediaSessionError {
        case .sessionInvalidated: return .invalidated
        case .invalidState: return .ineligible
        default: return .transient
        }
    }

    func observeEligibility(_ changed: @escaping @MainActor () -> Void) {
        observing = true
        lastEligibility = canBecomeApplicationPrimary
        lastApplicationPrimary = isApplicationPrimary
        eligibilityChanged = changed
        observe()
    }

    func stopObserving() {
        observing = false
        eligibilityChanged = nil
    }

    private func observe() {
        guard observing else { return }
        withObservationTracking {
            _ = session.canBecomeApplicationPrimary
            _ = session.isApplicationPrimary
            _ = session.isSystemPrimary
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.observing else { return }
                let eligible = self.canBecomeApplicationPrimary
                let applicationPrimary = self.isApplicationPrimary
                let message = "Now Playing status session=\(self.session.id) eligible=\(eligible) "
                    + "applicationPrimary=\(applicationPrimary) systemPrimary=\(self.isSystemPrimary)"
                PlaybackDebugLog.shared.record(message)
                NSLog("[BitChord] %@", message)
                // A superseded uncancellable request can steal application
                // primary from the new session. Recover on that status edge;
                // system prominence changes alone never trigger takeover.
                let needsPublication = eligible && (!self.lastEligibility
                    || (self.lastApplicationPrimary && !applicationPrimary))
                self.lastEligibility = eligible
                self.lastApplicationPrimary = applicationPrimary
                self.observe()
                if needsPublication { self.eligibilityChanged?() }
            }
        }
    }
}
#endif

/// Publishes the widget snapshot into the App Group container
/// (spec §3.2 WidgetStatePublisher / §9): ready-to-play semantics, no
/// position, last-played fallback handled widget-side. Artwork crosses as a
/// file (the spec's "size-capped artwork file"), and the whole publish runs
/// off the main thread — preference writes to a group container can stall on
/// container resolution and must never block the UI.
@MainActor
final class WidgetStatePublisher {
    func publish(entry: QueueEntry?, isPlaying: Bool, canNext: Bool, canPrevious: Bool) {
        guard let entry else { return }
        let group = "group.app.musicsk.player"
        // Unprovisioned App Groups hang cfprefsd on write — skip when the
        // container is missing rather than compiling DEBUG out entirely.
        guard FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: group
        ) != nil else { return }
        let title = entry.title
        let artist = entry.artist
        let artwork = entry.artworkData
        let artworkURL = Self.artworkFileURL()
        DispatchQueue.global(qos: .utility).async {
            guard let defaults = UserDefaults(suiteName: group) else { return }
            defaults.set(title, forKey: "widget.title")
            defaults.set(artist, forKey: "widget.artist")
            defaults.set(isPlaying, forKey: "widget.playing")
            defaults.set(canNext, forKey: "widget.canNext")
            defaults.set(canPrevious, forKey: "widget.canPrevious")
            if let artwork {
                if let url = artworkURL {
                    try? artwork.write(to: url, options: .atomic)
                    defaults.set(url.path, forKey: "widget.artworkPath")
                }
            } else {
                defaults.removeObject(forKey: "widget.artworkPath")
            }
        }
    }

    nonisolated private static func artworkFileURL() -> URL? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.app.musicsk.player"
        ) else { return nil }
        return container.appendingPathComponent("widget-artwork.jpg")
    }
}
