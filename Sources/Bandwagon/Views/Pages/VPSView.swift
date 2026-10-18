import SwiftUI

struct VPSView: View {
    @Environment(AppModel.self) private var model
    @Binding var selectedTab: ContentView.Tab

    init(selectedTab: Binding<ContentView.Tab>) {
        _selectedTab = selectedTab
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(title: "VPS", subtitle: headerSubtitle) {
                    if let bwh, bwh.usedBytes != nil {
                        StatusPill(title: bwh.healthLabel, tint: bwh.healthTint)
                    }
                }
                .pageHeaderInsets()

                pageContent
                    .padding(.horizontal, Theme.pagePadding)
                    .padding(.bottom, Theme.pagePadding)
                    .modifier(CenterWhenShort(enabled: bwh?.usedBytes == nil, reserving: Theme.pageHeaderHeight))
            }
        }
        .navigationTitle("VPS")
    }

    private var headerSubtitle: String? {
        guard bwh?.usedBytes != nil else { return nil }
        return [heroHost, heroIP, bwh?.location].compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }.joined(separator: " · ")
    }

    private var pageContent: some View {
            VStack(alignment: .leading, spacing: Theme.gap) {
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
                    // Keep the last good numbers on screen; a failure is a banner,
                    // not a reason to blank the page.
                    if let error = bwh?.error {
                        bwhBanner(error)
                    }
                    heroCard
                    systemCard
                    historyCard
                } else if let error = bwh?.error {
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
                        message: "正在获取套餐、规格与流量信息…",
                        icon: "antenna.radiowaves.left.and.right",
                        tint: .secondary
                    )
                }
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

    // MARK: - 用量概览

    private var heroCard: some View {
        let progress = (bwh?.usedPercent ?? 0) / 100
        return Panel(padding: 24) {
            VStack(alignment: .leading, spacing: 20) {
                UsageHero(
                    progress: progress,
                    percentage: ByteFormat.percent(bwh?.usedPercent),
                    used: ByteFormat.string(bwh?.usedBytes),
                    quota: ByteFormat.string(bwh?.quotaBytes),
                    remaining: ByteFormat.string(remaining),
                    reset: ByteFormat.daysLeft(resetAt: bwh?.resetAt),
                    resetDate: ByteFormat.resetDate(bwh?.resetAt),
                    tint: UsageRing.color(for: progress, forecast: model.forecast?.verdict)
                )
                if let forecast = model.forecast {
                    ForecastStrip(forecast: forecast)
                }
            }
        }
    }

    // MARK: - 系统概况

    /// Spec sheet: label-over-value cells in two columns, rows split by hairlines.
    /// The page header already names the host and its health.
    private var systemCard: some View {
        let rows = stride(from: 0, to: specItems.count, by: 2).map { start in
            Array(specItems[start..<min(start + 2, specItems.count)])
        }
        return Panel(padding: 0) {
            PanelHeader(title: "系统概况")
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 4)

            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 {
                    CardDivider()
                        .padding(.horizontal, 20)
                }
                HStack(alignment: .top, spacing: 20) {
                    ForEach(row) { item in
                        InfoCell(icon: item.icon, title: item.title, value: item.value, barFraction: item.fraction)
                    }
                    if row.count == 1 {
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
        }
    }

    private var specItems: [SpecRow] {
        var items: [SpecRow] = []
        appendSpecRow(&items, icon: "globe", title: "位置", value: bwh?.location)
        appendSpecRow(&items, icon: "network", title: "IP 地址", value: heroIP)
        appendSpecRow(&items, icon: "point.3.connected.trianglepath.dotted", title: "节点", value: bwh?.node)
        appendSpecRow(&items, icon: "desktopcomputer", title: "系统", value: bwh?.os)
        appendSpecRow(&items, icon: "shippingbox", title: "套餐", value: bwh?.plan)
        appendSpecRow(&items, icon: "cpu", title: "虚拟化", value: bwh?.vmType)
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

    @ViewBuilder
    private var historyCard: some View {
        let points = model.overview.bwhHistory ?? []
        if points.isEmpty {
            Color.clear
        } else {
            Panel(padding: 20) {
                TrafficHistoryChart(points: points)
            }
        }
    }

    // MARK: - 数据辅助

    private var bwh: BWHOverview? { model.overview.bwh }

    private var remaining: Int? {
        guard let used = bwh?.usedBytes, let quota = bwh?.quotaBytes else { return nil }
        return max(0, quota - used)
    }

    private var heroHost: String {
        if let hostname = bwh?.hostname, !hostname.isEmpty { return hostname }
        return "已连接"
    }

    private var heroIP: String? {
        guard let ip = bwh?.ip, !ip.isEmpty else { return nil }
        return ip
    }
}