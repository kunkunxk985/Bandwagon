import Charts
import SwiftUI

struct TrafficHistoryChart: View {
    let points: [HistoryPoint]

    @State private var range: TrafficRange = .week
    @State private var hoveredDate: Date?
    @State private var sampleCache = TrafficSampleCache()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var visibleBuckets: [TrafficBucket] {
        sampleCache.buckets(for: points, range: range)
    }

    /// A read of the same buckets, not a fresh derivation: the cache above keys
    /// on the point array, so a refresh still recomputes.
    private var allSamples: [TrafficSample] {
        sampleCache.samples(from: points)
    }

    private var visibleSamples: [TrafficSample] {
        sampleCache.visible(points, range: range)
    }

    /// Derived from the very buckets the chart draws, so the summary row can never
    /// disagree with the plotted series about a range's totals.
    private var summary: TrafficSummary {
        TrafficChartData.summary(for: visibleBuckets)
    }

    private var yMaximum: Double {
        max(1, Double(summary.peak) * 1.18)
    }

    private var xAxisDates: [Date] {
        sampleCache.axisDates(for: points, range: range)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            summaryRow
            focusRow
            chart
        }
        .onChange(of: range) {
            hoveredDate = nil
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 20) {
            PanelHeader(title: "流量趋势", subtitle: chartHint)
            Spacer()
            Picker("时间范围", selection: $range) {
                ForEach(TrafficRange.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 300)
        }
    }

    private var summaryRow: some View {
        HStack(spacing: 0) {
            TrafficMetric(
                title: "区间下载",
                value: TrafficChartData.valueLabel(summary.inboundTotal),
                color: Theme.series2
            )
            StatDivider(height: 38)
            TrafficMetric(
                title: "区间上传",
                value: TrafficChartData.valueLabel(summary.outboundTotal),
                color: Theme.accent
            )
            StatDivider(height: 38)
            // Combined, not single-direction: this tile sits beside the average, and
            // the average is combined too. Reporting a single-direction peak here
            // made it read as smaller than the average, which looks broken.
            TrafficMetric(
                title: "单日/时段峰值",
                value: TrafficChartData.valueLabel(summary.combinedPeak),
                color: nil
            )
            StatDivider(height: 38)
            TrafficMetric(
                title: averageTitle,
                value: TrafficChartData.valueLabel(perBucketAverage),
                color: nil
            )
        }
    }

    /// Mean combined transfer per bucket. Replaces a tile that only echoed the range
    /// picker back at the reader.
    private var perBucketAverage: Int {
        guard !visibleBuckets.isEmpty else { return 0 }
        let combined = summary.inboundTotal.addingReportingOverflow(summary.outboundTotal)
        guard !combined.overflow else { return 0 }
        return combined.partialValue / visibleBuckets.count
    }

    private var averageTitle: String {
        switch range {
        case .day: return "时段均量"
        case .week, .month: return "日均"
        case .all: return "月均"
        }
    }

    @ViewBuilder
    private var focusRow: some View {
        if let bucket = focusedBucket {
            FocusCard(bucket: bucket, range: range)
        }
    }

    private var chart: some View {
        Chart {
            // Stacked, not overlaid. A relay moves nearly equal traffic each way, so
            // as two lines the series sat on top of each other and conveyed nothing.
            // The silhouette is now the combined transfer, download as the lower band.
            ForEach(visibleBuckets) { bucket in
                AreaMark(
                    x: .value("时间", bucket.date),
                    yStart: .value("基线", 0),
                    yEnd: .value("下载", Double(bucket.inbound))
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Theme.series2.opacity(0.14), Theme.series2.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.linear)

                AreaMark(
                    x: .value("时间", bucket.date),
                    yStart: .value("基线", 0),
                    yEnd: .value("上传", Double(bucket.outbound))
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Theme.accent.opacity(0.10), Theme.accent.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.linear)
            }

            ForEach(visibleBuckets) { bucket in
                LineMark(
                    x: .value("时间", bucket.date),
                    y: .value("下载", Double(bucket.inbound)),
                    series: .value("方向", "下载")
                )
                .foregroundStyle(Theme.series2)
                .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.linear)

                LineMark(
                    x: .value("时间", bucket.date),
                    y: .value("上传", Double(bucket.outbound)),
                    series: .value("方向", "上传")
                )
                .foregroundStyle(Theme.accent)
                .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round, dash: [5, 3]))
                .interpolationMethod(.linear)

