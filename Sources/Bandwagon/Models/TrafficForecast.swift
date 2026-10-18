import Foundation

/// Verdict on whether this cycle's quota will hold.
///
/// Derived from the burn rate in the traffic history rather than from a guessed
/// billing-cycle length, so it needs no assumption about when the cycle started —
/// only the reset date, the quota, and what was actually moved recently.
///
/// The daily average intentionally matches the mini card's "日均" figure: it is the
/// same seven-day window including the partial current day. That makes the two
/// numbers agree, at the cost of a slight optimistic bias before the day is over.
struct TrafficForecast: Equatable {
    enum Verdict: String {
        /// Comfortably on track to finish the cycle inside the quota.
        case safe
        /// Projected to only just reach the reset.
        case tight
        /// Projected to run out before the reset.
        case over
    }

    var verdict: Verdict
    /// Mean total transfer per day over the sampled window.
    var dailyAverageBytes: Int
    /// Days of traffic left at the current rate.
    var daysUntilExhausted: Double
    /// Days until the plan resets.
    var daysLeft: Double
    var remainingBytes: Int

    /// The conclusion in words. Health is never carried by colour alone.
    var headline: String {
        switch verdict {
        case .over:
            guard daysUntilExhausted > 0.5 else { return "套餐流量已用尽" }
            return "按最近 7 天速度，约 \(Self.dayText(daysUntilExhausted)) 后用尽；距重置还有 \(Self.dayText(daysLeft))"
        case .tight:
            return "按最近 7 天速度，刚好能撑到重置"
        case .safe:
            return "按最近 7 天速度，重置前不会超额"
        }
    }

    var detail: String {
        "日均 \(TrafficChartData.valueLabel(dailyAverageBytes))"
    }

    static func dayText(_ days: Double) -> String {
        if days >= 10 { return String(format: "%.0f 天", days) }
        return String(format: "%.1f 天", days)
    }

    /// Returns nil whenever the answer would be a guess: no quota, no reset date,
    /// or no history to measure a rate from.
    static func make(
        points: [HistoryPoint],
        usedBytes: Int?,
        quotaBytes: Int?,
        resetAt: Int?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> TrafficForecast? {
        guard let used = usedBytes, used > 0,
              let quota = quotaBytes, quota > 0,
              let reset = resetAt, reset > 0 else { return nil }

        let resetSeconds = reset > 1_000_000_000_000 ? Double(reset) / 1000 : Double(reset)
        let daysLeft = (resetSeconds - now.timeIntervalSince1970) / 86_400
        guard daysLeft > 0 else { return nil }

        let samples = TrafficChartData.samples(from: points)
        let days = TrafficChartData.trimmed(
            TrafficChartData.dailyBuckets(
                from: TrafficChartData.visible(samples, range: .week),
                calendar: calendar
            ),
            for: .week
        )
        guard !days.isEmpty else { return nil }

        var total = 0
        for day in days {
            let (withInbound, overflowInbound) = total.addingReportingOverflow(day.inbound)
            let (withOutbound, overflowOutbound) = withInbound.addingReportingOverflow(day.outbound)
            total = (overflowInbound || overflowOutbound) ? Int.max : withOutbound
        }
        let daily = total / days.count
        guard daily > 0 else { return nil }

        let remaining = max(0, quota - used)
        let daysUntilExhausted = Double(remaining) / Double(daily)

        // A little headroom before calling it "safe": being projected to land at
        // 99% of quota is not the same as being comfortable.
        let ratio = daysUntilExhausted / daysLeft
        let verdict: Verdict = ratio >= 1.15 ? .safe : (ratio >= 1.0 ? .tight : .over)

        return TrafficForecast(
            verdict: verdict,
            dailyAverageBytes: daily,
            daysUntilExhausted: daysUntilExhausted,
            daysLeft: daysLeft,
            remainingBytes: remaining
        )
    }
}
