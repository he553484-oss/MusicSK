import Foundation

/// Explains only facts known at resolution time; never promises that a
/// lossless copy exists or that a later lookup will succeed.
enum LosslessFallbackNote {
    enum Reason: Equatable { case offline, noEnabledAlternative, sourceNotVerified }

    static func reason(requested: Bool, sourceVerifiedLossless: Bool,
                       connected: Bool, canSearchAlternative: Bool) -> Reason? {
        guard requested, !sourceVerifiedLossless else { return nil }
        if !connected { return .offline }
        if !canSearchAlternative { return .noEnabledAlternative }
        return .sourceNotVerified
    }
}
