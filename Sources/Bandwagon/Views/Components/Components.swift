import SwiftUI

/// Verdict on whether this cycle's quota will hold: the sentence first, then the
/// same answer drawn as a timeline from today to the reset. It is the conclusion,
/// so it sits directly under the quota numbers.
struct ForecastStrip: View {
    var forecast: TrafficForecast
    var showsTimeline = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: forecast.verdict.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(forecast.verdict.tint)

                Text(forecast.headline)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 10)

                Text(forecast.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
            }
            if showsTimeline {
                ForecastTimeline(forecast: forecast)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, showsTimeline ? 11 : 9)
        .background(
            forecast.verdict.tint.opacity(0.07),
            in: RoundedRectangle(cornerRadius: Theme.controlRadius + 1, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(forecast.headline)，\(forecast.detail)")
    }
}

/// Today → reset on a hairline. Three dots mark today, the projected run-out and
/// the reset; the stretch with nothing left before the reset is drawn dashed in
/// red. When the quota outlasts the cycle there is no run-out dot, and the far end
/// says roughly how much will be left over.
struct ForecastTimeline: View {
    var forecast: TrafficForecast
    var now: Date = Date()

    private var runsOut: Bool { forecast.daysUntilExhausted < forecast.daysLeft }
    private var exhaustFraction: Double {
        guard forecast.daysLeft > 0 else { return 1 }
        return min(1, max(0, forecast.daysUntilExhausted / forecast.daysLeft))
    }
    private var resetDate: Date { now.addingTimeInterval(forecast.daysLeft * 86_400) }
    private var exhaustDate: Date { now.addingTimeInterval(forecast.daysUntilExhausted * 86_400) }
    private var lineColor: Color { forecast.verdict == .tight ? Theme.warning : Theme.accent }

    /// Expected surplus at reset when the quota outlasts the cycle.
    private var leftoverAtReset: Int {
        let spent = Double(forecast.dailyAverageBytes) * forecast.daysLeft
        return max(0, forecast.remainingBytes - Int(min(spent, Double(Int.max))))
    }

    private let dot: CGFloat = 9

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                let width = proxy.size.width
                let inset = dot / 2
                let span = max(0, width - dot)
                let split = inset + span * (runsOut ? exhaustFraction : 1)
                let mid = proxy.size.height / 2
                ZStack(alignment: .topLeading) {
                    Path { path in
                        path.move(to: CGPoint(x: inset, y: mid))
                        path.addLine(to: CGPoint(x: split, y: mid))
                    }
                    .stroke(lineColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    if runsOut {
                        Path { path in
                            path.move(to: CGPoint(x: split, y: mid))
                            path.addLine(to: CGPoint(x: width - inset, y: mid))
                        }
                        .stroke(Theme.danger, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                    }
                    Circle()
                        .fill(lineColor)
                        .frame(width: dot, height: dot)
                        .position(x: inset, y: mid)
                    if runsOut {
                        ring(Theme.danger)
                            .position(x: split, y: mid)
                    }
                    ring(Color.secondary)
                        .position(x: width - inset, y: mid)
                }
            }
            .frame(height: dot + 2)

            HStack(spacing: 6) {
                Text("今天 \(DateFormats.string("M/d", now))")
                Spacer(minLength: 8)
                if runsOut {
                    Text("约 \(DateFormats.string("M/d", exhaustDate)) 用尽 · 空档 \(TrafficForecast.dayText(forecast.daysLeft - forecast.daysUntilExhausted))")
                        .foregroundStyle(Theme.danger)
                        .padding(.trailing, 14)
                } else if leftoverAtReset > 0 {
                    Text("重置时约剩 \(TrafficChartData.valueLabel(leftoverAtReset))")
                        .padding(.trailing, 14)
                }
                Text("\(DateFormats.string("M/d", resetDate)) 重置")
            }
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func ring(_ color: Color) -> some View {
        Circle()
            .fill(Theme.surface)
            .overlay(Circle().strokeBorder(color, lineWidth: 2))
            .frame(width: dot, height: dot)
    }

    private var accessibilityText: String {
        let reset = DateFormats.string("M月d日", resetDate)
        if runsOut {
            return "预计 \(DateFormats.string("M月d日", exhaustDate)) 用尽，\(reset) 重置"
        }
        return "\(reset) 重置，届时约剩 \(TrafficChartData.valueLabel(leftoverAtReset))"
    }
}

/// Full-width hairline separator used inside panels.
struct CardDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(height: 1)
    }
}

