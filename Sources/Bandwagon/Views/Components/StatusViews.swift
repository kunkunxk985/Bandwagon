import SwiftUI

/// Full-page state: nothing to show yet, nothing configured, or a failure with no
/// data to fall back on. For a failure that still has data behind it, use
/// `StatusBanner` instead so the dashboard keeps its numbers.
struct StatusCard: View {
    let title: String
    let message: String
    let icon: String
    let tint: Color
    let action: (() -> Void)?
    let actionTitle: String?

    init(
        title: String,
        message: String,
        icon: String,
        tint: Color,
        action: (() -> Void)? = nil,
        actionTitle: String? = nil
    ) {
        self.title = title
        self.message = message
        self.icon = icon
        self.tint = tint
        self.action = action
        self.actionTitle = actionTitle
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(tint)
                .frame(width: 48, height: 48)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
                .padding(.bottom, 4)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Text(message)
                .font(Theme.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            if let action, let actionTitle, !actionTitle.isEmpty {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .padding(.top, 6)
            }
        }
        // No Spacers: inside a ScrollView they collapse to zero, so the card used to
        // sit wherever ad-hoc `.padding(.top, …)` left it. Fixed padding reads the
        // same everywhere, and callers centre it when it is the only thing on a page.
        .padding(.vertical, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One-line failure notice for a page that can keep showing its last good data.
/// Used instead of `StatusCard` whenever a transient failure would otherwise blank
/// the dashboard.
struct StatusBanner: View {
    var title: String
    var message: String
    var icon: String
    var tint: Color
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 10)

            if let action, let actionTitle, !actionTitle.isEmpty {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderless)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
    }
}

/// Vertically centres its content when the container is taller than the content,
/// and gets out of the way otherwise. `Spacer()` collapses inside a ScrollView, so
/// a centred empty state has to claim the container's height explicitly.
struct CenterWhenShort: ViewModifier {
    var enabled: Bool
    /// Height already taken above this content in the same scroll view (a page
    /// header), so the centred block does not push the page into scrolling.
    var reserving: CGFloat = 0

    func body(content: Content) -> some View {
        if enabled {
            content.containerRelativeFrame(.vertical, alignment: .center) { length, _ in
                max(0, length - reserving)
            }
        } else {
            content
        }
    }
}
