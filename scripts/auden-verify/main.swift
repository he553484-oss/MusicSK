import Foundation

func check(_ value: @autoclosure () -> Bool, _ message: String) {
    if !value() {
        FileHandle.standardError.write(Data("FAIL \(message)\n".utf8))
        exit(1)
    }
    print("PASS \(message)")
}

check(MusicAppearance(rawValue: "original") == .original, "preserved original preference")
check(MusicAppearance(rawValue: "auden") == .auden, "Auden preference round-trips")
check(MusicAppearance(rawValue: "unknown") == nil, "unknown preference uses default at the binding")

var fold = AudenDockPolicy()
var folded = false
for offset in [3, 6, 10, 14, 18, 22, 26, 30, 36, 44] {
    folded = fold.update(offset: Double(offset), folded: folded)
}
check(folded, "small continuous scroll events fold the dock")
folded = fold.update(offset: 39, folded: folded)
check(folded, "small reversal keeps the dock stable")
folded = fold.update(offset: 29, folded: folded)
check(!folded, "accumulated reverse motion expands the dock")
check(!fold.update(offset: 0, folded: true), "return to the top expands the dock")

let reordered = AudenLibrarySection.ordered("downloads,obsolete,songs,downloads")
check(Array(reordered.prefix(2)) == [.downloads, .songs], "saved library order survives duplicates and unknown entries")
check(Set(reordered) == Set(AudenLibrarySection.allCases), "new library destinations remain accessible")

let phone = AudenPlayerGeometry.sleeveFrame(in: CGSize(width: 393, height: 420))
check(phone == CGRect(x: 30, y: 8, width: 333, height: 333), "portrait art observes the 30 point gutter")
let compact = AudenPlayerGeometry.sleeveFrame(in: CGSize(width: 393, height: 160))
check(compact.maxY == 156 && compact.width == compact.height, "short stages fit a centered square without clipping")
check(AudenPlayerGeometry.sleeveFrame(in: CGSize(width: 800, height: 800)).width == 560, "wide sleeve observes the reference cap")
check(AudenPlayerGeometry.sleeveFrame(in: CGSize(width: CGFloat.infinity, height: 800)).isEmpty, "invalid geometry is contained")

let portraitTransport = AudenPlayerMetrics.transport(compact: false)
let compactTransport = AudenPlayerMetrics.transport(compact: true)
check(portraitTransport.glyph == 74 && portraitTransport.touch == 84 && portraitTransport.skip == 53,
      "portrait transport matches PlayerControls")
check(compactTransport.glyph == 58 && compactTransport.touch == 76 && compactTransport.skip == 44,
      "compact transport matches PlayerControls")
check(AudenPlayerMetrics.fraction(15, maximum: 60) == 0.25 &&
      AudenPlayerMetrics.fraction(-1, maximum: 60) == 0 &&
      AudenPlayerMetrics.fraction(61, maximum: 60) == 1 &&
      AudenPlayerMetrics.fraction(1, maximum: .nan) == 0, "scrubbing stays inside the media duration")
check(AudenPlayerMetrics.feather(width: 5) == 2.5 && AudenPlayerMetrics.feather(width: 200) == 40,
      "Automix feather fits short ranges and caps long ones")
check(AudenPlayerMetrics.queueProgress(pull: 90, travel: 300) == 0.3 &&
      AudenPlayerMetrics.queueProgress(pull: 400, travel: 300) == 1 &&
      AudenPlayerMetrics.queueProgress(pull: -200, travel: 300) == 0 &&
      AudenPlayerMetrics.queueProgress(pull: 40, travel: 0) == 0, "queue reveal follows bounded movement")
check(AudenPlayerMetrics.opensQueue(progress: 0.3, upwardVelocity: 0) &&
      !AudenPlayerMetrics.opensQueue(progress: 0.29, upwardVelocity: 0) &&
      AudenPlayerMetrics.opensQueue(progress: 0.1, upwardVelocity: 450) &&
      !AudenPlayerMetrics.opensQueue(progress: 0.9, upwardVelocity: -450),
      "queue respects Auden release and reversal thresholds")
