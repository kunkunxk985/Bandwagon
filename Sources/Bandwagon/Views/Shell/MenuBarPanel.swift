import SwiftUI

/// Preference key for showing the menu bar item. Read by the app scene and the
/// settings page; applies immediately, outside the save button, because it is
/// about this Mac rather than about the panels.
enum MenuBarPreference {
    static let key = "showMenuBarExtra"
}

/// The menu bar item itself: a glyph that carries the forecast and the used share.
/// Menu bar images are template-rendered, so state is in the symbol, not a colour.
struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            if let percent = model.overview.bwh?.usedPercent {
                Text(ByteFormat.percent(percent))
                    .monospacedDigit()
            }
        }
        .task { await model.start() }
        .accessibilityLabel(accessibilityText)
    }

    private var symbol: String {
        if model.overview.bwh?.error != nil || model.overview.xui?.error != nil { return "exclamationmark.icloud" }
        switch model.forecast?.verdict {
        case .over: return "exclamationmark.triangle.fill"
        case .tight: return "exclamationmark.circle"
        default: return "gauge.with.dots.needle.33percent"
        }
    }

    private var accessibilityText: String {
        var parts = ["Bandwagon"]
        if let percent = model.overview.bwh?.usedPercent { parts.append("套餐已用 \(ByteFormat.percent(percent))") }
        if let forecast = model.forecast { parts.append(forecast.headline) }
        return parts.joined(separator: "，")
    }
}

/// The window that drops from the menu bar item: the answer to "am I fine?"
/// without opening the main window.
///
/// Laid out like the system's own menu bar panels (Wi-Fi, Control Center) and
/// painted with no background of its own, so the system's glass material shows
/// through: small grey section titles, round icon badges, inset separators, and
/// menu-style rows at the bottom. The main window keeps the flat dashboard look;
/// this one belongs to the menu bar.
struct MenuBarPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 10)

            quota
                .padding(.horizontal, 14)
                .padding(.bottom, 12)

            separator
            clients
            separator

            VStack(spacing: 0) {
                PanelMenuRow(title: "打开 Bandwagon…") { openMain() }
                PanelMenuRow(title: "退出 Bandwagon") { NSApp.terminate(nil) }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 5)
        }
        .frame(width: 300)
    }

    private var separator: some View {
        Divider()
            .padding(.horizontal, 14)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Bandwagon")
                .font(.system(size: 13, weight: .bold))
            Spacer()
            if let fetchedAt = model.overview.fetchedAt {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(ContentView.updatedLabel(fetchedAt, now: context.date))
                        .font(.system(size: 11.5))
                        .foregroundStyle(model.isStale ? ClientState.warn.swiftColor : Color.secondary)
                        .monospacedDigit()
                }
            }
            Button {
                Task { await model.load() }
            } label: {
                Group {
                    if model.loading {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                    }
                }
                .frame(width: 22, height: 22)
                .background(Color.primary.opacity(0.08), in: Circle())
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(model.loading)
            .help("刷新")
            .accessibilityLabel("刷新")
        }
    }

    @ViewBuilder
    private var quota: some View {
        if let bwh = model.overview.bwh, bwh.usedBytes != nil {
            let progress = (bwh.usedPercent ?? 0) / 100
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    RingMeter(
                        progress: progress,
                        label: ByteFormat.percent(bwh.usedPercent),
                        tint: UsageRing.color(for: progress, forecast: model.forecast?.verdict),
                        size: 58,
                        lineWidth: 6,
                        labelSize: 13
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ByteFormat.string(bwh.usedBytes))
                            .font(Theme.number(20))
                        Text("套餐 \(ByteFormat.string(bwh.quotaBytes)) · \(ByteFormat.daysLeft(resetAt: bwh.resetAt))后重置")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                }
                if let forecast = model.forecast {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: forecast.verdict.icon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(forecast.verdict.tint)
                        Text(forecast.headline)
                            .font(.system(size: 12))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let error = bwh.error {
                    errorLine(error)
                }
            }
        } else if let error = model.overview.bwh?.error {
            errorLine(error)
        } else if !model.settings.bwhReady {
            Text("尚未配置 Bandwagon")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("正在读取…")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The online count as one row, then only the clients that need a look —
    /// each a row that opens its detail sheet. A healthy panel shows one line.
    @ViewBuilder
    private var clients: some View {
        if let xui = model.overview.xui, let list = xui.clients {
            let flagged = list.filter { $0.state == .warn }
            VStack(alignment: .leading, spacing: 0) {
                Text("客户端")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.top, 9)
                    .padding(.bottom, 3)

                VStack(spacing: 0) {
                    PanelItemRow(
                        icon: "person.2.fill",
                        badge: ClientState.online.swiftColor,
                        title: "\(xui.onlineCount ?? 0) 个在线",
                        detail: "共 \(xui.clientCount ?? list.count) 个"
                    ) {
                        openMain()
                    }
                    ForEach(flagged.prefix(3)) { client in
                        PanelItemRow(
                            icon: "exclamationmark",
                            badge: ClientState.warn.swiftColor,
                            title: client.name,
                            detail: client.expiryWarning ?? client.percent.map { "已用 \(Int($0.rounded()))%" } ?? "预警"
                        ) {
                            openMain()
                            model.inspectedClientID = client.id
                        }
                    }
                }
                .padding(.horizontal, 5)
                .padding(.bottom, 5)

                if let error = xui.error {
                    errorLine(error)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                }
            }
        }
    }

    private func errorLine(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(Theme.warning)
            Text(message)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func openMain() {
        openWindow(id: BandwagonApp.mainWindowID)
        NSApp.activate()
    }
}

/// A row with a round coloured badge, like the network rows in the Wi-Fi panel.
private struct PanelItemRow: View {
    let icon: String
    let badge: Color
    let title: String
    let detail: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(badge, in: Circle())
                Text(title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(hovered ? Color.primary.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

/// A plain text row at the foot of the panel, like "Wi-Fi 设置…".
private struct PanelMenuRow: View {
    let title: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(hovered ? Color.primary.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}
