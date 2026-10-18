import AppKit
import SwiftUI

/// Design tokens. The look is a quiet data dashboard: a neutral canvas, flat white
/// panels drawn with a single hairline border, no glass, no gradients, no shadows.
/// Hierarchy comes from type — large tabular numbers over small secondary labels —
/// rather than from decoration. Every colour has a light and a dark value.
///
/// Window plumbing lives in `WindowChrome.swift`, full-page and inline status
/// surfaces in `StatusViews.swift`, and the presentation rules for model types in
/// `ModelPresentation.swift`.
enum Theme {
    // MARK: Colour

    /// The one action colour. Links, selection, the comfortable state of the meter.
    static let accent = dynamic(light: 0x2F6BEB, dark: 0x5B8DF6)
    /// Second data series (download). Distinct from the accent in hue and value
    /// so the two survive greyscale and colour-blind reading.
    static let series2 = dynamic(light: 0x14A39A, dark: 0x3CC7BC)

    static let success = dynamic(light: 0x1E9E5A, dark: 0x3DC47E)
    static let warning = dynamic(light: 0xC97A0A, dark: 0xF0A73A)
    static let danger = dynamic(light: 0xD93B3B, dark: 0xF26B6B)

    /// Window canvas behind the panels.
    static let canvas = dynamic(light: 0xF5F6F8, dark: 0x131416)
    /// Panel fill.
    static let surface = dynamic(light: 0xFFFFFF, dark: 0x1B1C1F)
    /// Panel border and table rules.
    static let border = Color.primary.opacity(0.085)
    /// Separators inside a panel.
    static let hairline = Color.primary.opacity(0.065)
    /// Track behind bars and meters; also hover and inset fills.
    static let fill = Color.primary.opacity(0.055)

    // MARK: Shape and spacing

    static let panelRadius: CGFloat = 12
    static let controlRadius: CGFloat = 7
    static let pagePadding: CGFloat = 28
    /// Approximate height of a `PageHeader` with its insets, reserved when a page
    /// centres an empty state below it.
    static let pageHeaderHeight: CGFloat = 92
    static let gap: CGFloat = 16

    // MARK: Type

    /// Small secondary label above a value.
    static let label = Font.system(size: 11.5, weight: .medium)
    /// Panel heading.
    static let heading = Font.system(size: 13, weight: .semibold)
    /// Body copy and table cells.
    static let body = Font.system(size: 13)
    /// Numbers in rows and stat strips.
    static func number(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// The one container. A flat surface with a hairline border; nothing glows, nothing
/// floats. Pages compose panels rather than nesting cards inside cards.
struct Panel<Content: View>: View {
    var padding: CGFloat = 20
    /// Stretch the surface itself to the row height. The frame has to sit inside,
    /// before the background: applied from outside it would only grow transparent
    /// space. Only worth setting when the content can absorb the extra height.
    var fillsHeight: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxHeight: fillsHeight ? .infinity : nil, alignment: .top)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
    }
}

/// Panel heading row: title, optional quiet subtitle, and an optional trailing
/// accessory such as a "查看全部" link.
struct PanelHeader<Trailing: View>: View {
    var title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(Theme.heading)
            if let subtitle {
                Text(subtitle)
                    .font(Theme.label)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            trailing
        }
    }
}

extension PanelHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// Accent text link with a chevron, for jumping from a summary to its detail page.
struct PanelLink: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(title)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.accent)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// In-page title. The window toolbar carries only the refresh controls, so the
/// page name sits here at a size that anchors the layout.
struct PageHeader<Trailing: View>: View {
    var title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 24, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
    }
}

extension View {
    /// The `Panel` look for views that build their own layout.
    func panelSurface() -> some View {
        background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
                    .strokeBorder(Theme.border, lineWidth: 1)
            )
    }

    /// Insets for a `PageHeader` sitting above a page's scroll view.
    func pageHeaderInsets() -> some View {
        padding(.horizontal, Theme.pagePadding)
            .padding(.top, 4)
            .padding(.bottom, 18)
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

struct RingMeter: View {
    var progress: Double
    var label: String
    /// Keeps the accent while the quota is comfortable, then adopts the warning and
    /// critical colours so the hero answers "am I near the limit?" at a glance.
    var tint: Color = Theme.accent
    var size: CGFloat = 112
    var lineWidth: CGFloat = 9
    var labelSize: CGFloat = 24

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.fill, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(1, max(0, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(label)
                .font(Theme.number(labelSize))
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("套餐已用 \(label)")
    }
}

/// Quota headline: the meter, what has been used against the plan, and the two
/// numbers that decide whether to worry — what is left and how long until reset.
struct UsageHero: View {
    var progress: Double
    var percentage: String
    var used: String
    var quota: String
    var remaining: String
    var reset: String
    var resetDate: String? = nil
    var tint: Color = Theme.accent

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            RingMeter(progress: progress, label: percentage, tint: tint)

            VStack(alignment: .leading, spacing: 6) {
                Text("本期已用")
                    .font(Theme.label)
                    .foregroundStyle(.secondary)
                Text(used)
                    .font(Theme.number(34))
                    .lineLimit(1)
                Text("套餐 \(quota)")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .layoutPriority(1)

            Spacer(minLength: 16)

            HStack(spacing: 0) {
                UsageHeroMetric(title: "剩余", value: remaining)
                StatDivider(height: 40)
                UsageHeroMetric(title: "距重置", value: reset, detail: resetDate)
            }
        }
    }
}

private struct UsageHeroMetric: View {
    let title: String
    let value: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(Theme.label)
                .foregroundStyle(.secondary)
            Text(value)
                .font(Theme.number(22))
                .lineLimit(1)
            Text(detail ?? " ")
                .font(Theme.label)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(minWidth: 96, alignment: .leading)
        .padding(.horizontal, 20)
    }
}

/// Vertical rule between items in a stat row.
struct StatDivider: View {
    var height: CGFloat = 30

    var body: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(width: 1, height: height)
    }
}

struct MiniMetric: View {
    var value: String
    var label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(Theme.number(17))
            Text(label)
                .font(Theme.label)
                .foregroundStyle(.secondary)
        }
    }
}

struct SectionTitle: View {
    var text: String

    var body: some View {
        HStack(spacing: 10) {
            Text(text)
                .font(Theme.heading)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.bottom, 12)
    }
}

/// The app's mark: the icon's ring on an accent tile, drawn from the same
/// proportions as packaging/macos/MakeIcon.swift so the sidebar and the Dock
/// show one shape. Vector, so it stays sharp at any size.
struct BrandMark: View {
    var size: CGFloat = 24

    private struct RingArc: Shape {
        var degrees: Double
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: rect.width / 2,
                        startAngle: .degrees(-90), endAngle: .degrees(degrees - 90), clockwise: false)
            return path
        }
    }

    var body: some View {
        // Icon proportions relative to the 824 body: ring 470 across, 78 wide.
        let ring = size * 470 / 824
        let line = max(1.5, size * 78 / 824)
        ZStack {
            RoundedRectangle(cornerRadius: size * 185 / 824, style: .continuous)
                .fill(Theme.accent)
            Circle()
                .stroke(Color.white.opacity(0.28), lineWidth: line)
                .frame(width: ring, height: ring)
            RingArc(degrees: 250)
                .stroke(Color.white, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .frame(width: ring, height: ring)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
