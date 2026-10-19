import SwiftUI

struct MiniTrafficCard: View {
    let points: [HistoryPoint]
    var onOpen: (() -> Void)? = nil

    /// One derivation per frame, not one per read: this card's footer and its
    /// two bar rows touched the buckets ten times, and each touch rebuilt a
    /// 2,000-entry sample array.
    @State private var sampleCache = TrafficSampleCache()
    /// Measured height of the plot area. The bars scale to whatever the card was
    /// stretched to, so extra row height becomes a taller chart rather than padding.
    @State private var plotHeight: CGFloat = 116

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
        Panel(padding: 20, fillsHeight: true) {
            VStack(alignment: .leading, spacing: 16) {
                header
                bars
                CardDivider()
                footer
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            PanelHeader(title: "近 7 天流量") {
                if let onOpen {
                    PanelLink(title: "流量趋势", action: onOpen)
                        .help("打开流量趋势")
                }
            }
            HStack(spacing: 18) {
                legend("下载", value: inboundTotal, color: Theme.series2)
                legend("上传", value: outboundTotal, color: Theme.accent)
                Spacer(minLength: 0)
            }
        }
    }

    private func legend(_ title: String, value: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(Theme.label)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(TrafficChartData.valueLabel(value))
                .font(Theme.number(12.5, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    private var bars: some View {
        VStack(spacing: 7) {
            ZStack(alignment: .bottom) {
                Rectangle()
                    .fill(Theme.hairline)
                    .frame(height: 1)
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(buckets) { bucket in
                        HStack(alignment: .bottom, spacing: 3) {
                            bar(height: barHeight(bucket.inbound), color: Theme.series2, highlighted: isToday(bucket.day))
                            bar(height: barHeight(bucket.outbound), color: Theme.accent, highlighted: isToday(bucket.day))
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .frame(height: plotHeight, alignment: .bottom)
            }
            // minHeight holds the chart at its original size when the card is not in a
            // row to fill — alone in a ScrollView the proposal is unbounded, and
            // without the floor the plot would collapse to nothing.
            .frame(minHeight: 116, maxHeight: .infinity, alignment: .bottom)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { plotHeight = $0 }
            HStack(spacing: 6) {
                ForEach(buckets) { bucket in
                    Text(dayLabel(bucket.day))
                        .font(.system(size: 10.5, weight: isToday(bucket.day) ? .semibold : .regular))
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
                .font(Theme.label)
                .foregroundStyle(.secondary)
            Text(value)
                .font(Theme.number(12.5, weight: .medium))
        }
    }

    /// Flat bars, rounded only at the top. The partial current day is drawn lighter
    /// so its short bar reads as "not over yet" rather than as a drop in traffic.
    private func bar(height: CGFloat, color: Color, highlighted: Bool) -> some View {
        UnevenRoundedRectangle(topLeadingRadius: 2.5, topTrailingRadius: 2.5, style: .continuous)
            .fill(color.opacity(highlighted ? 0.45 : 1))
            .frame(width: 9, height: height)
    }

    private func barHeight(_ value: Int) -> CGFloat {
        let ratio = Double(value) / Double(maxValue)
        return max(3, CGFloat(ratio) * plotHeight)
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