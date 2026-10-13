import LakhasKit
import SwiftUI

extension AIError {
    /// Friendly, specific message for each failure (docs/design.md: errors say what to do).
    var messageKey: LocalizedStringKey {
        switch self {
        case .noKey: "ai.error.noKey"
        case .invalidKey: "ai.error.invalidKey"
        case .insufficientCredit: "ai.error.credit"
        case .rateLimited: "ai.error.rateLimited"
        case .modelNotFound: "ai.error.model"
        case .refused: "ai.error.refused"
        case .truncated: "ai.error.truncated"
        case .invalidOutput: "ai.error.invalidOutput"
        case .network: "ai.error.network"
        case .providerUnavailable: "ai.error.unavailable"
        case .badRequest: "ai.error.badRequest"
        case .dailyLimitReached: "ai.error.dailyLimit"
        }
    }
}

extension AppFormat {
    /// "$0.0005"-style estimate (small amounts keep 4 decimals).
    func cost(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(value < 0.01 ? 4 : 2)).locale(locale))
    }
}
