import Foundation

/// The gating state for O9's picture, kept pure so its two easy-to-get-wrong
/// rules have a check: a surface leaving must not change the scene's active
/// state, and a surface appearing on a track without a video must clear the
/// previous track's id rather than keep playing it over the new song.
struct VideoSurfaceState: Equatable {
    private(set) var enabled = false
    private(set) var surfaces = 0
    private(set) var active = true
    private(set) var pictureInPictureActive = false
    private(set) var trackId: String?

    /// Whether a video-side request is allowed at all.
    var canRequest: Bool {
        enabled && (surfaces > 0 || pictureInPictureActive) &&
            (active || pictureInPictureActive) && !(trackId ?? "").isEmpty
    }

    mutating func setEnabled(_ on: Bool) {
        enabled = on
    }

    /// Scene phase only; no surface may write this.
    mutating func setActive(_ on: Bool) {
        active = on
    }

    mutating func setPictureInPictureActive(_ active: Bool) {
        pictureInPictureActive = active
    }

    mutating func setTrack(_ id: String?) {
        trackId = id
    }

    mutating func surfaceAppeared(videoId: String?) {
        surfaces += 1
        // Always assign: a local file or an addon track has no videoId, and
        // keeping the previous one would draw its video over this song.
        trackId = videoId
    }

    mutating func surfaceDisappeared() {
        surfaces = max(0, surfaces - 1)
        // `active` belongs to the scene phase, not to whichever surface left:
        // closing Now Playing while the pill still shows must not stop it.
    }
}

/// AVPlayer is shared, while each surface has its own display readiness. Item
/// revisions also change on a retry for the same track.
struct VideoPictureIdentity: Hashable {
    let trackID: String
    let itemRevision: UInt
}

struct VideoPresentedFrames: Equatable {
    private var frames: [UUID: VideoPictureIdentity] = [:]

    mutating func report(surface: UUID, picture: VideoPictureIdentity, ready: Bool,
                         current: VideoPictureIdentity?) {
        guard picture == current else { return }
        if ready {
            frames[surface] = picture
        } else if frames[surface] == picture {
            frames.removeValue(forKey: surface)
        }
    }

    mutating func remove(surface: UUID) { frames.removeValue(forKey: surface) }

    mutating func reset() { frames.removeAll() }

    func displays(_ picture: VideoPictureIdentity?, on surface: UUID? = nil) -> Bool {
        guard let picture else { return false }
        if let surface { return frames[surface] == picture }
        return frames.values.contains(picture)
    }
}
