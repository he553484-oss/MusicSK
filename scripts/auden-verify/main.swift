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
