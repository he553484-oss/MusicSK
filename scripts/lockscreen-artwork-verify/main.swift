import Foundation

func allowed(enabled: Bool = true, wifiOnly: Bool = false, wifi: Bool = false,
             canvas: Bool = true, constrained: Bool = false, reduced: Bool = false,
             low: Bool = false, autoplay: Bool = true, hot: Bool = false) -> Bool {
    LockScreenArtworkPolicy.allowsAnimation(enabled: enabled, wifiOnly: wifiOnly, usesWiFi: wifi,
        canvasAllowed: canvas, constrained: constrained, reduceMotion: reduced, lowPower: low,
        autoPlay: autoplay, thermalSerious: hot)
}
precondition(allowed())
precondition(!allowed(enabled: false))
precondition(!allowed(wifiOnly: true, wifi: false))
precondition(allowed(wifiOnly: true, wifi: true))
precondition(!allowed(canvas: false) && !allowed(constrained: true))
precondition(!allowed(reduced: true) && !allowed(low: true))
precondition(!allowed(autoplay: false) && !allowed(hot: true))
print("PASS lock screen artwork respects network, accessibility, power and thermal policy")
