import SwiftUI

struct OverviewView: View {
    @Environment(AppModel.self) private var model
    @Binding var selectedTab: ContentView.Tab

    init(selectedTab: Binding<ContentView.Tab>) {
        _selectedTab = selectedTab
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                bwhSection
                xuiSection
                activitySection
                serverSummarySection
            }
            .padding(28)
            .modifier(CenterWhenShort(enabled: !hasAnyData))
        }
        .navigationTitle("总览")
    }

    /// True once either service has reported something, even stale data. Until then
    /// the page is nothing but state cards, which belong centred rather than scrolled.
    private var hasAnyData: Bool {
        model.overview.bwh != nil || model.overview.xui != nil
    }

    // MARK: - Bandwagon 套餐与用量

    @ViewBuilder
    private var bwhSection: some View {
        let bwh = model.overview.bwh
        if !model.settings.bwhReady {
            StatusCard(
                title: "尚未配置 Bandwagon",
                message: "请先添加 VEID 与 API Key。",
                icon: "server.rack",
                tint: .secondary,
                action: { selectedTab = .settings },
                actionTitle: "前往设置"
            )
        } else if bwh?.usedBytes != nil {
            // Data exists, fresh or stale. A failure becomes a banner instead of
            // replacing the whole dashboard with an error page.
            VStack(alignment: .leading, spacing: 12) {
                if let error = bwh?.error {
                    bwhBanner(error)
                }
                heroCard
            }
        } else if let error = bwh?.error {
            // Failed with nothing to fall back on, so the page has to say so plainly.
            let failure = ServiceFailure(service: "Bandwagon", error: error, needsSettings: model.bwhNeedsSettings)
            StatusCard(
                title: failure.title,
                message: failure.message,
                icon: failure.icon,
                tint: .orange,
                action: { failure.resolve(goToSettings: { selectedTab = .settings }, retry: { await model.load() }) },
                actionTitle: failure.actionTitle
            )
        } else {
            StatusCard(
                title: "正在读取 Bandwagon",
                message: "正在获取套餐与用量信息…",
                icon: "antenna.radiowaves.left.and.right",
                tint: .secondary
            )
        }
    }

    private func bwhBanner(_ error: String) -> some View {
        let failure = ServiceFailure(service: "Bandwagon", error: error, needsSettings: model.bwhNeedsSettings)
        return StatusBanner(
            title: failure.staleTitle,
            message: failure.message,
            icon: failure.icon,
            tint: .orange,
            actionTitle: failure.actionTitle,
            action: { failure.resolve(goToSettings: { selectedTab = .settings }, retry: { await model.load() }) }
        )
    }

    private var heroCard: some View {
        GlassCard(padding: 26, tint: Theme.accent) {
            VStack(alignment: .leading, spacing: 20) {
                UsageHero(
                    progress: (model.overview.bwh?.usedPercent ?? 0) / 100,
                    percentage: ByteFormat.percent(model.overview.bwh?.usedPercent),
                    used: ByteFormat.string(model.overview.bwh?.usedBytes),
                    quota: ByteFormat.string(model.overview.bwh?.quotaBytes),
                    remaining: ByteFormat.string(remaining),
                    reset: ByteFormat.daysLeft(resetAt: model.overview.bwh?.resetAt),
                    resetDate: ByteFormat.resetDate(model.overview.bwh?.resetAt)
                )
                if let forecast = model.forecast {
                    ForecastStrip(forecast: forecast)
                }
                CardDivider()
                serverStrip
            }
        }
    }

    private var serverStrip: some View {
        HStack(spacing: 10) {
            HeroChip(
                value: hostTitle,
                label: hostIP
            )
            if let bwh = model.overview.bwh {
                // Status carries colour *and* text, so health is never colour-only.
                StatusPill(title: bwh.healthLabel, tint: bwh.healthTint)
            }
            Spacer(minLength: 8)
            // Counts stay visible even when the last fetch failed; the banner above
            // is what flags them as possibly stale.
            if let xui = model.overview.xui,
               let online = xui.onlineCount, let clients = xui.clientCount {
                HeroChip(
                    icon: "person.2.fill",
                    value: "\(online)",
                    valueColor: ClientState.online.swiftColor,
                    label: "在线"
                )
                HeroChip(
                    icon: "rectangle.stack.fill",
                    value: "\(clients)",
                    label: "客户端"
                )
                if model.xuiLoading {
                    ProgressView()
                        .controlSize(.mini)
                }
            } else if model.xuiLoading {
                HStack(spacing: 7) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在连接 3X-UI")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - 3X-UI 状态提示

    @ViewBuilder
    private var xuiSection: some View {
        let xui = model.overview.xui
        if xui?.clientCount != nil {
            // The hero strip already carries the counts; only the failure is news.
            if let error = xui?.error {
                let failure = ServiceFailure(service: "3X-UI", error: error, needsSettings: model.xuiNeedsSettings)
                StatusBanner(
                    title: failure.staleTitle,
                    message: failure.message,
                    icon: failure.icon,
                    tint: .orange,
                    actionTitle: failure.actionTitle,
                    action: { failure.resolve(goToSettings: { selectedTab = .settings }, retry: { await model.load() }) }
                )
            }
        } else if let error = xui?.error {
            let failure = ServiceFailure(service: "3X-UI", error: error, needsSettings: model.xuiNeedsSettings)
            StatusCard(
                title: failure.title,
                message: failure.message,
                icon: failure.icon,
                tint: .orange,
                action: { failure.resolve(goToSettings: { selectedTab = .settings }, retry: { await model.load() }) },
                actionTitle: failure.actionTitle
            )
        } else if xui == nil && !bwhHeroVisible && model.xuiLoading {
            StatusCard(
                title: "正在连接 3X-UI",
                message: "正在读取客户端与在线状态…",
                icon: "antenna.radiowaves.left.and.right",
                tint: .secondary
            )
        }
    }

    private var bwhHeroVisible: Bool {
        model.settings.bwhReady && model.overview.bwh?.usedBytes != nil
    }

    // MARK: - 流量与客户端

    @ViewBuilder
    private var activitySection: some View {
        let history = model.overview.bwhHistory ?? []
        let clients = topClients ?? []
        if !history.isEmpty && !clients.isEmpty {
            // One row, two equal columns. The traffic card used to be capped at 430pt,
            // so it sat both narrower and — because its chart was a fixed height —
            // shorter than the clients card beside it.
            HStack(alignment: .top, spacing: 18) {
                MiniTrafficCard(points: history, onOpen: { selectedTab = .vps })
                    .frame(maxWidth: .infinity)
                topClientsCard(clients)
                    .frame(maxWidth: .infinity)
            }
        } else if !history.isEmpty {
            MiniTrafficCard(points: history, onOpen: { selectedTab = .vps })
        } else if !clients.isEmpty {
            topClientsCard(clients)
        }
    }

    private func topClientsCard(_ clients: [Client]) -> some View {
        let maxUsed = clients.map { $0.used ?? 0 }.max() ?? 0
        return GlassCard(padding: 20, fillsHeight: true) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Text("Top 客户端")
                        .font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Button {
                        selectedTab = .clients
                    } label: {
                        HStack(spacing: 4) {
                            Text("查看全部")
                                .font(.system(size: 12, weight: .medium))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 10)

                VStack(spacing: 2) {
                    ForEach(Array(clients.enumerated()), id: \.element.id) { index, client in
                        TopClientRow(rank: index + 1, client: client, maxUsed: maxUsed)
                    }
                }
            }
        }
    }

    // MARK: - 服务器概况

    @ViewBuilder
    private var serverSummarySection: some View {
        let items = specItems
        if !items.isEmpty {
            GlassCard(padding: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        Text("服务器概况")
                            .font(.system(size: 16, weight: .semibold))
                        Spacer()
                        Button {
                            selectedTab = .vps
                        } label: {
                            HStack(spacing: 4) {
                                Text("VPS 详情")
                                    .font(.system(size: 12, weight: .medium))
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .semibold))
                            }
                            .foregroundStyle(Theme.accent)
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(alignment: .center, spacing: 14) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            InfoCell(icon: item.icon, title: item.title, value: item.value, barFraction: item.fraction)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if index < items.count - 1 {
                                Rectangle()
                                    .fill(Color.primary.opacity(0.06))
                                    .frame(width: 1, height: 34)
                            }
                        }
                    }
                }
            }
        }
    }

    private var specItems: [SpecRow] {
        var items: [SpecRow] = []
        let bwh = model.overview.bwh
        appendSpecRow(&items, icon: "globe", title: "位置", value: bwh?.location)
        if let ramLabel = usageLabel(total: bwh?.ramBytes, used: bwh?.ramUsedBytes) {
            items.append(SpecRow(
                icon: "memorychip",
                title: "内存",
                value: ramLabel,
                fraction: usageFraction(total: bwh?.ramBytes, used: bwh?.ramUsedBytes)
            ))
        }
        if let diskLabel = usageLabel(total: bwh?.diskBytes, used: bwh?.diskUsedBytes) {
            items.append(SpecRow(
                icon: "internaldrive",
                title: "磁盘",
                value: diskLabel,
                fraction: usageFraction(total: bwh?.diskBytes, used: bwh?.diskUsedBytes)
            ))
        }
        return items
    }

    // MARK: - 数据辅助

    private var remaining: Int? {
        guard let used = model.overview.bwh?.usedBytes,
              let quota = model.overview.bwh?.quotaBytes else { return nil }
        return max(0, quota - used)
    }

    private var topClients: [Client]? {
        model.overview.xui?.clients?.prefix(8).map { $0 }
    }

    private var hostTitle: String {
        if let name = model.overview.bwh?.hostname, !name.isEmpty { return name }
        if model.overview.bwh?.configured == true { return "已连接" }
        return "未配置"
    }

    private var hostIP: String? {
        guard let ip = model.overview.bwh?.ip, !ip.isEmpty else { return nil }
        return ip
    }
}

