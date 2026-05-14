import Foundation

/// Formatted reset-duration value for the menu bar duration label.
/// Sibling to `MenuBarPercentageDisplay`; both display types are driven by the
/// same underlying `UsageQuota` but render different facets.
public struct MenuBarDurationDisplay: Sendable, Equatable {
    public let status: QuotaStatus
    public let quota: UsageQuota

    /// Computed (not stored) so the countdown reflects the current wall clock
    /// every time SwiftUI evaluates the menu bar label, instead of freezing at
    /// the value captured when this display was constructed.
    public var text: String { quota.compactResetTime ?? "—" }

    public init(
        quota: UsageQuota,
        burnRateWarningEnabled: Bool = false,
        burnRateThreshold: Double = 1.5
    ) {
        self.quota = quota
        self.status = burnRateWarningEnabled
            ? quota.paceAwareStatus(burnRateThreshold: burnRateThreshold)
            : quota.status
    }
}
