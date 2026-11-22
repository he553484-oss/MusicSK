import AVFoundation
import AVKit
import Observation
import SwiftUI
import BitChordShared

/// App-wide owner of the O9 video side.
///
/// One muted `AVPlayer` feeds every visible surface, and a video-side request
/// exists only while **all** of these are true: the "Show Music Videos" switch
/// is on, at least one player surface is on screen, the app is active, and a
/// track with a videoId is playing. While it is visible, at most one upcoming
/// video's choice, alignment and segment index are prepared; no second player
/// or decoder runs for that preparation.
@MainActor
@Observable
final class VideoPlayback: NSObject, AVPictureInPictureControllerDelegate {
    static let shared = VideoPlayback()

    private(set) var side: ResolvedVideoSide?
    /// A music video is being found, fetched or lined up: the surface says so
    /// instead of leaving the toggle looking dead.
    private(set) var preparing = false
    let controller = VideoSideController(clock: VideoClock(position: { 0 }, isPlaying: { false }))

    @ObservationIgnored private var gate = VideoSurfaceState()
    private var mountedId: String?
    @ObservationIgnored private var resolvedId: String?
    @ObservationIgnored private var retriedId: String?
    @ObservationIgnored private var resolveTask: Task<Void, Never>?
    @ObservationIgnored private var surfaceRelease: Task<Void, Never>?
    @ObservationIgnored private var lastGateLog: String?
    @ObservationIgnored private var aheadTask: Task<Void, Never>?
    @ObservationIgnored private var aheadId: String?
    private struct PreparedVideo {
        let songId: String
        let side: ResolvedVideoSide
        let map: VideoVersionAlignment.Map?
        let saved: Date
    }
    @ObservationIgnored private var preparedAhead: PreparedVideo?
    private var presentedFrames = VideoPresentedFrames()
    private var alternateVersion: VideoVersion?

    private override init() { super.init() }

    var player: AVPlayer { controller.player }
    var state: VideoSideController.State { controller.state }
    var videoAspect: CGFloat {
        let size = controller.presentationSize
        if size.width > 0, size.height > 0 { return size.width / size.height }
        return CGFloat(side?.aspectRatio ?? (16.0 / 9.0))
    }
    func picture(for trackID: String?) -> VideoPictureIdentity? {
        guard let trackID, mountedId == trackID, side != nil, gate.canRequest,
              controller.state == .loading || controller.state == .ready else { return nil }
        return VideoPictureIdentity(trackID: trackID, itemRevision: controller.itemRevision)
    }

    func isDisplayingVideo(for trackID: String?, on surface: UUID? = nil) -> Bool {
        controller.hasAppliedClock && presentedFrames.displays(picture(for: trackID), on: surface)
    }

    func reportFrame(on surface: UUID, picture source: VideoPictureIdentity, ready: Bool) {
        presentedFrames.report(surface: surface, picture: source, ready: ready, current: picture(for: source.trackID))
    }

    func clearFrame(on surface: UUID) { presentedFrames.remove(surface: surface) }

    func offersVideoVersion(for trackID: String?) -> Bool {
        trackID != nil && mountedId == trackID && alternateVersion != nil
    }

    func playAlternateVideo(for trackID: String?) {
        guard offersVideoVersion(for: trackID), let alternateVersion else { return }
        self.alternateVersion = nil
        hooks?.playVideoVersion(alternateVersion.videoId, alternateVersion.durationText)
    }
    /// A short answer when the toggle found nothing, so it does not look dead.
    private(set) var notice: String?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored private var pictureInPictureController: AVPictureInPictureController?
    @ObservationIgnored private weak var pictureInPictureLayer: AVPlayerLayer?
    @ObservationIgnored private var pictureInPicturePossibility: NSKeyValueObservation?
    @ObservationIgnored private var isStartingPictureInPicture = false
    @ObservationIgnored private var detachedPictureInPictureLayer: AVPlayerLayer?
    @ObservationIgnored private var pictureLayers: [PictureLayerReference] = []
    private final class PictureLayerReference {
        weak var layer: AVPlayerLayer?
        init(_ layer: AVPlayerLayer) { self.layer = layer }
    }
    private(set) var canStartPictureInPicture = false
    private(set) var pictureInPictureActive = false
    @ObservationIgnored private var networkAllowed = true

