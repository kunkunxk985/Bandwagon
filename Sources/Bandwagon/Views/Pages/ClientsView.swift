import SwiftUI

struct ClientsView: View {
    @Environment(AppModel.self) private var model
    @State private var filter: Filter = .all
    @State private var query = ""
    @State private var sort: SortMode = .usage
    @State private var ascending = SortMode.usage.defaultAscending
    @Binding var selectedTab: ContentView.Tab

    enum Filter: String, CaseIterable {
        case all = "全部"
        case online = "在线"
        case warn = "预警"
        case off = "停用"
    }

    enum SortMode: String, CaseIterable {
        case usage = "用量"
        case name = "客户端"
        case recent = "上次在线"
        case quota = "配额"

        /// The direction a first click sorts in: names A→Z, everything else
        /// biggest or most recent first.
        var defaultAscending: Bool { self == .name }
    }

    init(selectedTab: Binding<ContentView.Tab>) {
        _selectedTab = selectedTab
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(title: "客户端", subtitle: headerSubtitle)
                    .pageHeaderInsets()
                if let clients = loadedClients, !clients.isEmpty {
                    header(clients)
                }
                listContent
            }
        }
        .navigationTitle("客户端")
    }

    private var loadedClients: [Client]? {
        guard let xui = model.overview.xui, xui.error == nil else { return nil }
        return xui.clients
    }

    private var headerSubtitle: String? {
        guard let clients = loadedClients, !clients.isEmpty else { return nil }
        return "3X-UI 面板上的 \(clients.count) 个客户端，按用量与配额风险排列"
    }

    // MARK: - 汇总与筛选

    private func header(_ clients: [Client]) -> some View {
        let warnCount = clients.filter { $0.state == .warn }.count
        return VStack(alignment: .leading, spacing: Theme.gap) {
            Panel(padding: 18) {
                HStack(spacing: 20) {
                    SummaryTile(title: "客户端", value: "\(clients.count)")
                    StatDivider(height: 40)
                    SummaryTile(
                        dotColor: ClientState.online.swiftColor,
                        title: "在线",
                        value: "\(clients.filter { $0.online == true }.count)"
                    )
                    StatDivider(height: 40)
                    SummaryTile(
                        dotColor: warnCount > 0 ? ClientState.warn.swiftColor : nil,
                        title: "预警",
                        value: "\(warnCount)",
                        valueColor: warnCount > 0 ? ClientState.warn.swiftColor : .primary
                    )
                    StatDivider(height: 40)
                    SummaryTile(title: "总用量", value: ByteFormat.string(totalUsed(clients)))
                }
            }

            HStack(spacing: 12) {
                Picker("筛选", selection: $filter) {
                    ForEach(Filter.allCases, id: \.self) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 280)

                Spacer(minLength: 12)

                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("搜索名称或邮箱", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: 1)
                )
                .frame(width: 220)
            }
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.bottom, 14)
    }

    private func totalUsed(_ clients: [Client]) -> Int {
        clients.reduce(0) { partial, client in
            let (result, overflow) = partial.addingReportingOverflow(client.used ?? 0)
            return overflow ? Int.max : result
        }
    }

    /// Scale reference for the row bars. Taken from the full client list rather
    /// than the filtered one, so changing a filter never rescales the bars.
    private var busiestUsage: Int {
        model.overview.xui?.clients?.map { $0.used ?? 0 }.max() ?? 0
    }

    // MARK: - 列表

    @ViewBuilder
    private var listContent: some View {
        if model.overview.xui == nil && model.xuiLoading {
            StatusCard(
                title: "正在连接 3X-UI",
                message: "请稍候，正在读取客户端列表…",
                icon: "antenna.radiowaves.left.and.right",
                tint: .secondary
            )
            .padding(.horizontal, Theme.pagePadding)
            .modifier(CenterWhenShort(enabled: true, reserving: Theme.pageHeaderHeight))
        } else if let error = model.overview.xui?.error {
            let failure = ServiceFailure(service: "3X-UI", error: error, needsSettings: model.xuiNeedsSettings)
            StatusCard(
                title: failure.title,
                message: failure.message,
                icon: failure.icon,
                tint: Theme.warning,
                action: { failure.resolve(goToSettings: { selectedTab = .settings }, retry: { await model.load() }) },
                actionTitle: failure.actionTitle
            )
            .padding(.horizontal, Theme.pagePadding)
            .modifier(CenterWhenShort(enabled: true, reserving: Theme.pageHeaderHeight))
        } else if let clients = model.overview.xui?.clients {
            if clients.isEmpty {
                StatusCard(
                    title: model.settings.xuiReady ? "暂无客户端" : "尚未配置 3X-UI",
                    message: model.settings.xuiReady ? "面板已连接，返回的客户端列表为空" : "请在设置中配置 3X-UI 面板地址",
                    icon: "person.2.fill",
                    tint: .secondary,
                    action: { selectedTab = .settings },
                    actionTitle: "前往设置"
                )
                .padding(.horizontal, Theme.pagePadding)
                .modifier(CenterWhenShort(enabled: true, reserving: Theme.pageHeaderHeight))
            } else if visibleClients.isEmpty {
                filteredEmptyState
            } else {
                Panel(padding: 0) {
                    LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                        Section {
                            ForEach(Array(visibleClients.enumerated()), id: \.element.id) { index, client in
                                if index > 0 {
                                    CardDivider()
                                        .padding(.leading, ClientColumns.inset)
                                }
                                ClientRow(client: client, maxUsed: busiestUsage)
                            }
                        } header: {
                            ClientTableHeader(sort: $sort, ascending: $ascending)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
                .padding(.horizontal, Theme.pagePadding)
                .padding(.bottom, Theme.pagePadding)
            }
        } else {
            StatusCard(
                title: "尚未配置 3X-UI",
                message: "请在设置中配置 3X-UI 面板地址",
                icon: "person.2.fill",
                tint: .secondary,
                action: { selectedTab = .settings },
                actionTitle: "前往设置"
            )
            .padding(.horizontal, Theme.pagePadding)
            .modifier(CenterWhenShort(enabled: true, reserving: Theme.pageHeaderHeight))
        }
    }

    private var filteredEmptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text("没有匹配的客户端")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 64)
        .frame(maxWidth: .infinity)
    }

    private var visibleClients: [Client] {
        guard let all = model.overview.xui?.clients else { return [] }
        var list = all.filter { client in
            let hit: Bool
            switch filter {
            case .all: hit = true
            case .online: hit = client.state == .online
            case .warn: hit = client.state == .warn
            case .off: hit = client.state == .off
            }
            guard hit else { return false }
            if query.isEmpty { return true }
            let q = query.lowercased()
            return client.name.lowercased().contains(q) || (client.email?.lowercased().contains(q) ?? false)
        }
        list.sort { lhs, rhs in
            let order = compare(lhs, rhs)
            if order == .orderedSame {
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            return ascending ? order == .orderedAscending : order == .orderedDescending
        }
        return list
    }

    private func compare(_ lhs: Client, _ rhs: Client) -> ComparisonResult {
        func order<T: Comparable>(_ a: T, _ b: T) -> ComparisonResult {
            a < b ? .orderedAscending : (a > b ? .orderedDescending : .orderedSame)
        }
        switch sort {
        case .usage:
            return order(lhs.used ?? 0, rhs.used ?? 0)
        case .name:
            return lhs.name.localizedStandardCompare(rhs.name)
        case .recent:
            // Online now counts as the most recent of all.
            func key(_ client: Client) -> Int { client.online == true ? Int.max : (client.lastOnline ?? 0) }
            return order(key(lhs), key(rhs))
        case .quota:
            return order(lhs.percent ?? -1, rhs.percent ?? -1)
        }
    }
}