                if let hoveredDate, abs(hoveredDate.timeIntervalSince(bucket.date)) < 1 {
                    RuleMark(x: .value("选中时间", bucket.date))
                        .foregroundStyle(Color.primary.opacity(0.34))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                    PointMark(
                        x: .value("时间", bucket.date),
                        y: .value("下载", Double(bucket.inbound))
                    )
                    .symbolSize(36)
                    .foregroundStyle(Theme.series2)

                    PointMark(
                        x: .value("时间", bucket.date),
                        y: .value("上传", Double(bucket.outbound))
                    )
                    .symbolSize(36)
                    .foregroundStyle(Theme.accent)
                }
            }
        }
        .chartYScale(domain: 0...yMaximum)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                    .foregroundStyle(Theme.hairline)
                if let bytes = value.as(Double.self) {
                    AxisValueLabel {
                        Text(TrafficChartData.axisLabel(bytes))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: xAxisDates) { _ in
                AxisTick(stroke: StrokeStyle(lineWidth: 1))
                    .foregroundStyle(Theme.border)
            }
        }
        .chartPlotStyle { plot in
            plot.overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Theme.border)
                    .frame(height: 1)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    xAxisLabels(proxy: proxy, geometry: geometry)
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case let .active(location):
                                guard let anchor = proxy.plotFrame else { return }
                                let frame = geometry[anchor]
                                guard frame.contains(location) else {
                                    hoveredDate = nil
                                    return
                                }
                                let plotX = location.x - frame.origin.x
                                guard let date: Date = proxy.value(atX: plotX) else { return }
                                // Snaps to a bucket, so the overwhelming majority
                                // of mouse moves are a no-op write. Assigning on
                                // every pixel of movement re-rendered the chart,
                                // the axis labels and the summary row at the
                                // pointer's frame rate.
                                let nearest = nearestBucketDate(to: date)
                                if hoveredDate != nearest { hoveredDate = nearest }
                            case .ended:
                                hoveredDate = nil
                            }
                        }
                }
            }
        }
        .padding(.trailing, 10)
        .frame(height: 300)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: range)
    }


    private func axisDate(_ date: Date) -> String {
        switch range {
        case .day:
            return DateFormats.string("HH:mm", date)
        case .week, .month:
            // The newest bucket is a partial day. Left as a bare date it reads as a
            // collapse in traffic, so it is named for what it actually is.
            if Calendar.current.isDateInToday(date) { return "今日" }
            return DateFormats.string(range == .week ? "M/d E" : "M/d", date)
        case .all:
            return DateFormats.string("yyyy/M", date)
        }
    }

    /// 自绘横轴标签：本机 Charts 会把系统 AxisValueLabel 的左缘钉在刻度上（整字宽右偏、
    /// 最右标签被裁切），故弃用系统标签；用 plotFrame 原点 + position(forX:)（绘图区局部坐标）
    /// 精确居中。右缘不按半个标签宽夹紧——绘图区最右刻度几乎就是框右缘，夹紧会把最右标签
    /// 拉左半个字宽；改由 Chart 上的尾随留白（.padding(.trailing, 10)）给最右标签腾整字位置。
    @ViewBuilder
    private func xAxisLabels(proxy: ChartProxy, geometry: GeometryProxy) -> some View {
        if let anchor = proxy.plotFrame {
            let frame = geometry[anchor]
            ForEach(xAxisDates, id: \.self) { date in
                if let x = proxy.position(forX: date) {
                    Text(axisDate(date))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .position(
                            x: min(max(frame.origin.x + x, 24), geometry.size.width),
                            y: frame.maxY + 10
                        )
                }
            }
        }
    }

    private func detailDate(_ date: Date) -> String {
        DateFormats.string("M月d日", date)
    }

    private func detailHour(_ date: Date) -> String {
        DateFormats.string("M月d日 HH:mm", date)
    }

    private func detailMonth(_ date: Date) -> String {
        DateFormats.string("yyyy年M月", date)
    }

    private var chartHint: String {
        switch range {
        case .day:
            return "每小时使用量"
        case .week:
            return "每天使用量"
        case .month:
            return "每天使用量"
        case .all:
            return "每月使用量"
        }
    }

    private var focusedBucket: TrafficBucket? {
        if let hoveredDate {
            return nearestBucket(to: hoveredDate)
        }
        return visibleBuckets.last
    }

    private func nearestBucket(to date: Date) -> TrafficBucket? {
        visibleBuckets.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }
    }

    private func nearestBucketDate(to date: Date) -> Date {
        let candidates = visibleBuckets.map(\.date)
        return candidates.min {
            abs($0.timeIntervalSince(date)) < abs($1.timeIntervalSince(date))
        } ?? date
    }
}

private struct FocusCard: View {
    let bucket: TrafficBucket
    let range: TrafficRange

    private var title: String {
        switch range {
        case .day: "时段"
        case .week: "日期"
        case .month: "日期"
        case .all: "月份"
        }
    }

    private var detail: String {
        switch range {
        case .day: DateFormats.string("M月d日 HH:mm", bucket.date)
        case .week, .month:
            Calendar.current.isDateInToday(bucket.date)
                ? "今日"
                : DateFormats.string("M月d日", bucket.date)
        case .all: DateFormats.string("yyyy年M月", bucket.date)
        }
    }

    var body: some View {
        HStack(spacing: 18) {
            HStack(spacing: 8) {
                Text(title)
                    .font(Theme.label)
                    .foregroundStyle(.secondary)
                Text(detail)
                    .font(Theme.number(13, weight: .semibold))
            }
            Spacer()
            TrafficLegendValue(
                title: "下载",
                value: TrafficChartData.valueLabel(bucket.inbound),
                color: Theme.series2
            )
            TrafficLegendValue(
                title: "上传",
                value: TrafficChartData.valueLabel(bucket.outbound),
                color: Theme.accent,
                dashed: true
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.fill.opacity(0.7), in: RoundedRectangle(cornerRadius: Theme.controlRadius + 1, style: .continuous))
    }
}

private struct TrafficMetric: View {
    let title: String
    let value: String
    /// Series colour when the figure belongs to one plotted line; nil for derived
    /// figures, which then carry no swatch.
    let color: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let color {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(color)
                        .frame(width: 8, height: 8)
                }
                Text(title)
                    .font(Theme.label)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(Theme.number(20))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 4)
    }
}

private struct TrafficLegendValue: View {
    let title: String
    let value: String
    let color: Color
    var dashed: Bool = false

    var body: some View {
        HStack(spacing: 7) {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 2))
                path.addLine(to: CGPoint(x: 14, y: 2))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: dashed ? [4, 3] : []))
            .frame(width: 14, height: 4)
            Text(title)
                .font(Theme.label)
                .foregroundStyle(.secondary)
            Text(value)
                .font(Theme.number(13))
        }
    }
}
