import SwiftUI

/// Design tokens and the shared card chrome. Window plumbing lives in
/// `WindowChrome.swift`, full-page and inline status surfaces in `StatusViews.swift`,
/// and the presentation rules for model types in `ModelPresentation.swift`.
enum Theme {
    static let accent = Color(red: 0.22, green: 0.45, blue: 0.95)
    static let hairline = Color.primary.opacity(0.06)
}

/// Material card surface: top sheen, light-catching edge, optional accent wash.
struct CardSurface: View {
    var cornerRadius: CGFloat = 20
    var tint: Color? = nil

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.regularMaterial)
            .overlay {
                if let tint {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.09), tint.opacity(0.0)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.16), Color.white.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.primary.opacity(0.14), Color.primary.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
    }
}

struct GlassCard<Content: View>: View {
    var padding: CGFloat = 22
    var tint: Color? = nil
    /// Stretch the surface itself to the row height. The frame has to sit inside,
    /// before the background: applied from outside it would only grow transparent
    /// space and leave the two cards looking ragged anyway.
    ///
    /// Only worth setting when the card's content can absorb the extra height —
    /// otherwise the surplus simply becomes empty space inside the card.
    var fillsHeight: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxHeight: fillsHeight ? .infinity : nil, alignment: .top)
            .background(CardSurface(tint: tint))
            .shadow(color: .black.opacity(0.05), radius: 1.5, x: 0, y: 1)
            .shadow(color: .black.opacity(0.08), radius: 14, x: 0, y: 7)
    }
}

struct RingMeter: View {
    var progress: Double
    var label: String
    /// Keeps the accent while the quota is comfortable, then adopts the warning and
    /// critical colours so the hero answers "am I near the limit?" at a glance.
    var tint: Color = Theme.accent

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [tint.opacity(0.10), Color.clear],
                        center: .center,
                        startRadius: 4,
                        endRadius: 62
                    )
                )
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 13)
            Circle()
                .trim(from: 0, to: min(1, max(0, progress)))
                .stroke(
                    AngularGradient(
                        colors: [tint.opacity(0.72), tint, tint.opacity(0.72)],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 13, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: tint.opacity(0.38), radius: 7, x: 0, y: 1)
            Text(label)
                .font(.system(size: 31, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .frame(width: 148, height: 148)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("套餐已用 \(label)")
    }
}

struct UsageHero: View {
    var progress: Double
    var percentage: String
    var used: String
    var quota: String
    var remaining: String
    var reset: String
    var resetDate: String? = nil

    // Two columns, sized to sit against the 148pt ring. A single row of four turned
    // the metrics into a thin strip beside it and read as cramped.
    private let columns = [
        GridItem(.flexible(), alignment: .leading),
        GridItem(.flexible(), alignment: .leading)
    ]

    var body: some View {
        HStack(spacing: 30) {
            RingMeter(
                progress: progress,
                label: percentage,
                tint: UsageRing.color(for: progress)
            )

            LinearGradient(
                colors: [
                    Color.primary.opacity(0.02),
                    Color.primary.opacity(0.11),
                    Color.primary.opacity(0.02)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: 1, height: 132)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                UsageHeroMetric(title: "已用", value: used)
                UsageHeroMetric(title: "套餐", value: quota)
                UsageHeroMetric(title: "剩余", value: remaining)
                UsageHeroMetric(title: "重置", value: reset, detail: resetDate)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct UsageHeroMetric: View {
    let title: String
    let value: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value)
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let detail {
                    Text(detail)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MiniMetric: View {
    var value: String
    var label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

struct SectionTitle: View {
    var text: String

    var body: some View {
        HStack(spacing: 10) {
            Text(text)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.bottom, 12)
    }
}
