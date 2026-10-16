import SwiftUI

/// One-line verdict on whether this cycle's quota will hold. It is the conclusion,
/// so it sits directly under the quota numbers and above the supporting detail.
struct ForecastStrip: View {
    var forecast: TrafficForecast

    var body: some View {
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
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            forecast.verdict.tint.opacity(0.09),
            in: RoundedRectangle(cornerRadius: Theme.controlRadius + 1, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(forecast.headline)，\(forecast.detail)")
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

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
            Text(title)
                .font(.system(size: 12, weight: .medium))
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
