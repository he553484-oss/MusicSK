import Foundation

guard let apple = AppearanceProfileValues.preset("apple"),
      let original = AppearanceProfileValues.preset("original"),
      let oled = AppearanceProfileValues.preset("oled") else { fatalError("missing profile") }
precondition(apple.background == "dynamic" && apple.animated)
precondition(original.background == "original" && original.blur == 64 && original.brightness == 0)
precondition(oled.background == "black" && !oled.animated && oled.material == "opaque")
precondition(AppearanceProfileValues.preset("custom") == nil)
precondition(AppearanceProfileValues.preset("unknown") == nil)
print("PASS appearance profile defaults, OLED and custom preservation")