    private func say(_ text: String?) {
        noticeTask?.cancel()
        notice = text
        guard text != nil else { return }
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    /// What the picture needs from the player beyond its clock: the playing
    /// song's credits and length, to find its music video, and the way to put
    /// the music-video upload itself on the audio side when the two cuts do not
    /// line up.
    struct PlayerHooks {
        var track: () -> (title: String, artist: String, seconds: Double, durationText: String?)?
        var playVideoVersion: (_ videoId: String, _ durationText: String?) -> Void
        var next: () -> (videoId: String, title: String, artist: String, seconds: Double, durationText: String?)? = { nil }
    }

    @ObservationIgnored private var hooks: PlayerHooks?

    /// The clock is the audio player's; every surface passes the same closures
    /// because there is exactly one audio player.
    func configure(clock: VideoClock, hooks: PlayerHooks) {
        controller.setClock(clock)
        self.hooks = hooks
    }

    func setEnabled(_ on: Bool) {
        guard gate.enabled != on else { return }
        PlaybackDebugLog.shared.record("video: switch \(on ? "on" : "off")", about: gate.trackId)
        gate.setEnabled(on)
        if !on {
            pictureInPictureController?.stopPictureInPicture()
        }
        reconcile()
    }


    func setSurfaceVisible(_ visible: Bool, videoId: String?) {
        surfaceRelease?.cancel()
        surfaceRelease = nil
        if visible {
            gate.surfaceAppeared(videoId: videoId)
        } else {
            gate.surfaceDisappeared()
            if gate.surfaces == 0, gate.enabled, gate.active, networkAllowed,
               !gate.pictureInPictureActive, mountedId != nil {
                // SwiftUI can notify the disappearing host before mounting its
                // replacement. Keep the current item through that handoff.
                surfaceRelease = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(160))
                    guard !Task.isCancelled, let self else { return }
                    self.surfaceRelease = nil
                    self.reconcile()
                }
                return
            }
        }
        reconcile()
    }

    func setTrack(_ videoId: String?) {
        gate.setTrack(videoId)
        reconcile()
    }

    /// Scene phase only. A surface leaving or arriving never writes this.
    func setActive(_ active: Bool) {
        gate.setActive(active)
        reconcile()
    }

    func refreshNetworkPolicy() {
        let allowed = !NetworkQuality.shared.metered ||
            PlatformSettings.shared.getBoolean(key: "video_over_cellular", default: false)
        guard networkAllowed != allowed else { return }
        networkAllowed = allowed
        if !allowed { pictureInPictureController?.stopPictureInPicture() }
        reconcile()
    }

    var pictureInPictureSupported: Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
    }

    func registerPictureInPictureLayer(_ layer: AVPlayerLayer) {
        guard pictureInPictureSupported else { return }
        if !pictureLayers.contains(where: { $0.layer === layer }) {
            pictureLayers.append(PictureLayerReference(layer))
        }
        selectPictureInPictureLayer()
    }

    private func selectPictureInPictureLayer() {
        guard pictureInPictureLayer == nil else { return }
        pictureLayers.removeAll { $0.layer == nil }
        guard let layer = pictureLayers.first?.layer,
              let pip = AVPictureInPictureController(playerLayer: layer) else { return }
        pip.delegate = self
        pictureInPictureLayer = layer
        pictureInPictureController = pip
        pictureInPicturePossibility = pip.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] pip, _ in
            Task { @MainActor [weak self, weak pip] in
                guard let self, let pip, self.pictureInPictureController === pip else { return }
                self.canStartPictureInPicture = pip.isPictureInPicturePossible
            }
        }
    }

    /// A PiP window can outlive the SwiftUI surface that opened it.
    func unregisterPictureInPictureLayer(_ layer: AVPlayerLayer) -> Bool {
        pictureLayers.removeAll { $0.layer == nil || $0.layer === layer }
        guard pictureInPictureLayer === layer else { return false }
        if pictureInPictureActive || isStartingPictureInPicture {
            detachedPictureInPictureLayer = layer
            return true
        }
        releasePictureInPictureSource()
        return false
    }

    private func releasePictureInPictureSource() {
        pictureInPicturePossibility = nil
        canStartPictureInPicture = false
        detachedPictureInPictureLayer?.player = nil
        detachedPictureInPictureLayer = nil
        pictureInPictureLayer = nil
        pictureInPictureController?.delegate = nil
        pictureInPictureController = nil
        selectPictureInPictureLayer()
    }

    func startPictureInPicture() {
        guard !isStartingPictureInPicture, let pictureInPictureController,
              pictureInPictureController.isPictureInPicturePossible else { return }
        isStartingPictureInPicture = true
        pictureInPictureController.startPictureInPicture()
    }

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor [weak self] in
            self?.didStartPictureInPicture()
        }
    }

    @MainActor
    private func didStartPictureInPicture() {
        isStartingPictureInPicture = false
        pictureInPictureActive = true
        player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        gate.setPictureInPictureActive(true)
        reconcile()
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor [weak self] in
            self?.didStopPictureInPicture()
        }
    }

    @MainActor
    private func didStopPictureInPicture() {
        isStartingPictureInPicture = false
        pictureInPictureActive = false
        player.audiovisualBackgroundPlaybackPolicy = .pauses
        gate.setPictureInPictureActive(false)
        if detachedPictureInPictureLayer != nil { releasePictureInPictureSource() }
        reconcile()
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in
            self?.didFailToStartPictureInPicture(message: message)
        }
    }

    @MainActor
    private func didFailToStartPictureInPicture(message: String) {
        isStartingPictureInPicture = false
        if detachedPictureInPictureLayer != nil { releasePictureInPictureSource() }
        PlaybackDebugLog.shared.record("video: PiP failed to start: \(message)", about: gate.trackId)
    }

    /// A surface asked to show a track: resolve only the one it needs, and only
    /// once. A nil side (an art track) or a failure is remembered for this
    /// track, so a body pass cannot turn into a request loop.
    private func reconcile() {
        if gate.enabled {
            let state = "surfaces=\(gate.surfaces) active=\(gate.active) track=\(gate.trackId ?? "none") mounted=\(mountedId ?? "none")"
            if state != lastGateLog {
                lastGateLog = state
                PlaybackDebugLog.shared.record("video gate: \(state)", about: gate.trackId)
            }
        }
        guard networkAllowed, gate.canRequest, let id = gate.trackId else {
            stop()
            return
        }
        if mountedId == id, resolvedId == id { return }
        if mountedId == id, resolveTask != nil { return }
        start(id)
    }

    private func start(_ id: String, forceRefresh: Bool = false) {
        if mountedId != id { retriedId = nil }
        resolveTask?.cancel()
        resolveTask = nil
        mountedId = id
        resolvedId = nil
        side = nil
        alternateVersion = nil
        presentedFrames.reset()
        preparing = true
        say(nil)
        controller.detach()

        if !forceRefresh, let prepared = preparedAhead, prepared.songId == id,
           Date().timeIntervalSince(prepared.saved) < Self.preparedLifetime {
            preparedAhead = nil
            preparing = false
            resolvedId = id
            side = prepared.side
            controller.attach(prepared.side, timeMap: prepared.map)
            PlaybackDebugLog.shared.record("video: using prepared video choice and alignment", about: id)
            prepareAhead()
            return
        }
        preparedAhead = nil

        let requestedTrack = hooks?.track()
        PlaybackDebugLog.shared.record(
            "video: resolving song=\(requestedTrack?.title ?? id) artist=\(requestedTrack?.artist ?? "") (forceRefresh=\(forceRefresh))",
            about: id
        )
        resolveTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if !Task.isCancelled, self.mountedId == id {
                    if self.acceptsResolution(for: id) { self.resolvedId = id }
                    self.resolveTask = nil
                    self.preparing = false
                }
            }
            do {
                let side = try await InnertubeStreamResolver.shared.resolveVideo(videoId: id, forceRefresh: forceRefresh)
                guard self.acceptsResolution(for: id) else { return }
                // The upload is itself a music video (and not a still image
                // posted as one): same file, same timeline.
                let sameFileIsPlayable = side.isAuthoritativeMusicVideo
                    ? side.qualifiesAsCounterpartVideo()
                    : side.qualifiesAsSearchVideo(isOfficialMusicVideo: false)
                if sameFileIsPlayable {
                    PlaybackDebugLog.shared.record("video: attaching the picture", about: id)
                    self.preparing = false
                    self.side = side
                    self.controller.attach(side)
                    self.prepareAhead()
                    return
                }
                // An art track (or a still picture): the music video is another
                // upload, with its own cut. Find it, check it is moving
                // picture, and map the song onto it.
                guard let track = self.hooks?.track() else { self.preparing = false; return }
                let candidates = await Self.findVideoVersions(videoId: id, track: track)
                guard self.acceptsResolution(for: id) else { return }
                var fallback: VideoVersion?
                for candidate in candidates.prefix(3) {
                    let videoSide = try await InnertubeStreamResolver.shared.resolveVideo(videoId: candidate.videoId)
                    guard self.acceptsResolution(for: id) else { return }
                    let isCounterpart = candidate.source == "counterpart"
                    let qualifies = isCounterpart
                        ? videoSide.qualifiesAsCounterpartVideo()
                        : videoSide.qualifiesAsSearchVideo(
                            isOfficialMusicVideo: candidate.type == "MUSIC_VIDEO_TYPE_OMV"
                        )
                    guard qualifies else {
                        if isCounterpart {
                            PlaybackDebugLog.shared.record(
                                "video: counterpart \(candidate.videoId) rejected (AVC/MP4=\(videoSide.isAVCInMP4), bitrate=\(videoSide.bitrate.map { String($0) } ?? "?") kbps, \(videoSide.kbpsPerMegapixel.map { String(format: "%.0f", $0) } ?? "?") kbps/MP)",
                                about: id
                            )
                        }
                        PlaybackDebugLog.shared.record(
                            "video: \(candidate.videoId) (\(candidate.type ?? "untyped")) is not moving picture; next", about: id
                        )
                        continue
                    }
                    if fallback == nil { fallback = candidate }
                    PlaybackDebugLog.shared.record(
                        "video: aligning \(requestedTrack?.title ?? id) by \(requestedTrack?.artist ?? "") with \(candidate.videoId) (\(candidate.type ?? "untyped"), \(candidate.durationText ?? "?"), source=\(candidate.source ?? "search"))",
                        about: id
                    )
                    let map = await VideoVersionAlignment.shared.map(songId: id, videoId: candidate.videoId)
                    guard self.acceptsResolution(for: id) else { return }
                    if let map, map.confident {
                        PlaybackDebugLog.shared.record(
                            "video: picture of \(candidate.videoId) for \(requestedTrack?.title ?? id) by \(requestedTrack?.artist ?? "") aligned: \(map.summary) min-window=\(String(format: "%.3f", map.minimumWindowSimilarity))",
                            about: id
                        )
                        self.preparing = false
                        self.side = videoSide
                        self.controller.attach(videoSide, timeMap: map)
                        self.prepareAhead()
                        return
                    }
                }
                self.preparing = false
                guard let fallback else {
                    PlaybackDebugLog.shared.record("video: no music video for this song", about: id)
                    self.say("No music video for this song")
                    self.prepareAhead()
                    self.side = nil
                    self.controller.detach()
                    return
                }
                // Different cuts use their own audio only when the listener
                // explicitly chooses that recording.
                PlaybackDebugLog.shared.record(
                    "video: \(fallback.videoId) does not align; keeping the song and offering the video version", about: id
                )
                self.alternateVersion = fallback
            } catch {
                PlaybackDebugLog.shared.record("video: resolve failed: \(error)", about: id)
                guard self.acceptsResolution(for: id) else { return }
                self.preparing = false
                self.side = nil
                self.controller.detach()
                self.say("The music video couldn’t be loaded")
            }
        }
    }

    private func acceptsResolution(for id: String) -> Bool {
        !Task.isCancelled && mountedId == id && gate.trackId == id && gate.canRequest && networkAllowed
    }

    /// The picture failed (usually an expired signed URL): ask once more,
    /// bypassing the shared cache, then let the artwork stay.
    func videoFailed() {
        PlaybackDebugLog.shared.record("video: the player failed", about: gate.trackId)
        guard gate.canRequest, let id = gate.trackId,
              mountedId == id, resolvedId == id, retriedId != id else { return }
        retriedId = id
        start(id, forceRefresh: true)
    }

    /// While this track plays, the next one's music video is found and lined
    /// up (the map is kept on disk), so a change of track shows its picture
    /// as soon as it loads instead of after the search and the alignment.
    private func prepareAhead() {
        guard gate.canRequest, let next = hooks?.next() else { return }
        // Not on the track change itself: its alignment would land on the blend.
        prepare(next, delay: 20)
    }

    /// A signed video URL lives for hours; a stale one is refreshed by the
    /// player-failure retry, so a prepared choice can be kept for a while.
    private static let preparedLifetime: TimeInterval = 20 * 60

    private func prepare(
        _ next: (videoId: String, title: String, artist: String, seconds: Double, durationText: String?),
        delay: Double
    ) {
        guard next.videoId != aheadId else { return }
        aheadId = next.videoId
        aheadTask?.cancel()
        aheadTask = Task(priority: .utility) { [weak self] in
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
            }
            let own = try? await InnertubeStreamResolver.shared.resolveVideo(videoId: next.videoId)
            if let own {
                let qualifies = own.isAuthoritativeMusicVideo
                    ? own.qualifiesAsCounterpartVideo()
                    : own.qualifiesAsSearchVideo(isOfficialMusicVideo: false)
                if qualifies {
                    await self?.rememberPrepared(songId: next.videoId, side: own, map: nil)
                    return
                }
            }
            let track = (title: next.title, artist: next.artist, seconds: next.seconds, durationText: next.durationText)
            for candidate in await Self.findVideoVersions(videoId: next.videoId, track: track).prefix(3) {
                guard !Task.isCancelled else { return }
                guard let side = try? await InnertubeStreamResolver.shared.resolveVideo(videoId: candidate.videoId) else { continue }
                let qualifies = candidate.source == "counterpart"
                    ? side.qualifiesAsCounterpartVideo()
                    : side.qualifiesAsSearchVideo(
                        isOfficialMusicVideo: candidate.type == "MUSIC_VIDEO_TYPE_OMV"
                    )
                guard qualifies else { continue }
                let map = await VideoVersionAlignment.shared.map(songId: next.videoId, videoId: candidate.videoId)
                PlaybackDebugLog.shared.record(
                    "video: lined up \(next.title) by \(next.artist) ahead with \(candidate.videoId): \(map?.confident == true ? "aligned" : "not aligned") map=\(map?.summary ?? "none") min-window=\(map.map { String(format: "%.3f", $0.minimumWindowSimilarity) } ?? "?")",
                    about: next.videoId
                )
                if map?.confident == true {
                    await self?.rememberPrepared(songId: next.videoId, side: side, map: map)
                    return
                }
            }
        }
    }

    private func rememberPrepared(songId: String, side: ResolvedVideoSide, map: VideoVersionAlignment.Map?) async {
        guard !Task.isCancelled, networkAllowed, aheadId == songId else { return }
        preparedAhead = PreparedVideo(songId: songId, side: side, map: map, saved: Date())
        // Only metadata is warmed. AVFoundation remains the sole video decoder,
        // and no GPU work is started for an offscreen upcoming item.
        if let string = side.url, let url = URL(string: string) {
            _ = try? await VideoIndexCache.shared.index(source: url, headers: side.headers)
        }
    }

    private func stop() {
        surfaceRelease?.cancel()
        surfaceRelease = nil
        aheadTask?.cancel()
        aheadTask = nil
        aheadId = nil
        if preparedAhead?.songId != gate.trackId { preparedAhead = nil }
        guard mountedId != nil else { return }
        resolveTask?.cancel()
        resolveTask = nil
        mountedId = nil
        resolvedId = nil
        side = nil
        alternateVersion = nil
        presentedFrames.reset()
        preparing = false
        say(nil)
        controller.detach()
    }

    private struct VideoVersion: Decodable {
        let videoId: String
        let title: String
        let durationText: String?
        let type: String?
        let source: String?
    }

    private static func findVideoVersions(
        videoId: String, track: (title: String, artist: String, seconds: Double, durationText: String?)
    ) async -> [VideoVersion] {
        await withCheckedContinuation { continuation in
            VideoVersionBridge.shared.find(
                videoId: videoId, title: track.title, artist: track.artist,
                durationText: track.durationText ?? (track.seconds > 0 ? QueueEntry.formatDuration(track.seconds) : nil),
                callback: VideoVersionAdapter { json, message in
                    if let message {
                        PlaybackDebugLog.shared.record("video: music-video search failed: \(message)", about: videoId)
                    }
                    let found = json.flatMap { try? JSONDecoder().decode([VideoVersion].self, from: Data($0.utf8)) } ?? []
                    continuation.resume(returning: found)
                }
            )
        }
    }
}

