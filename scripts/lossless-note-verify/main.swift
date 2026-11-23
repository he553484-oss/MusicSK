import Foundation
precondition(LosslessFallbackNote.reason(requested: false, sourceVerifiedLossless: false, connected: false, canSearchAlternative: false) == nil)
precondition(LosslessFallbackNote.reason(requested: true, sourceVerifiedLossless: true, connected: false, canSearchAlternative: false) == nil)
precondition(LosslessFallbackNote.reason(requested: true, sourceVerifiedLossless: false, connected: false, canSearchAlternative: true) == .offline)
precondition(LosslessFallbackNote.reason(requested: true, sourceVerifiedLossless: false, connected: true, canSearchAlternative: false) == .noEnabledAlternative)
precondition(LosslessFallbackNote.reason(requested: true, sourceVerifiedLossless: false, connected: true, canSearchAlternative: true) == .sourceNotVerified)
print("Lossless fallback reasons passed")
