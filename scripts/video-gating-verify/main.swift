import Foundation

// The O9 picture gate, with fake surfaces and scene values.
//
// Two rules are easy to get wrong and both were: a surface leaving is not the
// scene going inactive, and a surface appearing on a track without a videoId
// must clear the previous one. This pins both, plus the switch and the last
// surface leaving.
//
// Run: scripts/check-video-gating.sh

var failures = 0
var checks = 0

func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    checks += 1
    if ok {
        print("  ok   \(label)\(detail.isEmpty ? "" : " — \(detail)")")
    } else {
        failures += 1
        print("  FAIL \(label)\(detail.isEmpty ? "" : " — \(detail)")")
    }
}

func videoSide(kbpsPerMegapixel: Double, musicVideoType: String?, width: Int = 1920, height: Int = 1080) -> ResolvedVideoSide {
    let bitrate = Int((kbpsPerMegapixel * 1000 * Double(width * height) / 1_000_000).rounded())
    return ResolvedVideoSide(
        url: "https://example.invalid/video",
        width: width,
        height: height,
        itag: 137,
        mimeType: "video/mp4",
        codecs: "avc1.640028",
        bitrate: bitrate,
        headers: [:],
        availableVideoHeights: [1080],
        hasNParameter: false,
        clientName: "test",
        profileId: "test",
        musicVideoType: musicVideoType
    )
}

let lowMotionOMV = videoSide(kbpsPerMegapixel: 120, musicVideoType: "MUSIC_VIDEO_TYPE_OMV")
check("a low-bitrate OMV qualifies for search", lowMotionOMV.qualifiesAsSearchVideo(isOfficialMusicVideo: true),
      "\(Int(lowMotionOMV.kbpsPerMegapixel ?? 0)) kbps/MP")

let lowBitrateNonOMV = videoSide(kbpsPerMegapixel: 120, musicVideoType: nil)
check("a low-bitrate non-OMV does not qualify for search",
      !lowBitrateNonOMV.qualifiesAsSearchVideo(isOfficialMusicVideo: false),
      "\(Int(lowBitrateNonOMV.kbpsPerMegapixel ?? 0)) kbps/MP")

let unknownTypeOMV = videoSide(kbpsPerMegapixel: 120, musicVideoType: nil)
check("a low-bitrate side qualifies when the search row identifies its OMV type",
      unknownTypeOMV.qualifiesAsSearchVideo(isOfficialMusicVideo: true),
      "\(Int(unknownTypeOMV.kbpsPerMegapixel ?? 0)) kbps/MP")

let staticOMV = videoSide(kbpsPerMegapixel: 30, musicVideoType: "MUSIC_VIDEO_TYPE_OMV")
check("a static OMV qualifies for neither search nor counterpart",
      !staticOMV.qualifiesAsSearchVideo(isOfficialMusicVideo: true) && !staticOMV.qualifiesAsCounterpartVideo(),
      "\(Int(staticOMV.kbpsPerMegapixel ?? 0)) kbps/MP")

let verticalOMV = videoSide(kbpsPerMegapixel: 120, musicVideoType: "MUSIC_VIDEO_TYPE_OMV", width: 1080, height: 1920)
check("an official vertical video qualifies and keeps its original aspect",
      verticalOMV.qualifiesAsSearchVideo(isOfficialMusicVideo: true) && verticalOMV.aspectRatio == 9.0 / 16.0)
let ambiguousVertical = videoSide(kbpsPerMegapixel: 120, musicVideoType: nil, width: 1080, height: 1920)
check("a vertical art upload still needs an authoritative video match",
      !ambiguousVertical.qualifiesAsSearchVideo(isOfficialMusicVideo: false))

var gate = VideoSurfaceState()
gate.setEnabled(true)

gate.surfaceAppeared(videoId: "A")
gate.surfaceAppeared(videoId: "A")
check("two surfaces on a video track allow a request", gate.canRequest && gate.surfaces == 2)

gate.surfaceDisappeared()
check("closing one surface keeps the other's picture", gate.canRequest, "surfaces \(gate.surfaces)")
check("a surface leaving does not change the scene state", gate.active)

gate.setActive(false)
check("a backgrounded app stops requests", !gate.canRequest)
gate.surfaceDisappeared()
check("the last surface leaving does not re-activate the scene", !gate.active && !gate.canRequest)
gate.setActive(true)
check("returning to the foreground with no surface still stops", !gate.canRequest)

gate.surfaceAppeared(videoId: "A")
gate.surfaceAppeared(videoId: nil)
check("a surface appearing on a file clears the previous video id",
      gate.trackId == nil && !gate.canRequest, "track \(gate.trackId ?? "nil")")

gate.setTrack("B")
check("a video track set explicitly allows a request", gate.canRequest)
gate.setEnabled(false)
check("the switch off stops requests", !gate.canRequest)
gate.setEnabled(true)
check("the switch on allows a request again", gate.canRequest)

gate.setTrack("")
check("an empty video id is not a request", !gate.canRequest)

var pipGate = VideoSurfaceState()
pipGate.setEnabled(true)
pipGate.surfaceAppeared(videoId: "pip-")
pipGate.setPictureInPictureActive(true)
pipGate.surfaceDisappeared()
pipGate.setActive(false)
check("an active PiP picture carries its own visible surface into the background", pipGate.canRequest)
pipGate.setTrack(nil)
check("a track without video clears a background PiP source", !pipGate.canRequest)
pipGate.setTrack("another-")
pipGate.setPictureInPictureActive(false)
check("closing PiP releases the last video request", !pipGate.canRequest)

var frames = VideoPresentedFrames()
let mainSurface = UUID()
let miniSurface = UUID()
let first = VideoPictureIdentity(trackID: "A", itemRevision: 1)
let retry = VideoPictureIdentity(trackID: "A", itemRevision: 2)
let next = VideoPictureIdentity(trackID: "B", itemRevision: 3)
check("an item without a decoded display frame keeps the artwork", !frames.displays(first, on: mainSurface))
frames.report(surface: miniSurface, picture: first, ready: true, current: first)
check("a mini-player frame cannot reveal the immersive stage", frames.displays(first) && !frames.displays(first, on: mainSurface))
frames.report(surface: mainSurface, picture: first, ready: true, current: first)
check("a new item always needs its own display frame", frames.displays(first, on: mainSurface) && !frames.displays(retry, on: mainSurface))
frames.report(surface: mainSurface, picture: retry, ready: true, current: retry)
frames.report(surface: mainSurface, picture: first, ready: false, current: retry)
check("stale first-frame notifications do not hide a replacement for the same song", frames.displays(retry, on: mainSurface))
frames.report(surface: mainSurface, picture: retry, ready: true, current: next)
check("a different song cannot inherit a ready frame", !frames.displays(next))
frames.remove(surface: mainSurface)
check("a removed surface leaves only the independently ready mini player", !frames.displays(retry) && frames.displays(first, on: miniSurface))
frames.reset()
check("closing the picture clears all frames", !frames.displays(first) && !frames.displays(nil))

print(failures == 0 ? "\nall \(checks) checks passed" : "\n\(failures) of \(checks) checks FAILED")
exit(failures == 0 ? 0 : 1)