/// Column titles, pinned to the top of the table while it scrolls. Widths match
/// `ClientRow` column for column.
private struct ClientTableHeader: View {
    @Binding var sort: ClientsView.SortMode
    @Binding var ascending: Bool

    var body: some View {
        HStack(spacing: ClientColumns.spacing) {
            Text("状态")
                .frame(width: ClientColumns.state, alignment: .leading)
            sortable(.name, alignment: .leading)
                .frame(minWidth: ClientColumns.nameMin, maxWidth: ClientColumns.nameMax, alignment: .leading)
            sortable(.recent, alignment: .leading)
                .frame(width: ClientColumns.lastOnline, alignment: .leading)
            Spacer(minLength: 0)
            Color.clear
                .frame(minWidth: 64, maxWidth: 120, maxHeight: 1)
            sortable(.usage, alignment: .trailing)
                .frame(width: ClientColumns.used, alignment: .trailing)
            sortable(.quota, alignment: .trailing)
                .frame(width: ClientColumns.quota, alignment: .trailing)
            Color.clear
                .frame(width: ClientColumns.copy, height: 1)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, ClientColumns.inset)
        .padding(.vertical, 9)
        .background(Theme.surface)
        .overlay(alignment: .bottom) { CardDivider() }
    }

    /// A column title that sorts by that column; clicking the active column again
    /// flips the direction. The active one is darker and carries the arrow.
    private func sortable(_ mode: ClientsView.SortMode, alignment: HorizontalAlignment) -> some View {
        let active = sort == mode
        return Button {
            if active {
                ascending.toggle()
            } else {
                sort = mode
                ascending = mode.defaultAscending
            }
        } label: {
            HStack(spacing: 3) {
                Text(mode.rawValue)
                Image(systemName: ascending ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .opacity(active ? 1 : 0)
            }
            .foregroundStyle(active ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("按\(mode.rawValue)排序")
        .accessibilityLabel("按\(mode.rawValue)排序")
        .accessibilityValue(active ? (ascending ? "升序" : "降序") : "")
    }
}

private enum ClientColumns {
    static let spacing: CGFloat = 16
    static let inset: CGFloat = 18
    static let used: CGFloat = 72
    static let quota: CGFloat = 96
    static let state: CGFloat = 56
    static let nameMin: CGFloat = 120
    /// Capped so the identity columns (status, name, last online) stay together
    /// on the left and the numbers on the right, instead of the name column
    /// absorbing every spare point of a wide window.
    static let nameMax: CGFloat = 260
    static let lastOnline: CGFloat = 84
    static let copy: CGFloat = 24
}

struct ClientRow: View {
    @Environment(AppModel.self) private var model
    let client: Client
    let maxUsed: Int
    @State private var copied = false
    @State private var hovered = false

    private var utilization: (fraction: Double, percent: Double)? {
        guard let percent = client.percent, percent > 0 else { return nil }
        return (min(1, max(0, percent / 100)), percent)
    }

    /// Bar length encodes how much this client actually moved relative to the
    /// busiest client, so it always agrees with the default "按用量" ordering.
    /// Previously the bar encoded quota share, which contradicted the sort: two
    /// clients at 117 GB drew 23% and 58% bars.
    private var usageFraction: Double {
        guard maxUsed > 0 else { return 0 }
        return min(1, max(0, Double(client.used ?? 0) / Double(maxUsed)))
    }

    /// Bar colour still encodes quota risk, matching the percentage label beside
    /// it. Clients without an individual quota fall back to the accent colour.
    private var usageTint: Color {
        guard let utilization else { return Theme.accent }
        return UsageTint.color(for: utilization.fraction)
    }

    var body: some View {
        HStack(spacing: ClientColumns.spacing) {
            // Status leads the row, dot and word together, so who is online reads
            // down one column beside the names. At the far right it sat a whole
            // window's width away from the name it belonged to.
            StatusPill(title: client.state.title, tint: client.state.swiftColor)
                .frame(width: ClientColumns.state, alignment: .leading)

            // No initial avatar: a grey circle holding "杜" twice and "C" once
            // said nothing the name beside it didn't.
            VStack(alignment: .leading, spacing: 2) {
                Text(client.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if let email = client.email, !email.isEmpty, email != client.name {
                    Text(email)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(minWidth: ClientColumns.nameMin, maxWidth: ClientColumns.nameMax, alignment: .leading)

            Text(client.lastOnlineText())
                .font(.system(size: 12.5))
                .foregroundStyle(client.online == true ? AnyShapeStyle(ClientState.online.swiftColor) : AnyShapeStyle(.secondary))
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: ClientColumns.lastOnline, alignment: .leading)

            Spacer(minLength: 0)

            UsageBar(value: usageFraction, tint: usageTint)
                .frame(minWidth: 64, maxWidth: 120)
                .help("长度＝相对最大用量，颜色＝配额占用风险")

            Text(ByteFormat.string(client.used))
                .font(Theme.number(13))
                .frame(width: ClientColumns.used, alignment: .trailing)

            quotaCell
                .frame(width: ClientColumns.quota, alignment: .trailing)

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
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(copied ? ClientState.online.swiftColor : Color.secondary)
                    .frame(width: ClientColumns.copy, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(copied ? "已复制" : "复制邮箱")
            // Every row carries the same icon, so VoiceOver announced nineteen
            // identical "拷贝" buttons. Name the client in the label.
            .accessibilityLabel(copied ? "已复制 \(client.name) 的邮箱" : "复制 \(client.name) 的邮箱")
            .opacity(hovered || copied ? 1 : 0)
        }
        .padding(.horizontal, ClientColumns.inset)
        .padding(.vertical, 11)
        .background(hovered ? Theme.fill.opacity(0.6) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering in
            hovered = hovering
        }
        // The copy button keeps its own tap; anywhere else opens the detail sheet.
        .onTapGesture { model.inspectedClientID = client.id }
        .accessibilityAction(named: "查看详情") { model.inspectedClientID = client.id }
        .help("查看详情与管理")
    }

    /// Quota share, or the expiry that raised a warning. Without the expiry text a
    /// row could show "预警" beside a low, green bar and leave the reader guessing.
    @ViewBuilder
    private var quotaCell: some View {
        VStack(alignment: .trailing, spacing: 2) {
            if let utilization {
                Text("\(Int(utilization.percent.rounded()))%")
                    .font(Theme.number(12.5, weight: .medium))
                    .foregroundStyle(utilization.fraction >= UsageThreshold.warn ? usageTint : Color.secondary)
            } else {
                Text("—")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
            if let expiryWarning = client.expiryWarning {
                Text(expiryWarning)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(ClientState.warn.swiftColor)
                    .lineLimit(1)
            }
        }
    }
}
