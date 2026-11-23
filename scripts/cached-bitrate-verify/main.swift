import Foundation
precondition(CachedBitrate.estimateKbps(bytes: 4_000_000, durationSeconds: 200, complete: true) == 160)
precondition(CachedBitrate.estimateKbps(bytes: 4_000_000, durationSeconds: 200, complete: false) == nil)
precondition(CachedBitrate.estimateKbps(bytes: 0, durationSeconds: 200, complete: true) == nil)
precondition(CachedBitrate.estimateKbps(bytes: 4_000_000, durationSeconds: nil, complete: true) == nil)
precondition(CachedBitrate.estimateKbps(bytes: 4_000_000, durationSeconds: 0, complete: true) == nil)
precondition(CachedBitrate.estimateKbps(bytes: Int64.max, durationSeconds: 1, complete: true) == nil)
print("Cached bitrate estimate checks passed")
