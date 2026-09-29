import SwiftUI

struct MiniTrafficCard: View {
    let points: [HistoryPoint]
    var onOpen: (() -> Void)? = nil

    /// One derivation per frame, not one per read: this card's footer and its
    /// two bar rows touched the buckets ten times, and each touch rebuilt a
    /// 2,000-entry sample array.
    @State private var sampleCache = TrafficSampleCache()

    private var buckets: [DailyBucket] {
        sampleCache.buckets(for: points, range: .week).compactMap { bucket in
            guard case .day(let day) = bucket else { return nil }
            return day
        }
    }

    private var inboundTotal: Int {
        buckets.reduce(0) { saturatingAdd($0, $1.inbound) }
    }

    private var outboundTotal: Int {
        buckets.reduce(0) { saturatingAdd($0, $1.outbound) }
    }

    private var maxValue: Int {
        max(1, buckets.map { max($0.inbound, $0.outbound) }.max() ?? 0)
    }

    private var dayTotal: Int {
        buckets.reduce(0) { saturatingAdd($0, saturatingAdd($1.inbound, $1.outbound)) }
    }

    private var todayTotal: Int? {
        guard let last = buckets.last, Calendar.current.isDateInToday(last.day) else { return nil }
        return saturatingAdd(last.inbound, last.outbound)
    }

    private var dailyAverage: Int {
        guard !buckets.isEmpty else { return 0 }
        return dayTotal / buckets.count
    }

    var body: some View {
        GlassCard(padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                header
                bars
                CardDivider()
                footer
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                if let onOpen {
                    Button(action: onOpen) {
                        HStack(spacing: 5) {
                            Text("近 7 天流量")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.primary)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("打开流量趋势")
                } else {
                    Text("近 7 天流量")
                        .font(.system(size: 15, weight: .semibold))
                }
                Spacer()
            }
            HStack(spacing: 8) {
                legend("下载", value: inboundTotal, color: .teal)
                Spacer(minLength: 4)
                legend("上传", value: outboundTotal, color: Theme.accent)
            }
        }
    }

    private func legend(_ title: String, value: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.95), color.opacity(0.55)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 14, height: 3.5)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(TrafficChartData.valueLabel(value))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    private var bars: some View {
        VStack(spacing: 7) {
            ZStack(alignment: .bottom) {
                Rectangle()
                    .fill(Color.primary.opacity(0.07))
                    .frame(height: 1)
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(buckets) { bucket in
                        HStack(alignment: .bottom, spacing: 5) {
                            bar(height: barHeight(bucket.inbound), color: .teal, highlighted: isToday(bucket.day))
                            bar(height: barHeight(bucket.outbound), color: Theme.accent, highlighted: isToday(bucket.day))
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .frame(height: 116, alignment: .bottom)
            }
            HStack(spacing: 6) {
                ForEach(buckets) { bucket in
                    Text(dayLabel(bucket.day))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(isToday(bucket.day) ? AnyShapeStyle(Color.primary) : AnyShapeStyle(Color.secondary))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 18) {
            stat(
                title: todayTotal != nil ? "今日" : "最新一天",
                value: TrafficChartData.valueLabel(todayTotal ?? lastDayTotal)
            )
            Spacer(minLength: 8)
            stat(title: "日均", value: TrafficChartData.valueLabel(dailyAverage))
        }
    }

    private var lastDayTotal: Int {
        guard let last = buckets.last else { return 0 }
        return saturatingAdd(last.inbound, last.outbound)
    }

    private func stat(title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
    }

    private func bar(height: CGFloat, color: Color, highlighted: Bool) -> some View {
        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [color.opacity(0.98), color.opacity(0.55)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 15, height: height)
            .shadow(color: highlighted ? color.opacity(0.35) : Color.clear, radius: 4, x: 0, y: 1)
    }

    private func barHeight(_ value: Int) -> CGFloat {
        let ratio = Double(value) / Double(maxValue)
        return max(4, CGFloat(ratio) * 116)
    }

    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }

    private func dayLabel(_ date: Date) -> String {
        // The newest bar covers a partial day. Left as a bare date the short bar
        // reads as a collapse in traffic, so it is named for what it actually is.
        if isToday(date) { return "今日" }
        return DateFormats.string("M/d", date)
    }

    private func saturatingAdd(_ lhs: Int, _ rhs: Int) -> Int {
        let (result, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int.max : result
    }
}