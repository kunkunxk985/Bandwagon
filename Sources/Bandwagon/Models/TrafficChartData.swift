import Foundation

enum TrafficRange: String, CaseIterable, Identifiable {
    case day = "24 小时"
    case week = "7 天"
    case month = "30 天"
    case all = "全部"

    var id: String { rawValue }

    var seconds: Int? {
        switch self {
        case .day: 86_400
        case .week: 7 * 86_400
        case .month: 30 * 86_400
        case .all: nil
        }
    }
}

struct TrafficSample: Identifiable, Equatable, Hashable {
    let timestamp: Int
    let inbound: Int
    let outbound: Int

    var id: Int { timestamp }
    var date: Date { Date(timeIntervalSince1970: TimeInterval(timestamp)) }
    var peak: Int { max(inbound, outbound) }
}

struct DailyBucket: Identifiable, Equatable, Hashable {
    let day: Date
    var inbound: Int
    var outbound: Int
    var id: Date { day }
}

struct HourlyBucket: Identifiable, Equatable, Hashable {
    let hourStart: Date
    var inbound: Int
    var outbound: Int
    var id: Date { hourStart }
}

struct MonthlyBucket: Identifiable, Equatable, Hashable {
    let month: Date
    var inbound: Int
    var outbound: Int
    var id: Date { month }
}

struct TrafficBucketID: Hashable {
    let kind: Int
    let date: Date
}

enum TrafficBucket: Identifiable, Hashable {
    case hour(HourlyBucket)
    case day(DailyBucket)
    case month(MonthlyBucket)

    var id: TrafficBucketID {
        switch self {
        case .hour(let bucket): TrafficBucketID(kind: 0, date: bucket.hourStart)
        case .day(let bucket): TrafficBucketID(kind: 1, date: bucket.day)
        case .month(let bucket): TrafficBucketID(kind: 2, date: bucket.month)
        }
    }

    var date: Date {
        switch self {
        case .hour(let bucket): bucket.hourStart
        case .day(let bucket): bucket.day
        case .month(let bucket): bucket.month
        }
    }

    var inbound: Int {
        switch self {
        case .hour(let bucket): bucket.inbound
        case .day(let bucket): bucket.inbound
        case .month(let bucket): bucket.inbound
        }
    }

    var outbound: Int {
        switch self {
        case .hour(let bucket): bucket.outbound
        case .day(let bucket): bucket.outbound
        case .month(let bucket): bucket.outbound
        }
    }
}

/// Memoizes the raw-sample derivation, which is the expensive part of drawing a
/// traffic view: it builds a dictionary of every point and sorts it.
///
/// SwiftUI re-evaluates a computed property on *every read*, so a view that
/// touches its buckets nine times per body rebuilt that array nine times per
/// frame. Keyed on the point array, so a refresh that changes the data still
/// recomputes, and every read within one frame is free.
final class TrafficSampleCache {
    private var cachedPoints: [HistoryPoint]?
    private var cachedSamples: [TrafficSample] = []
    private var cachedBuckets: [TrafficRange: [TrafficBucket]] = [:]

    func samples(from points: [HistoryPoint]) -> [TrafficSample] {
        if let cachedPoints, cachedPoints == points { return cachedSamples }
        cachedSamples = TrafficChartData.samples(from: points)
        cachedPoints = points
        cachedBuckets = [:]
        return cachedSamples
    }

    func visible(_ points: [HistoryPoint], range: TrafficRange) -> [TrafficSample] {
        TrafficChartData.visible(samples(from: points), range: range)
    }

    /// The exact buckets a view draws, so a summary row and the plotted series
    /// can never disagree, and so the range's totals stay trimmed to the same
    /// nominal bucket count the chart shows.
    func buckets(for points: [HistoryPoint], range: TrafficRange) -> [TrafficBucket] {
        // Re-key first. Reading the range cache before this would serve buckets
        // built from the previous point array, because only `samples(from:)`
        // knows whether the data changed.
        _ = samples(from: points)
        if let cached = cachedBuckets[range] { return cached }
        let inRange = TrafficChartData.visible(cachedSamples, range: range)
        let trimmed = TrafficChartData.trimmed(
            TrafficChartData.buckets(from: inRange, range: range),
            for: range
        )
        cachedBuckets[range] = trimmed
        return trimmed
    }

