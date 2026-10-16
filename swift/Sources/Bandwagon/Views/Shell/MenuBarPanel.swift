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
struct MenuBarPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)
            CardDivider()

            VStack(alignment: .leading, spacing: 14) {
                quota
                clients
            }
            .padding(16)

            CardDivider()
            footer
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
        .frame(width: 320)
        .background(Theme.surface)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Bandwagon")
                .font(.system(size: 13, weight: .semibold))
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
                if model.loading {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11.5, weight: .medium))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(model.loading)
            .help("刷新")
        }
    }

    @ViewBuilder
    private var quota: some View {
        if let bwh = model.overview.bwh, bwh.usedBytes != nil {
            let progress = (bwh.usedPercent ?? 0) / 100
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    RingMeter(
                        progress: progress,
                        label: ByteFormat.percent(bwh.usedPercent),
                        tint: UsageRing.color(for: progress, forecast: model.forecast?.verdict),
                        size: 64,
                        lineWidth: 6,
                        labelSize: 14
                    )
                    VStack(alignment: .leading, spacing: 3) {
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
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: forecast.verdict.icon)
                            .font(.system(size: 11.5, weight: .semibold))
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

    /// Counts, then only the clients that need a look. A healthy panel shows one
    /// line here, not a list.
    @ViewBuilder
    private var clients: some View {
        if let xui = model.overview.xui, let list = xui.clients {
            let flagged = list.filter { $0.state == .warn }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 14) {
                    HeroChip(dotColor: ClientState.online.swiftColor, value: "\(xui.onlineCount ?? 0)", label: "在线")
                    HeroChip(value: "\(xui.clientCount ?? list.count)", label: "客户端")
                    if !flagged.isEmpty {
                        HeroChip(dotColor: ClientState.warn.swiftColor, value: "\(flagged.count)", label: "预警")
                    }
                }
                ForEach(flagged.prefix(3)) { client in
                    Button {
                        openMain()
                        model.inspectedClientID = client.id
                    } label: {
                        HStack {
                            Text(client.name)
                                .font(.system(size: 12.5))
                                .lineLimit(1)
                            Spacer()
                            Text(client.expiryWarning ?? client.percent.map { "\(Int($0.rounded()))%" } ?? "")
                                .font(Theme.number(12, weight: .medium))
                                .foregroundStyle(ClientState.warn.swiftColor)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if let error = xui.error {
                    errorLine(error)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 4) {
            MenuRowButton(title: "打开 Bandwagon", systemImage: "macwindow") { openMain() }
            Spacer()
            MenuRowButton(title: "退出", systemImage: "power") { NSApp.terminate(nil) }
        }
    }

    private func errorLine(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
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

private struct MenuRowButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12.5))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(hovered ? Theme.fill : Color.clear, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}