private struct TopClientRow: View {
    let rank: Int
    let client: Client
    let maxUsed: Int

    @State private var copied = false
    @State private var hovered = false

    private var fraction: Double {
        guard maxUsed > 0 else { return 0 }
        return min(1, max(0, Double(client.used ?? 0) / Double(maxUsed)))
    }

    var body: some View {
        HStack(spacing: 10) {
            Text("\(rank)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(rank <= 3 ? Theme.accent : Color.secondary)
                .frame(width: 24, height: 24)
                .background(
                    rank <= 3 ? Theme.accent.opacity(0.13) : Color.primary.opacity(0.045),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )

            Text(client.name)
                .font(.system(size: 13.5, weight: .semibold))
                .lineLimit(1)
                .layoutPriority(1)

            HStack(spacing: 5) {
                Circle()
                    .fill(client.state.swiftColor)
                    .frame(width: 6, height: 6)
                Text(client.state.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(client.state.swiftColor)
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 8)

            // Single accent colour: the state pill beside the name already carries
            // risk, so colouring the bars too only added noise to the first screen.
            UsageBar(value: fraction, tint: Theme.accent)
                .frame(minWidth: 36, maxWidth: 72)

            Text(ByteFormat.string(client.used))
                .font(.system(size: 14.5, weight: .bold, design: .rounded))
                .monospacedDigit()
                .frame(minWidth: 60, alignment: .trailing)

            Button {
                let text = client.email ?? client.name
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                    copied = false
                }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(copied ? ClientState.online.swiftColor : Color.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(copied ? "已复制" : "复制邮箱")
            // Name the client so this button is distinguishable from the seven
            // others on the card when read by VoiceOver.
            .accessibilityLabel(copied ? "已复制 \(client.name) 的邮箱" : "复制 \(client.name) 的邮箱")
            .opacity(hovered || copied ? 1 : 0.6)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            hovered ? Color.primary.opacity(0.05) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .onHover { hovering in
            hovered = hovering
        }
    }
}