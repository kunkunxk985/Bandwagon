import SwiftUI

/// One-line verdict on whether this cycle's quota will hold. It is the conclusion,
/// so it sits directly under the quota numbers and above the supporting detail.
struct ForecastStrip: View {
    var forecast: TrafficForecast

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: forecast.verdict.icon)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(forecast.verdict.tint)

            Text(forecast.headline)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 10)

            Text(forecast.detail)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(
            forecast.verdict.tint.opacity(0.10),
            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(forecast.verdict.tint.opacity(0.22), lineWidth: 0.8)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(forecast.headline)，\(forecast.detail)")
    }
}

/// Hairline divider that fades at both ends — used inside cards.
struct CardDivider: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color.primary.opacity(0.025),
                Color.primary.opacity(0.11),
                Color.primary.opacity(0.025)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 1)
    }
}

/// Compact stat tile for summary rows (clients overview, dashboards).
struct SummaryTile: View {
    var icon: String? = nil
    var dotColor: Color? = nil
    var tint: Color = .secondary
    var title: String
    var value: String

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.20), tint.opacity(0.07)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                if let dotColor {
                    ZStack {
                        Circle()
                            .fill(dotColor.opacity(0.22))
                            .frame(width: 15, height: 15)
                        Circle()
                            .fill(dotColor)
                            .frame(width: 7.5, height: 7.5)
                    }
                } else if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(tint)
                }
            }
            .frame(width: 34, height: 34)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(tint.opacity(0.22), lineWidth: 0.8)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(value)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

/// Inline utilization bar (0...1) on a subtle track.
struct UsageBar: View {
    var value: Double
    var tint: Color = Theme.accent
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.075))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.72), tint],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
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
enum UsageRing {
    static func color(for fraction: Double) -> Color {
        if fraction >= UsageThreshold.critical { return ClientState.off.swiftColor }
        if fraction >= UsageThreshold.warn { return ClientState.warn.swiftColor }
        return Theme.accent
    }
}

/// State pill with tinted capsule background.
struct StatusPill: View {
    var title: String
    var tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(tint.opacity(0.13), in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(tint.opacity(0.26), lineWidth: 0.8)
        )
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

/// Icon + label + value cell used by spec grids and the overview strip.
struct InfoCell: View {
    var icon: String
    var title: String
    var value: String
    var barFraction: Double? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Theme.accent.opacity(0.20), Theme.accent.opacity(0.07)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            .frame(width: 32, height: 32)
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(0.20), lineWidth: 0.8)
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if let barFraction {
                    UsageBar(value: barFraction, tint: UsageTint.color(for: barFraction))
                        .frame(maxWidth: 180)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// Capsule chip used in hero footers for host and status information.
struct HeroChip: View {
    var icon: String? = nil
    var dotColor: Color? = nil
    var value: String
    var valueColor: Color = .primary
    var label: String? = nil

    var body: some View {
        HStack(spacing: 7) {
            if let dotColor {
                ZStack {
                    Circle()
                        .fill(dotColor.opacity(0.22))
                        .frame(width: 14, height: 14)
                    Circle()
                        .fill(dotColor)
                        .frame(width: 7, height: 7)
                }
            } else if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.accent.opacity(0.9))
            }
            Text(value)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(valueColor)
                .lineLimit(1)
            if let label {
                Text(label)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.primary.opacity(0.045))
        )
        .overlay(
            Capsule()
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }
}