    func axisDates(for points: [HistoryPoint], range: TrafficRange) -> [Date] {
        TrafficChartData.axisDates(for: visible(points, range: range), range: range)
    }
}

struct TrafficSummary: Equatable {
    let inboundTotal: Int
    let outboundTotal: Int
    /// Highest single-direction bucket. This is what the chart's y-axis has to
    /// cover, because the plotted series are one direction each.
    let peak: Int
    /// Highest combined (download + upload) bucket. The summary row reports this
    /// instead of `peak`, so the "busiest bucket" figure is on the same footing as
    /// the daily average — otherwise a single-direction peak can read as *lower*
    /// than the combined average, which looks like a bug.
    let combinedPeak: Int
}

enum TrafficChartData {
    static func samples(from points: [HistoryPoint]) -> [TrafficSample] {
        var byTimestamp: [Int: TrafficSample] = [:]
        for point in points {
            guard let rawTimestamp = point.t, rawTimestamp > 0 else { continue }
            let timestamp = rawTimestamp > 1_000_000_000_000 ? rawTimestamp / 1000 : rawTimestamp
            byTimestamp[timestamp] = TrafficSample(
                timestamp: timestamp,
                inbound: max(0, point.inbound ?? 0),
                outbound: max(0, point.out ?? 0)
            )
        }
        return byTimestamp.values.sorted { $0.timestamp < $1.timestamp }
    }

    static func visible(_ samples: [TrafficSample], range: TrafficRange) -> [TrafficSample] {
        guard let seconds = range.seconds, let newest = samples.last?.timestamp else { return samples }
        let cutoff = newest - seconds
        return samples.filter { $0.timestamp >= cutoff }
    }

    /// Dispatches to the aggregation the range is drawn with. One entry point so
    /// a cache and a view can never disagree about which bucketing a range uses.
    static func buckets(from samples: [TrafficSample], range: TrafficRange) -> [TrafficBucket] {
        switch range {
        case .day:
            return hourlyBuckets(from: samples).map(TrafficBucket.hour)
        case .week, .month:
            return dailyBuckets(from: samples).map(TrafficBucket.day)
        case .all:
            return monthlyBuckets(from: samples).map(TrafficBucket.month)
        }
    }

    static func dailyBuckets(from samples: [TrafficSample], calendar: Calendar = .current) -> [DailyBucket] {
        guard let first = samples.first, let last = samples.last else { return [] }
        var calendar = calendar
        calendar.locale = Locale(identifier: "zh_CN")

        var buckets: [Date: DailyBucket] = [:]
        var current = calendar.startOfDay(for: first.date)
        let endDay = calendar.startOfDay(for: last.date)

        while current <= endDay {
            buckets[current] = DailyBucket(day: current, inbound: 0, outbound: 0)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current), next > current else { break }
            current = next
        }

        for sample in samples {
            let day = calendar.startOfDay(for: sample.date)
            if var bucket = buckets[day] {
                bucket.inbound = saturatingAdd(bucket.inbound, sample.inbound)
                bucket.outbound = saturatingAdd(bucket.outbound, sample.outbound)
                buckets[day] = bucket
            }
        }

