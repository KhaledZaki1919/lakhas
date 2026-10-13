import Foundation
import SwiftData

/// One AI request, for the local usage counter and cost estimate (ADR-020). Stays on device.
@Model
public final class UsageRecord {
    public var id: UUID
    public var date: Date
    public var dayKey: String
    public var providerRaw: String
    public var model: String
    public var featureRaw: String
    public var inputTokens: Int
    public var outputTokens: Int
    public var success: Bool
    /// USD, from `PriceTable` at the time of the request; nil when the model has no price.
    public var estimatedCost: Double?

    public init(event: AIUsageEvent, date: Date = .now, estimatedCost: Double?, calendar: Calendar = .current) {
        id = UUID()
        self.date = date
        dayKey = DayKey.make(date, calendar: calendar)
        providerRaw = event.provider.rawValue
        model = event.model
        featureRaw = event.feature.rawValue
        inputTokens = event.usage?.inputTokens ?? 0
        outputTokens = event.usage?.outputTokens ?? 0
        success = event.success
        self.estimatedCost = estimatedCost
    }

    public var feature: AIFeature { AIFeature(rawValue: featureRaw) ?? .text }
}

public struct UsageSummary: Equatable, Sendable {
    public let requests: Int
    public let inputTokens: Int
    public let outputTokens: Int
    /// Sum of known estimates; `hasUnpricedRequests` tells whether some had no price.
    public let estimatedCost: Double
    public let hasUnpricedRequests: Bool

    public init(_ records: [UsageRecord]) {
        let counted = records.filter { $0.feature != .connectionTest }
        requests = counted.count
        inputTokens = counted.reduce(0) { $0 + $1.inputTokens }
        outputTokens = counted.reduce(0) { $0 + $1.outputTokens }
        estimatedCost = counted.compactMap(\.estimatedCost).reduce(0, +)
        hasUnpricedRequests = counted.contains { $0.estimatedCost == nil && ($0.inputTokens + $0.outputTokens) > 0 }
    }
}