/// One figure in a stat strip: small label over a large tabular number. Strips are
/// a single panel divided by rules, not a row of separate tiles.
struct SummaryTile: View {
    var dotColor: Color? = nil
    var title: String
    var value: String
    var valueColor: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let dotColor {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 6, height: 6)
                }
                Text(title)
                    .font(Theme.label)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(Theme.number(22))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Inline utilization bar (0...1) on a subtle track.
struct UsageBar: View {
    var value: Double
    var tint: Color = Theme.accent
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.fill)
                Capsule()
                    .fill(tint)
                    .frame(width: max(height, proxy.size.width * min(1, max(0, value))))
            }
        }
        .frame(height: height)
    }
}

/// Utilization color by fraction: healthy / warning / critical. Thresholds come
/// from `UsageThreshold` so this can never drift from `Client.state`.
enum UsageTint {
    static func color(for fraction: Double) -> Color {
        if fraction >= UsageThreshold.critical { return ClientState.off.swiftColor }
        if fraction >= UsageThreshold.warn { return ClientState.warn.swiftColor }
        return ClientState.online.swiftColor
    }
}

/// Ring colour. Unlike the bars this keeps the accent while the quota is
/// comfortable, so the hero stays on-brand and only turns semantic when the
/// number actually needs attention.
///
/// The forecast counts as much as the used share: a ring at 28% that stays calm
/// blue beside "will run out in 18 days" contradicts the sentence under it.
enum UsageRing {
    static func color(for fraction: Double, forecast: TrafficForecast.Verdict? = nil) -> Color {
        if fraction >= UsageThreshold.critical || forecast == .over { return ClientState.off.swiftColor }
        if fraction >= UsageThreshold.warn || forecast == .tight { return ClientState.warn.swiftColor }
        return Theme.accent
    }
}

/// State label: a coloured dot and the state in words, so status is never colour
/// alone. Quiet by design — a filled capsule on every row was the loudest thing
/// on the page.
struct StatusPill: View {
    var title: String
    var tint: Color
    /// Point size of the word. The clients table passes the shared row size;
    /// other screens keep this quieter default.
    var size: CGFloat = 12

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
            Text(title)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(tint == .secondary ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .lineLimit(1)
        }
        .fixedSize()
    }
}

/// One spec row: icon, label, value, and an optional utilization fraction.
struct SpecRow: Identifiable {
    var id: String { title }
    var icon: String
    var title: String
    var value: String
    var fraction: Double? = nil
}

/// Appends a spec row when the value is meaningful.
func appendSpecRow(_ items: inout [SpecRow], icon: String, title: String, value: String?) {
    guard let value, !value.isEmpty, value != "—" else { return }
    items.append(SpecRow(icon: icon, title: title, value: value))
}

/// Formats a capacity as "used / total" when a used value is known, and as just the
/// total otherwise. Used by the memory and disk cells, which read the same shape.
func usageLabel(total: Int?, used: Int?) -> String? {
    guard let total, total > 0 else { return nil }
    let totalText = ByteFormat.string(total)
    if let used, used > 0 {
        return "\(ByteFormat.string(used)) / \(totalText)"
    }
    return totalText
}

/// Used/total as a 0...1 fraction for a spec cell's bar, or nil when either side is
/// missing or nonsensical — a cell with no bar is better than a bar at a wrong length.
func usageFraction(total: Int?, used: Int?) -> Double? {
    guard let total, total > 0, let used, used > 0 else { return nil }
    return min(1, Double(used) / Double(total))
}

/// Label over value, with an optional utilization bar. The icon is a small
/// monochrome glyph beside the label, not a tinted tile: eight blue tiles in one
/// panel gave the eye nowhere to land.
struct InfoCell: View {
    var icon: String
    var title: String
    var value: String
    var barFraction: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: icon)
                    .font(.system(size: 10.5, weight: .medium))
                    .frame(width: 14)
            }
            .font(Theme.label)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)

            Text(value)
                .font(.system(size: 13.5, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .textSelection(.enabled)
            if let barFraction {
                UsageBar(value: barFraction, tint: UsageTint.color(for: barFraction))
                    .frame(maxWidth: 200)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Inline fact for panel footers: an optional glyph or dot, a value, and a quiet
/// label. Text, not a capsule — the footer reads as one line of facts.
struct HeroChip: View {
    var icon: String? = nil
    var dotColor: Color? = nil
    var value: String
    var valueColor: Color = .primary
    var label: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let dotColor {
                Circle()
                    .fill(dotColor)
                    .frame(width: 6, height: 6)
            } else if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(valueColor)
                .monospacedDigit()
                .lineLimit(1)
            if let label {
                Text(label)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
    }
}