        return buckets.values.sorted { $0.day < $1.day }
    }

    static func hourlyBuckets(from samples: [TrafficSample], calendar: Calendar = .current) -> [HourlyBucket] {
        guard let first = samples.first, let last = samples.last else { return [] }
        var calendar = calendar
        calendar.locale = Locale(identifier: "zh_CN")

        var buckets: [Date: HourlyBucket] = [:]
        guard var current = calendar.dateInterval(of: .hour, for: first.date)?.start,
              let endHour = calendar.dateInterval(of: .hour, for: last.date)?.start else {
            return []
        }

        while current <= endHour {
            buckets[current] = HourlyBucket(hourStart: current, inbound: 0, outbound: 0)
            guard let next = calendar.date(byAdding: .hour, value: 1, to: current), next > current else { break }
            current = next
        }

        for sample in samples {
            guard let hour = calendar.dateInterval(of: .hour, for: sample.date)?.start,
                  var bucket = buckets[hour] else { continue }
            bucket.inbound = saturatingAdd(bucket.inbound, sample.inbound)
            bucket.outbound = saturatingAdd(bucket.outbound, sample.outbound)
            buckets[hour] = bucket
        }

        return buckets.values.sorted { $0.hourStart < $1.hourStart }
    }

    static func monthlyBuckets(from samples: [TrafficSample], calendar: Calendar = .current) -> [MonthlyBucket] {
        guard let first = samples.first, let last = samples.last else { return [] }
        var calendar = calendar
        calendar.locale = Locale(identifier: "zh_CN")

        var buckets: [DateComponents: MonthlyBucket] = [:]
        let current = calendar.startOfDay(for: first.date)
        let endDay = calendar.startOfDay(for: last.date)
        let currentYearMonth = calendar.dateComponents([.year, .month], from: current)
        guard var month = calendar.date(from: currentYearMonth) else { return [] }

        while month <= endDay {
            let components = calendar.dateComponents([.year, .month], from: month)
            buckets[components] = MonthlyBucket(month: month, inbound: 0, outbound: 0)
            guard let next = calendar.date(byAdding: .month, value: 1, to: month), next > month else { break }
            month = next
        }

        for sample in samples {
            let components = calendar.dateComponents([.year, .month], from: sample.date)
            if var bucket = buckets[components] {
                bucket.inbound = saturatingAdd(bucket.inbound, sample.inbound)
                bucket.outbound = saturatingAdd(bucket.outbound, sample.outbound)
                buckets[components] = bucket
            }
        }

        return buckets.values.sorted { $0.month < $1.month }
    }

    static func nearest(to date: Date, in samples: [TrafficSample]) -> TrafficSample? {
        let target = Int(date.timeIntervalSince1970)
        return samples.min {
            abs($0.timestamp - target) < abs($1.timestamp - target)
        }
    }

    /// Nominal bucket count for a range. A rolling window (exactly 7×86_400s back
    /// from the newest sample) starts mid-day, so aggregation yields one extra
    /// partial leading bucket. That bucket is real traffic, but it has no axis
    /// label and makes the chart's total disagree with the mini card's.
    static func bucketLimit(for range: TrafficRange) -> Int? {
        switch range {
        case .day: 24
        case .week: 7
        case .month: 30
        case .all: nil
        }
    }

    /// Trims to the nominal bucket count so every surface that reports a range
    /// sums the same buckets. `nil` limit (`.all`) keeps the full history.
    static func trimmed<T>(_ buckets: [T], for range: TrafficRange) -> [T] {
        guard let limit = bucketLimit(for: range), buckets.count > limit else { return buckets }
        return Array(buckets.suffix(limit))
    }

    /// Totals derived from the same buckets the chart draws, so the summary row
    /// can never disagree with the plotted series.
    static func summary(for buckets: [TrafficBucket]) -> TrafficSummary {
        var inboundTotal = 0
        var outboundTotal = 0
        var peak = 0
        var combinedPeak = 0
        for bucket in buckets {
            inboundTotal = saturatingAdd(inboundTotal, bucket.inbound)
            outboundTotal = saturatingAdd(outboundTotal, bucket.outbound)
            peak = max(peak, max(bucket.inbound, bucket.outbound))
            combinedPeak = max(combinedPeak, saturatingAdd(bucket.inbound, bucket.outbound))
        }
        return TrafficSummary(
            inboundTotal: inboundTotal,
            outboundTotal: outboundTotal,
            peak: peak,
            combinedPeak: combinedPeak
        )
    }

    static func axisDates(
        for samples: [TrafficSample],
        range: TrafficRange,
        calendar inputCalendar: Calendar = .current
    ) -> [Date] {
        guard let first = samples.first, let last = samples.last else { return [] }
        var calendar = inputCalendar
        calendar.locale = Locale(identifier: "zh_CN")
        let start = first.date
        let end = last.date
        guard start < end else { return [start] }

        var ticks: [Date] = []

        func appendSequence(from firstTick: Date, component: Calendar.Component, step: Int) {
            var tick = firstTick
            while tick <= end {
                if tick >= start { ticks.append(tick) }
                guard let next = calendar.date(byAdding: component, value: step, to: tick), next > tick else { break }
                tick = next
            }
        }

        switch range {
        case .day:
            var tick = calendar.dateInterval(of: .hour, for: start)?.start ?? start
            let hour = calendar.component(.hour, from: tick)
            let hoursToGrid = (4 - hour % 4) % 4
            if hoursToGrid > 0 {
                tick = calendar.date(byAdding: .hour, value: hoursToGrid, to: tick) ?? tick
            }
            if tick < start {
                tick = calendar.date(byAdding: .hour, value: 4, to: tick) ?? tick
            }
            appendSequence(from: tick, component: .hour, step: 4)

        case .week:
            var tick = calendar.startOfDay(for: start)
            if tick < start {
                tick = calendar.date(byAdding: .day, value: 1, to: tick) ?? tick
            }
            appendSequence(from: tick, component: .day, step: 1)

        case .month:
            var tick = calendar.startOfDay(for: start)
            let weekday = calendar.component(.weekday, from: tick)
            let daysToMonday = (2 - weekday + 7) % 7
            tick = calendar.date(byAdding: .day, value: daysToMonday, to: tick) ?? tick
            if tick < start {
                tick = calendar.date(byAdding: .weekOfYear, value: 1, to: tick) ?? tick
            }
            appendSequence(from: tick, component: .weekOfYear, step: 1)

        case .all:
            let span = end.timeIntervalSince(start)
            let startComponents = calendar.dateComponents([.year, .month], from: start)
            guard var month = calendar.date(from: startComponents) else { return [start, end] }
            while month <= end {
                let days = span <= 180 * 86_400 ? [1, 15] : [1]
                let monthComponents = calendar.dateComponents([.year, .month], from: month)
                for day in days {
                    var components = monthComponents
                    components.day = day
                    if let candidate = calendar.date(from: components), candidate >= start, candidate <= end {
                        ticks.append(candidate)
                    }
                }
                guard let next = calendar.date(byAdding: .month, value: 1, to: month), next > month else { break }
                month = next
            }
        }

        if ticks.isEmpty { return [start, end] }
        if ticks.count == 1 {
            return ticks[0] == start ? [ticks[0], end] : [start, ticks[0]]
        }
        return ticks
    }

    static func summary(for samples: [TrafficSample]) -> TrafficSummary {
        let inboundTotal = samples.reduce(into: 0) { total, sample in
            total = saturatingAdd(total, sample.inbound)
        }
        let outboundTotal = samples.reduce(into: 0) { total, sample in
            total = saturatingAdd(total, sample.outbound)
        }
        let peak = samples.map(\.peak).max() ?? 0
        let combinedPeak = samples.map { saturatingAdd($0.inbound, $0.outbound) }.max() ?? 0
        return TrafficSummary(
            inboundTotal: inboundTotal,
            outboundTotal: outboundTotal,
            peak: peak,
            combinedPeak: combinedPeak
        )
    }

    static func summary(for buckets: [HourlyBucket]) -> TrafficSummary {
        let inboundTotal = buckets.reduce(into: 0) { total, bucket in
            total = saturatingAdd(total, bucket.inbound)
        }
        let outboundTotal = buckets.reduce(into: 0) { total, bucket in
            total = saturatingAdd(total, bucket.outbound)
        }
        let peak = buckets.map { max($0.inbound, $0.outbound) }.max() ?? 0
        let combinedPeak = buckets.map { saturatingAdd($0.inbound, $0.outbound) }.max() ?? 0
        return TrafficSummary(
            inboundTotal: inboundTotal,
            outboundTotal: outboundTotal,
            peak: peak,
            combinedPeak: combinedPeak
        )
    }

    static func valueLabel(_ bytes: Int) -> String {
        let value = Double(max(0, bytes))
        let gib = 1_073_741_824.0
        let mib = 1_048_576.0
        let kib = 1_024.0
        if value >= gib { return String(format: "%.2f GB", value / gib) }
        if value >= mib { return String(format: "%.1f MB", value / mib) }
        if value >= kib { return String(format: "%.1f KB", value / kib) }
        return "\(Int(value)) B"
    }

    static func axisLabel(_ bytes: Double) -> String {
        let value = max(0, bytes)
        let gib = 1_073_741_824.0
        let mib = 1_048_576.0
        let kib = 1_024.0
        if value >= gib { return String(format: value >= 10 * gib ? "%.0f GB" : "%.1f GB", value / gib) }
        if value >= mib { return String(format: value >= 10 * mib ? "%.0f MB" : "%.1f MB", value / mib) }
        if value >= kib { return String(format: "%.0f KB", value / kib) }
        return value == 0 ? "0" : "\(Int(value)) B"
    }

    private static func saturatingAdd(_ lhs: Int, _ rhs: Int) -> Int {
        let (result, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int.max : result
    }
}