private final class VideoVersionAdapter: VideoVersionBridgeVideoVersionCallback {
    private let handler: (String?, String?) -> Void
    init(_ handler: @escaping (String?, String?) -> Void) { self.handler = handler }
    func onResult(json: String?, message: String?) { handler(json, message) }
}

/// Hosts the shared muted player over its artwork fallback. Opening another
/// pane changes the surface's visibility without replacing the audio session.
struct VideoSurface<Fallback: View>: View {
    var cornerRadius: CGFloat = 12
    var fillSlot = true
    var announcesLoading = false
    var presentation: Presentation = .letterbox
    var presented = true
    /// Both the artwork and picture use this mask in the edge-to-edge stage.
    /// Nil is used by hosts that never fade into the background.
    var fadesToBackdrop: Bool? = nil
    var controlsTopInset: CGFloat = 0
    var showsPictureControls = true
    @ViewBuilder var fallback: () -> Fallback

    enum Presentation {
        case letterbox
        case fill
        case card
    }

    @Environment(PlaybackController.self) private var controller
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("show_music_videos") private var showMusicVideos = false
    @AppStorage("video_over_cellular") private var videoOverCellular = false
    @State private var surfaceID = UUID()
    @State private var appeared = false
    @State private var registered = false
    @State private var theaterPresented = false

