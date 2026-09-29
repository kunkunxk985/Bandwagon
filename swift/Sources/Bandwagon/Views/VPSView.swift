import SwiftUI

struct VPSView: View {
    @Environment(AppModel.self) private var model
    @Binding var selectedTab: ContentView.Tab

    init(selectedTab: Binding<ContentView.Tab>) {
        _selectedTab = selectedTab
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
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
                        tint: .orange,
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
            .padding(28)
            .modifier(CenterWhenShort(enabled: bwh?.usedBytes == nil))
        }
        .navigationTitle("VPS")
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

    // MARK: - 用量概览

    private var heroCard: some View {
        GlassCard(padding: 26, tint: Theme.accent) {
            VStack(alignment: .leading, spacing: 20) {
                UsageHero(
                    progress: (bwh?.usedPercent ?? 0) / 100,
                    percentage: ByteFormat.percent(bwh?.usedPercent),
                    used: ByteFormat.string(bwh?.usedBytes),
                    quota: ByteFormat.string(bwh?.quotaBytes),
                    remaining: ByteFormat.string(remaining),
                    reset: ByteFormat.daysLeft(resetAt: bwh?.resetAt),
                    resetDate: ByteFormat.resetDate(bwh?.resetAt)
                )
                if let forecast = model.forecast {
                    ForecastStrip(forecast: forecast)
                }
                CardDivider()
                // The metrics grid above already states the reset date, so the chip
                // row carries only the host identity.
                HStack(spacing: 10) {
                    HeroChip(
                        dotColor: bwh?.healthTint ?? .secondary,
                        value: heroHost,
                        label: heroIP
                    )
                    Spacer(minLength: 8)
                }
            }
        }
    }

    // MARK: - 系统概况

    private var systemCard: some View {
        GlassCard(padding: 22) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 30, height: 30)
                        .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    Text("系统概况")
                        .font(.system(size: 16, weight: .semibold))
                    Spacer()
                    if let bwh, bwh.status?.isEmpty == false {
                        StatusPill(title: bwh.healthLabel, tint: bwh.healthTint)
                    }
                }

                CardDivider()

                // Two columns. Three filled the width no better — the spare space
                // simply moved behind the third column and the grid became 3/3/2.
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 16, alignment: .leading),
                        GridItem(.flexible(), spacing: 16, alignment: .leading)
                    ],
                    alignment: .leading,
                    spacing: 18
                ) {
                    ForEach(specItems) { item in
                        InfoCell(icon: item.icon, title: item.title, value: item.value, barFraction: item.fraction)
                    }
                }
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
        appendSpecRow(&items, icon: "memorychip", title: "内存", value: ByteFormat.string(bwh?.ramBytes))
        if let diskLabel = diskUsageLabel(total: bwh?.diskBytes, used: bwh?.diskUsedBytes) {
            let fraction: Double? = {
                guard let total = bwh?.diskBytes, total > 0,
                      let used = bwh?.diskUsedBytes, used > 0 else { return nil }
                return min(1, Double(used) / Double(total))
            }()
            items.append(SpecRow(icon: "internaldrive", title: "磁盘", value: diskLabel, fraction: fraction))
        }
        return items
    }

    @ViewBuilder
    private var historyCard: some View {
        let points = model.overview.bwhHistory ?? []
        if points.isEmpty {
            Color.clear
        } else {
            GlassCard(padding: 22, tint: .teal) {
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