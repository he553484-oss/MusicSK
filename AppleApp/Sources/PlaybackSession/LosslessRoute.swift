import Foundation

/// Route policy shared by lossless upgrades and exact-output eligibility.
enum LosslessRoute {
    static func permitsLossless(routeKind: String, bluetoothCodec: String? = nil) -> Bool {
        let route = routeKind.lowercased()
        guard route.contains("bluetooth") else { return true }
        guard let codec = bluetoothCodec?.lowercased() else { return false }
        // AAC, SBC, aptX-HD and LDAC are lossy. Only an explicitly reported
        // lossless codec can opt back in; current AV route APIs do not report it.
        return codec.contains("aptx lossless")
    }

    static func cappedLosslessSampleRate(routeKind: String, requested: Double?) -> Double? {
        guard let requested, requested > 0 else { return nil }
        guard routeKind.lowercased().contains("airplay") else { return requested }
        return min(max(requested, 44_100), 48_000)
    }

    static func permitsBitPerfect(routeKind: String, sourceIsLossless: Bool, integerPcm: Bool) -> Bool {
        guard sourceIsLossless, integerPcm else { return false }
        let route = routeKind.lowercased()
        return !route.isEmpty && !route.contains("bluetooth") && !route.contains("airplay")
    }

    /// A category or configuration notification can repeat a device change.
    /// Retain the opportunity until recovery completes, then consume it once.
    struct UpgradeOpportunity {
        private var currentKind = ""
        private var pending = false

        mutating func observe(kind: String) {
            let normalized = kind.lowercased()
            // Hardware may briefly report no port while establishing a route.
            guard !normalized.isEmpty, normalized != currentKind else { return }
            if !LosslessRoute.permitsLossless(routeKind: normalized) {
                pending = false
            } else if currentKind.contains("bluetooth") {
                pending = true
            }
            currentKind = normalized
        }

        mutating func consume() -> Bool {
            guard pending else { return false }
            pending = false
            return true
        }
    }
}
