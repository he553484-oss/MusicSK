import Foundation
struct SearchHitDTO {
    var videoId: String?; var title: String; var subtitle: String?; var durationText: String?
    init(kind: String, videoId: String?, title: String, subtitle: String?, thumbnailUrl: String?, durationText: String?, albumName: String?, browseId: String?, browseType: String?, artistId: String?, albumId: String?, isVideo: Bool, setVideoId: String?) { self.videoId = videoId; self.title = title; self.subtitle = subtitle; self.durationText = durationText }
}
struct QueueEntry { var title: String; var artist: String; var durationSeconds: Double }
enum TrackMatch {
    struct Target { var title: String; var artist: String; var durationSec: Int? }
    struct Candidate { var title: String; var artist: String; var durationText: String? }
    static func bestIndex(in candidates: [Candidate], target: Target) -> Int? { nil }
    static func seconds(of text: String?) -> Int? { nil }
}