    private var playback: VideoPlayback { .shared }
    private var trackID: String? { controller.current?.videoId }

    private func caption(_ text: String, loading: Bool) -> some View {
        HStack(spacing: 6) {
            if loading {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "video.slash")
                    .font(.caption)
            }
            Text(text)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(10)
        .allowsHitTesting(false)
    }

    private func picture(_ source: VideoPictureIdentity, visible: Bool) -> some View {
        GeometryReader { geometry in
            let aspect = playback.videoAspect
            let size = presentation == .fill
                ? geometry.size
                : PlayerLayout.containedCanvasSize(bounds: geometry.size, aspect: aspect)
            ZStack {
                if presentation == .letterbox && fillSlot && visible { Color.black }
                VideoLayerView(
                    player: playback.player,
                    gravity: presentation == .fill ? .resizeAspectFill : .resizeAspect,
                    onDisplayChanged: { ready in
                        playback.reportFrame(on: surfaceID, picture: source, ready: ready)
                    }
                )
                .id(source)
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .shadow(color: presentation == .card ? .black.opacity(0.35) : .clear, radius: 20, y: 10)
                .opacity(visible ? 1 : 0)
                .animation(visible && !reduceMotion ? .easeOut(duration: 0.20) : nil, value: visible)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        // A previous track must disappear immediately; only verified frames
        // for the new item fade in over its cover.
        .transition(.identity)
    }

    @ViewBuilder
    private func visualContent(source: VideoPictureIdentity?, visible: Bool) -> some View {
        let content = ZStack {
            fallback()
                .opacity(presentation == .card && visible ? 0 : 1)
                .animation(visible && !reduceMotion ? .easeOut(duration: 0.20) : nil, value: visible)
            if let source {
                picture(source, visible: visible)
            }
        }
        .allowsHitTesting(false)
        if let fadesToBackdrop {
            content.mask {
                LinearGradient(
                    stops: [
                        .init(color: .white, location: 0),
                        .init(color: .white, location: 0.62),
                        .init(color: .white.opacity(fadesToBackdrop ? 0 : 1), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        } else {
            content
        }
    }

    private var pictureControls: some View {
        HStack(spacing: 8) {
            Button {
                theaterPresented = true
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .accessibilityLabel("Open video theater")
            }
            .help("Open Video Theater")
            if playback.pictureInPictureSupported {
                Button {
                    playback.startPictureInPicture()
                } label: {
                    Image(systemName: "pip.enter")
                        .accessibilityLabel("Start Picture in Picture")
                }
                .help("Picture in Picture")
                .disabled(!playback.canStartPictureInPicture)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(10)
        .padding(.top, presentation == .fill ? controlsTopInset : 0)
    }

    var body: some View {
        let active = registered && presented && showMusicVideos
        let source = active ? playback.picture(for: trackID) : nil
        let visible = source != nil && playback.isDisplayingVideo(for: trackID, on: surfaceID)
        visualContent(source: source, visible: visible)
            .overlay(alignment: presentation == .fill ? .topTrailing : .bottomTrailing) {
                if visible && showsPictureControls { pictureControls }
            }
            .overlay(alignment: .bottom) {
                if active && announcesLoading && !visible {
                    if playback.offersVideoVersion(for: trackID) {
                        Button("Play Video Version", systemImage: "film") {
                            playback.playAlternateVideo(for: trackID)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .padding(10)
                        .accessibilityIdentifier("player.musicVideoVersion")
                    } else if playback.preparing || source != nil {
                        caption(String(localized: "Loading music video"), loading: true)
                            .accessibilityIdentifier("player.musicVideoLoading")
                    } else if let notice = playback.notice {
                        caption(notice, loading: false)
                            .accessibilityIdentifier("player.musicVideoNotice")
                    }
                }
            }
        #if os(iOS)
        .fullScreenCover(isPresented: $theaterPresented) {
            VideoTheaterView(controller: controller)
        }
        #else
        .sheet(isPresented: $theaterPresented) {
            VideoTheaterView(controller: controller)
                .frame(minWidth: 900, minHeight: 560)
        }
        #endif
        .onAppear {
            appeared = true
            updateRegistration(presented)
        }
        .onDisappear {
            appeared = false
            updateRegistration(false)
        }
        .onChange(of: presented) { _, visible in
            if appeared { updateRegistration(visible) }
        }
        .onChange(of: showMusicVideos) { _, enabled in
            if registered || playback.pictureInPictureActive { playback.setEnabled(enabled) }
        }
        .onChange(of: NetworkQuality.shared.metered) { _, _ in
            if registered { playback.refreshNetworkPolicy() }
        }
        .onChange(of: videoOverCellular) { _, _ in
            if registered { playback.refreshNetworkPolicy() }
        }
        .onChange(of: playback.state) { _, state in
            if registered && state == .failed { playback.videoFailed() }
        }
    }

    private func updateRegistration(_ visible: Bool) {
        guard registered != visible else { return }
        registered = visible
        guard visible else {
            playback.clearFrame(on: surfaceID)
            playback.setSurfaceVisible(false, videoId: nil)
            return
        }
        playback.configure(
            clock: VideoClock(
                position: { controller.livePosition(at: Date()) },
                isPlaying: { controller.isPlaying },
                rate: { controller.effectivePlaybackRate }
            ),
            hooks: .init(
                track: { [controller] in
                    guard let entry = controller.current else { return nil }
                    let seconds = controller.duration > 0 ? controller.duration : entry.durationSeconds
                    return (entry.title, entry.artist, seconds, entry.durationText)
                },
                playVideoVersion: { [controller] id, durationText in
                    controller.playVideoVersion(videoId: id, durationText: durationText)
                },
                next: { [controller] in
                    guard let entry = controller.upNextEntry, let videoId = entry.videoId else { return nil }
                    return (videoId, entry.title, entry.artist, entry.durationSeconds, entry.durationText)
                }
            )
        )
        playback.setActive(scenePhase == .active)
        playback.refreshNetworkPolicy()
        playback.setEnabled(showMusicVideos)
        playback.setSurfaceVisible(true, videoId: trackID)
    }
}

@MainActor
final class VideoLayerCoordinator {
    private weak var watchedItem: AVPlayerItem?
    private var displayObservation: NSKeyValueObservation?
    private var report: ((Bool) -> Void)?

    func update(
        layer: AVPlayerLayer,
        player: AVPlayer,
        gravity: AVLayerVideoGravity,
        onDisplayChanged: @escaping (Bool) -> Void
    ) {
        if layer.videoGravity != gravity { layer.videoGravity = gravity }
        if layer.player !== player { layer.player = player }
        report = onDisplayChanged
        let item = player.currentItem
        guard displayObservation == nil || watchedItem !== item else { return }
        watchedItem = item
        displayObservation = nil
        guard let item else { return }
        displayObservation = layer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self, weak player, weak item] layer, _ in
            Task { @MainActor [weak self, weak player, weak item, weak layer] in
                guard let self, let layer, let player, let item,
                      self.watchedItem === item, player.currentItem === item,
                      layer.player === player else { return }
                self.report?(layer.isReadyForDisplay)
            }
        }
    }

    func dismantle(_ layer: AVPlayerLayer) {
        displayObservation = nil
        watchedItem = nil
        report = nil
        if !VideoPlayback.shared.unregisterPictureInPictureLayer(layer) {
            layer.player = nil
        }
    }
}

#if os(iOS)
struct VideoLayerView: UIViewRepresentable {
    let player: AVPlayer
    var gravity: AVLayerVideoGravity = .resizeAspect
    let onDisplayChanged: (Bool) -> Void

    func makeCoordinator() -> VideoLayerCoordinator { VideoLayerCoordinator() }
    func makeUIView(context: Context) -> VideoLayerHost {
        let view = VideoLayerHost()
        updateUIView(view, context: context)
        VideoPlayback.shared.registerPictureInPictureLayer(view.playerLayer)
        return view
    }
    func updateUIView(_ view: VideoLayerHost, context: Context) {
        context.coordinator.update(layer: view.playerLayer, player: player, gravity: gravity,
                                   onDisplayChanged: onDisplayChanged)
    }
    static func dismantleUIView(_ view: VideoLayerHost, coordinator: VideoLayerCoordinator) {
        coordinator.dismantle(view.playerLayer)
    }
}

final class VideoLayerHost: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
#else
struct VideoLayerView: NSViewRepresentable {
    let player: AVPlayer
    var gravity: AVLayerVideoGravity = .resizeAspect
    let onDisplayChanged: (Bool) -> Void

    func makeCoordinator() -> VideoLayerCoordinator { VideoLayerCoordinator() }
    func makeNSView(context: Context) -> VideoLayerHost {
        let view = VideoLayerHost()
        updateNSView(view, context: context)
        VideoPlayback.shared.registerPictureInPictureLayer(view.playerLayer)
        return view
    }
    func updateNSView(_ view: VideoLayerHost, context: Context) {
        context.coordinator.update(layer: view.playerLayer, player: player, gravity: gravity,
                                   onDisplayChanged: onDisplayChanged)
    }
    static func dismantleNSView(_ view: VideoLayerHost, coordinator: VideoLayerCoordinator) {
        coordinator.dismantle(view.playerLayer)
    }
}

final class VideoLayerHost: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }
}
#endif
