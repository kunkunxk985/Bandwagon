import SwiftUI

struct OverviewView: View {
    @Environment(AppModel.self) private var model
    @Binding var selectedTab: ContentView.Tab

    init(selectedTab: Binding<ContentView.Tab>) {
        _selectedTab = selectedTab
    }

    var body: some View {
        // The header scrolls with the page. Pinned outside the scroll view it ran
        // wider than the panels whenever the system shows legacy scroll bars.
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(title: "总览", subtitle: hostSubtitle) {
                    headerFacts
                }
                .pageHeaderInsets()

                VStack(alignment: .leading, spacing: Theme.gap) {
                    bwhSection
                    xuiSection
                    activitySection
                    serverSummarySection
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.bottom, Theme.pagePadding)
                .modifier(CenterWhenShort(enabled: !hasAnyData, reserving: Theme.pageHeaderHeight))
            }
        }
        .navigationTitle("总览")
    }

    /// True once either service has reported something, even stale data. Until then
    /// the page is nothing but state cards, which belong centred rather than scrolled.
    private var hasAnyData: Bool {
        model.overview.bwh != nil || model.overview.xui != nil
    }

    // MARK: - 页头

    private var hostSubtitle: String? {
        guard let bwh = model.overview.bwh, bwh.usedBytes != nil else { return nil }
        return [hostTitle, hostIP].compactMap { $0 }.joined(separator: " · ")
    }

    /// Server health and client counts, read as one line of facts beside the title.
    /// Counts stay visible even when the last fetch failed; the banner below is what
    /// flags them as possibly stale.
    private var headerFacts: some View {
        HStack(spacing: 18) {
            if let bwh = model.overview.bwh, bwh.usedBytes != nil {
                // Status carries colour *and* text, so health is never colour-only.
                StatusPill(title: bwh.healthLabel, tint: bwh.healthTint)
            }
            if let xui = model.overview.xui,
               let online = xui.onlineCount, let clients = xui.clientCount {
                HeroChip(icon: "person.2", value: "\(online)", label: "在线")
                HeroChip(icon: "rectangle.stack", value: "\(clients)", label: "客户端")
            }
            if model.xuiLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
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
                tint: Theme.warning,
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
            tint: Theme.warning,
            actionTitle: failure.actionTitle,
            action: { failure.resolve(goToSettings: { selectedTab = .settings }, retry: { await model.load() }) }
        )
    }

    private var heroCard: some View {
        let progress = (model.overview.bwh?.usedPercent ?? 0) / 100
        return Panel(padding: 24) {
            VStack(alignment: .leading, spacing: 20) {
                UsageHero(
                    progress: progress,
                    percentage: ByteFormat.percent(model.overview.bwh?.usedPercent),
                    used: ByteFormat.string(model.overview.bwh?.usedBytes),
                    quota: ByteFormat.string(model.overview.bwh?.quotaBytes),
                    remaining: ByteFormat.string(remaining),
                    reset: ByteFormat.daysLeft(resetAt: model.overview.bwh?.resetAt),
                    resetDate: ByteFormat.resetDate(model.overview.bwh?.resetAt),
                    tint: UsageRing.color(for: progress, forecast: model.forecast?.verdict)
                )
                if let forecast = model.forecast {
                    ForecastStrip(forecast: forecast)
                }
            }
        }
    }

    // MARK: - 3X-UI 状态提示

    @ViewBuilder
    private var xuiSection: some View {
        let xui = model.overview.xui
        if xui?.clientCount != nil {
            // The page header already carries the counts; only the failure is news.
            if let error = xui?.error {
                let failure = ServiceFailure(service: "3X-UI", error: error, needsSettings: model.xuiNeedsSettings)
                StatusBanner(
                    title: failure.staleTitle,
                    message: failure.message,
                    icon: failure.icon,
                    tint: Theme.warning,
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
                tint: Theme.warning,
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
            // One row, two equal columns of equal height. The traffic chart absorbs
            // the extra height, so neither panel ends in empty space.
            HStack(alignment: .top, spacing: Theme.gap) {
                MiniTrafficCard(points: history, onOpen: { selectedTab = .vps })
                    .frame(maxWidth: .infinity)
                topClientsCard(clients)
                    .frame(maxWidth: .infinity)
            }
            .fixedSize(horizontal: false, vertical: true)
        } else if !history.isEmpty {
            MiniTrafficCard(points: history, onOpen: { selectedTab = .vps })
        } else if !clients.isEmpty {
            topClientsCard(clients)
        }
    }

    private func topClientsCard(_ clients: [Client]) -> some View {
        let maxUsed = clients.map { $0.used ?? 0 }.max() ?? 0
        return Panel(padding: 0, fillsHeight: true) {
            PanelHeader(title: "用量最高的客户端") {
                PanelLink(title: "查看全部") { selectedTab = .clients }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            VStack(spacing: 0) {
                ForEach(Array(clients.enumerated()), id: \.element.id) { index, client in
                    if index > 0 {
                        CardDivider()
                            .padding(.leading, 20)
                    }
                    TopClientRow(rank: index + 1, client: client, maxUsed: maxUsed)
                }
            }
            .padding(.bottom, 6)
        }
    }

    // MARK: - 服务器概况

    @ViewBuilder
    private var serverSummarySection: some View {
        let items = specItems
        if !items.isEmpty {
            Panel(padding: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    PanelHeader(title: "服务器") {
                        PanelLink(title: "VPS 详情") { selectedTab = .vps }
                    }

                    HStack(alignment: .top, spacing: 20) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            if index > 0 {
                                StatDivider(height: 44)
                            }
                            InfoCell(icon: item.icon, title: item.title, value: item.value, barFraction: item.fraction)
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
    @Environment(AppModel.self) private var model
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
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(Theme.number(12, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 16, alignment: .trailing)

            Text(client.name)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .layoutPriority(1)

            Spacer(minLength: 8)

            StatusPill(title: client.state.title, tint: client.state.swiftColor)
                .frame(width: 52, alignment: .leading)

            // Single accent colour: the state beside the name already carries risk,
            // so colouring the bars too only added noise to the first screen.
            UsageBar(value: fraction, tint: Theme.accent)
                .frame(minWidth: 36, maxWidth: 64)

            Text(ByteFormat.string(client.used))
                .font(Theme.number(13))
                .frame(minWidth: 64, alignment: .trailing)

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
            .opacity(hovered || copied ? 1 : 0)
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .padding(.vertical, 9)
        .background(hovered ? Theme.fill.opacity(0.6) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering in
            hovered = hovering
        }
        .onTapGesture { model.inspectedClientID = client.id }
        .accessibilityAction(named: "查看详情") { model.inspectedClientID = client.id }
    }
}
