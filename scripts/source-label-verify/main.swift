import Foundation

let requested = "saavn:example"
precondition(PlaybackSourceLabel.name(origin: nil, source: requested, isLocal: false) == nil)
precondition(PlaybackSourceLabel.name(origin: "jiosaavn", source: requested, isLocal: false) == "JioSaavn")
precondition(PlaybackSourceLabel.name(origin: "youtube", source: requested, isLocal: false) == "YouTube")
precondition(PlaybackSourceLabel.name(origin: "substitute", source: requested, isLocal: false) == "Alternative source")
precondition(PlaybackSourceLabel.name(origin: "cache", source: requested, isLocal: false) == "Cached audio")
print("PASS requested and effective source labels remain distinct")
