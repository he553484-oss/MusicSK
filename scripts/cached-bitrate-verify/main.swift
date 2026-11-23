import Foundation
precondition(CachedBitrate.estimateKbps(bytes: 4_000_000, durationSeconds: 200, complete: true) == 160)
precondition(CachedBitrate.estimateKbps(bytes: 4_000_000, durationSeconds: 200, complete: false) == nil)
precondition(CachedBitrate.estimateKbps(bytes: 0, durationSeconds: 200, complete: true) == nil)
precondition(CachedBitrate.estimateKbps(bytes: 4_000_000, durationSeconds: nil, complete: true) == nil)
precondition(CachedBitrate.estimateKbps(bytes: 4_000_000, durationSeconds: 0, complete: true) == nil)
precondition(CachedBitrate.estimateKbps(bytes: Int64.max, durationSeconds: 1, complete: true) == nil)
print("Cached bitrate estimate checks passed")
if CommandLine.arguments.count > 1 {
    let attrs = try FileManager.default.attributesOfItem(atPath: CommandLine.arguments[1])
    let bytes = (attrs[.size] as! NSNumber).int64Value
    guard let estimate = CachedBitrate.estimateKbps(bytes: bytes, durationSeconds: 6, complete: true) else {
        fatalError("complete Opus fixture should have an estimate")
    }
    precondition(estimate > 80, "whole-file estimate should not use the quiet opening")
    print("Six-second Opus cache estimate: \(estimate) kbps")
}
