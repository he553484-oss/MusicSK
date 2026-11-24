import Foundation

guard let apple = AppearanceProfileValues.preset("apple"),
      let original = AppearanceProfileValues.preset("original"),
      let oled = AppearanceProfileValues.preset("oled") else { fatalError("missing profile") }
precondition(apple.background == "dynamic" && apple.animated)
precondition(original.background == "original" && original.blur == 64 && original.brightness == 0)
precondition(oled.background == "black" && !oled.animated && oled.material == "opaque")
precondition(oled.motion == "reduced" && !oled.haptics && !oled.transitions)
precondition(apple.motion == "automatic" && apple.haptics)
precondition(AppearanceProfileValues.preset("custom") == nil)
precondition(AppearanceProfileValues.preset("unknown") == nil)
precondition(AppearanceInstallDefaults.shouldApplyAppleProfile(onboarded: false, signedIn: false, hasQueue: false, hasAppearancePreference: false))
precondition(!AppearanceInstallDefaults.shouldApplyAppleProfile(onboarded: true, signedIn: false, hasQueue: false, hasAppearancePreference: false))
precondition(!AppearanceInstallDefaults.shouldApplyAppleProfile(onboarded: false, signedIn: true, hasQueue: false, hasAppearancePreference: false))
precondition(!AppearanceInstallDefaults.shouldApplyAppleProfile(onboarded: false, signedIn: false, hasQueue: true, hasAppearancePreference: false))
precondition(!AppearanceInstallDefaults.shouldApplyAppleProfile(onboarded: false, signedIn: false, hasQueue: false, hasAppearancePreference: true))
print("PASS appearance profile defaults, OLED and custom preservation")
