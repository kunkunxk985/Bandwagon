import Foundation

@main
struct TrafficChartRegression {
    static func main() {
        let base = 1_700_000_000
        let points = [
            HistoryPoint(t: (base + 14_400) * 1000, inbound: 3_221_225_472, out: 1_073_741_824),
            HistoryPoint(t: base, inbound: 1_073_741_824, out: 536_870_912),
            HistoryPoint(t: base + 7_200, inbound: 2_147_483_648, out: 268_435_456),
            HistoryPoint(t: nil, inbound: 99, out: 99),
        ]

        let samples = TrafficChartData.samples(from: points)
        guard samples.count == 3,
              samples.map(\.timestamp) == [base, base + 7_200, base + 14_400] else {
            fail("samples must normalize millisecond timestamps and sort chronologically")
        }

        let summary = TrafficChartData.summary(for: samples)
        guard summary.inboundTotal == 6_442_450_944,
              summary.outboundTotal == 1_879_048_192,
              summary.peak == 3_221_225_472,
              summary.combinedPeak == 4_294_967_296 else {
            fail("summary totals or peaks are incorrect")
        }

        let rangePoints = [
            TrafficSample(timestamp: base - 40 * 86_400, inbound: 1, outbound: 1),
            TrafficSample(timestamp: base - 8 * 86_400, inbound: 2, outbound: 2),
            TrafficSample(timestamp: base - 6 * 86_400, inbound: 3, outbound: 3),
            TrafficSample(timestamp: base, inbound: 4, outbound: 4),
        ]
        guard TrafficChartData.visible(rangePoints, range: .week).map(\.inbound) == [3, 4],
              TrafficChartData.visible(rangePoints, range: .month).map(\.inbound) == [2, 3, 4],
              TrafficChartData.visible(rangePoints, range: .all).count == 4 else {
            fail("time range filtering is incorrect")
        }

        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let weekTicks = TrafficChartData.axisDates(for: rangePoints, range: .week, calendar: utcCalendar)
        guard weekTicks.count >= 2,
              weekTicks.allSatisfy({
                  let parts = utcCalendar.dateComponents([.hour, .minute, .second], from: $0)
                  return parts.hour == 0 && parts.minute == 0 && parts.second == 0
              }) else {
            fail("7-day axis ticks must land on local midnight")
        }

        let dayPoints = [
            TrafficSample(timestamp: base, inbound: 1, outbound: 1),
            TrafficSample(timestamp: base + 86_400, inbound: 1, outbound: 1),
        ]
        let dayTicks = TrafficChartData.axisDates(for: dayPoints, range: .day, calendar: utcCalendar)
        guard dayTicks.count >= 4,
              dayTicks.allSatisfy({
                  let parts = utcCalendar.dateComponents([.hour, .minute, .second], from: $0)
                  return (parts.hour ?? -1) % 4 == 0 && parts.minute == 0 && parts.second == 0
              }) else {
            fail("24-hour axis ticks must use four-hour boundaries")
        }

        let allTicks = TrafficChartData.axisDates(for: rangePoints, range: .all, calendar: utcCalendar)
        guard !allTicks.isEmpty,
              allTicks.allSatisfy({ [1, 15].contains(utcCalendar.component(.day, from: $0)) }) else {
            fail("all-history ticks must use the first and fifteenth of a month")
        }

        let target = Date(timeIntervalSince1970: TimeInterval(base + 8_000))
        guard TrafficChartData.nearest(to: target, in: samples)?.timestamp == base + 7_200 else {
            fail("hover selection must resolve to the nearest sample")
        }

        guard TrafficChartData.valueLabel(1_073_741_824) == "1.00 GB",
              TrafficChartData.axisLabel(0) == "0" else {
            fail("traffic labels must expose readable units")
        }

        let hourlyStart = utcCalendar.date(
            from: DateComponents(year: 2024, month: 1, day: 2, hour: 10)
        )!
        let hourlySamples = [
            TrafficSample(timestamp: Int(hourlyStart.timeIntervalSince1970), inbound: 10, outbound: 1),
            TrafficSample(timestamp: Int(hourlyStart.timeIntervalSince1970) + 1_800, inbound: 20, outbound: 2),
            TrafficSample(timestamp: Int(hourlyStart.timeIntervalSince1970) + 3_600, inbound: 5, outbound: 3),
        ]
        let hourlyBuckets = TrafficChartData.hourlyBuckets(from: hourlySamples, calendar: utcCalendar)
        guard hourlyBuckets.count == 2,
              hourlyBuckets.map(\.inbound) == [30, 5],
              hourlyBuckets.map({ utcCalendar.component(.hour, from: $0.hourStart) }) == [10, 11] else {
            fail("same-day samples must aggregate into their actual hourly buckets")
        }

        let hourlySummary = TrafficChartData.summary(for: hourlyBuckets)
        guard hourlySummary.inboundTotal == 35,
              hourlySummary.outboundTotal == 6,
              hourlySummary.peak == 30,
              hourlySummary.combinedPeak == 33 else {
            fail("24-hour summary must report aggregated hourly totals and peak")
        }

        let cache = TrafficSampleCache()
        // Same calendar day in UTC and common runner timezones (base+7_200 crossed UTC midnight).
        let sameDay = 1_704_067_200 // 2024-01-01 00:00:00 UTC
        let originalPoints = [
            HistoryPoint(t: sameDay, inbound: 10, out: 1),
            HistoryPoint(t: sameDay + 3_600, inbound: 20, out: 2),
        ]
        let changedPoints = [
            HistoryPoint(t: sameDay, inbound: 10, out: 1),
            HistoryPoint(t: sameDay + 3_600, inbound: 80, out: 2),
        ]
        let originalBuckets = cache.buckets(for: originalPoints, range: .week)
        let changedBuckets = cache.buckets(for: changedPoints, range: .week)
        guard originalBuckets.first?.inbound == 30,
              changedBuckets.first?.inbound == 90 else {
            fail("bucket cache must invalidate when same-count sample values change")
        }
        guard let stableID = changedBuckets.first?.id,
              cache.buckets(for: changedPoints, range: .week).first?.id == stableID else {
            fail("bucket identity must remain stable across reads")
        }

        // A rolling 7×86_400s window starts mid-day, so daily aggregation yields one
        // extra partial leading bucket. Every surface that reports a range must trim
        // to the same nominal count, or the mini card and the trend chart disagree.
        let weekWindow = (0..<8).map { offset in
            TrafficSample(timestamp: base - (7 - offset) * 86_400, inbound: 10, outbound: 4)
        }
        let untrimmedWeek = TrafficChartData.dailyBuckets(from: weekWindow, calendar: utcCalendar)
        let trimmedWeek = TrafficChartData.trimmed(untrimmedWeek, for: .week)
        guard untrimmedWeek.count == 8,
              trimmedWeek.count == 7,
              trimmedWeek == Array(untrimmedWeek.suffix(7)),
              TrafficChartData.trimmed(untrimmedWeek, for: .all).count == 8 else {
            fail("7-day buckets must trim to seven days while full history stays untrimmed")
        }

        let weekBuckets = trimmedWeek.map(TrafficBucket.day)
        let weekSummary = TrafficChartData.summary(for: weekBuckets)
        guard weekSummary.inboundTotal == 70,
              weekSummary.outboundTotal == 28,
              weekSummary.peak == 10,
              weekSummary.combinedPeak == 14 else {
            fail("chart summary must be derived from the same trimmed buckets it draws")
        }

        // Merging (not dropping) oversized histories must keep every byte counted.
        var bulky: [HistoryPoint] = []
        var expectedIn = 0
        var expectedOut = 0
        for index in 0..<6_000 {
            let inbound = (index % 7) * 1_048_576
            let outbound = (index % 5) * 524_288
            expectedIn += inbound
            expectedOut += outbound
            bulky.append(HistoryPoint(t: base + index * 300, inbound: inbound, out: outbound, cpu: 1))
        }
        let folded = BWHClient.merged(bulky, limit: 1_500)
        let foldedIn = folded.reduce(0) { $0 + ($1.inbound ?? 0) }
        let foldedOut = folded.reduce(0) { $0 + ($1.out ?? 0) }
        guard folded.count == 1_500,
              folded.first?.t == base + 3 * 300,
              folded.last?.t == base + 5_999 * 300,
              foldedIn == expectedIn,
              foldedOut == expectedOut else {
            fail("history merging must bound point count while preserving totals")
        }

        // The memoising cache must be correct first, then cheap: many reads of one
        // frame's buckets return identical data, and a changed point array must
        // invalidate it. A view that reads its buckets many times per body is
        // what made the app feel laggy, so the speedup is part of the contract.
        let memo = TrafficSampleCache()
        let repeated = (0..<9).map { _ in memo.buckets(for: points, range: .week) }
        guard repeated.allSatisfy({ $0.map(\.inbound) == repeated[0].map(\.inbound) }) else {
            fail("repeated cache reads within one frame must agree")
        }
        // Mutate a point that survives normalization — the fixture's last entry
        // has a nil timestamp and is dropped before any bucketing.
        var changed = points
        changed[1] = HistoryPoint(
            t: changed[1].t,
            inbound: (changed[1].inbound ?? 0) + 500_000_000,
            out: changed[1].out,
            cpu: changed[1].cpu
        )
        let cached = memo.buckets(for: points, range: .week)
        let refreshed = memo.buckets(for: changed, range: .week)
        guard cached.map(\.inbound) != refreshed.map(\.inbound) else {
            fail("cache must invalidate when the point array changes")
        }

        let bulkyPoints = (0..<2_000).map { index in
            HistoryPoint(t: base + index * 300, inbound: 4_000_000 + index, out: 3_000_000 + index, cpu: 1)
        }
        let timed = TrafficSampleCache()
        _ = timed.buckets(for: bulkyPoints, range: .week)   // warm
        let passes = 40
        let start = DispatchTime.now()
        var sink = 0
        for _ in 0..<passes {
            for _ in 0..<9 {
                sink &+= timed.buckets(for: bulkyPoints, range: .week).count
            }
        }
        let perPass = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e6 / Double(passes)
        let uncachedStart = DispatchTime.now()
        for _ in 0..<passes {
            for _ in 0..<9 {
                sink &+= legacyBucketCount(bulkyPoints)
            }
        }
        let uncachedPerPass = Double(DispatchTime.now().uptimeNanoseconds - uncachedStart.uptimeNanoseconds) / 1e6 / Double(passes)
        // 16.7 ms is one 60 Hz frame. Nine reads of a 2,000-point history used to
        // exceed it, which is the visible stutter.
        guard perPass * 10 < uncachedPerPass else {
            fail("memoised buckets must be far cheaper than re-deriving them (cached \(perPass) ms vs \(uncachedPerPass) ms)")
        }
        print(String(format: "nine reads of 2,000 points: %.2f ms -> %.3f ms (%.0fx)", uncachedPerPass, perPass, uncachedPerPass / max(perPass, 0.000_001)))
        _ = sink

        print("PASS traffic chart ranges, totals, peak, hover, units, cache invalidation, stable identity, range trimming, merge folding, and memoised per-frame cost")
    }

    /// What a view read before the memoising cache: one full sample derivation
    /// per access, then trim. Kept as the regression's cost baseline.
    private static func legacyBucketCount(_ points: [HistoryPoint]) -> Int {
        let visible = TrafficChartData.visible(TrafficChartData.samples(from: points), range: .week)
        return TrafficChartData.trimmed(TrafficChartData.buckets(from: visible, range: .week), for: .week).count
    }

    private static func fail(_ message: String) -> Never {
        print("FAIL \(message)")
        exit(1)
    }
}
