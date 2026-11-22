import Foundation

func appearance(
    _ distance: Int, timed: Bool = true, synced: Bool = true, active: Bool = false,
    browsing: Bool = false, blurEnabled: Bool = true
) -> LyricRowLook {
    LyricRowLook.forLine(
        timed: timed, synced: synced, active: active, distance: distance,
        compact: true, browsing: browsing, blurEnabled: blurEnabled
    )
}

let active = appearance(0, active: true)
precondition(active.alpha == 1 && active.blur == 0)

let inactive = (1...5).map { appearance($0) }
for (near, far) in zip(inactive, inactive.dropFirst()) {
    precondition(near.alpha > far.alpha && near.blur < far.blur)
}
precondition(appearance(100) == inactive.last)
precondition(appearance(3, browsing: true).alpha > appearance(3).alpha)
precondition(appearance(3, browsing: true).blur < appearance(3).blur)
precondition(appearance(3, browsing: true).blur > 0)
precondition(appearance(3, blurEnabled: false).blur == 0)
precondition(appearance(3, timed: false).blur == 0)
precondition(appearance(3, synced: false).blur == 0)

let positions: [Int64] = [200, 1_000, 1_250, 1_500, 1_750, 2_000, 2_400]
let progress = positions.map { LyricWordProgress.at($0, start: 1_000, end: 2_000) }
precondition(progress == [0, 0, 0.25, 0.5, 0.75, 1, 1])
precondition(LyricWordProgress.at(1_200, start: 1_000, end: 1_000) == 0)
precondition(LyricWordProgress.at(0, start: .min, end: .max) == 0.5)
precondition(LyricWordProgress.glowEnvelope(0) == 0 && LyricWordProgress.glowEnvelope(1) == 0)
precondition(LyricWordProgress.glowEnvelope(0.25) < LyricWordProgress.glowEnvelope(0.5))
precondition(abs(LyricWordProgress.glowEnvelope(0.25) - LyricWordProgress.glowEnvelope(0.75)) < 0.000001)

print("PASS lyric focus separation, manual reading, blur preference, held word progress and glow")
