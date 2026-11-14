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

    private var headerSubtitle: String? { nil }

    // MARK: - 汇总与筛选

    private func header(_ clients: [Client]) -> some View {
        let warnCount = clients.filter(\.isWarned).count
        return VStack(alignment: .leading, spacing: Theme.gap) {
            Panel(padding: 18) {
                HStack(spacing: 20) {
                    SummaryTile(title: "客户端", value: "\(clients.count)")
                    StatDivider(height: 40)
                    SummaryTile(
                        dotColor: ClientState.online.swiftColor,
                        title: "在线",
                        value: "\(clients.filter(\.isConnected).count)"
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
                        .onKeyPress(.escape) {
                            if !query.isEmpty {
                                query = ""
                                return .handled
                            }
                            return .ignored
                        }
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("清空搜索")
                        .accessibilityLabel("清空搜索")
                    }
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
            ClientsLoadingSkeleton()
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
                    title: model.settings.xuiReady ? "暂无客户端" : "未配置",
                    message: model.settings.xuiReady ? "面板已连接，返回的客户端列表为空" : "请在设置中填写 3X-UI 面板地址与账号",
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
                title: "未配置",
                message: "请在设置中填写 3X-UI 面板地址与账号",
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
            // 在线 follows the connection, not the exclusive pill. A warned client
            // who is still online belongs here and in 预警.
            case .online: hit = client.isConnected
            case .warn: hit = client.isWarned
            case .off: hit = client.isDeactivated
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
            // The column shows the cap. Unlimited (0) sorts as the largest.
            func cap(_ client: Client) -> Int {
                let total = client.total ?? 0
                return total > 0 ? total : Int.max
            }
            return order(cap(lhs), cap(rhs))
        }
    }
}

/// Column titles, pinned to the top of the table while it scrolls. The same
/// `ClientColumnLayout` as `ClientRow`, so a header stays over its column when
/// the window grows.
private struct ClientTableHeader: View {
    @Binding var sort: ClientsView.SortMode
    @Binding var ascending: Bool

    var body: some View {
        ClientColumnLayout {
            Text("状态")
                .frame(maxWidth: .infinity, alignment: .leading)
            sortable(.name, alignment: .leading)
            sortable(.recent, alignment: .leading)
            sortable(.usage, alignment: .leading)
            sortable(.quota, alignment: .leading)
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("按\(mode.rawValue)排序")
        .accessibilityLabel("按\(mode.rawValue)排序")
        .accessibilityValue(active ? (ascending ? "升序" : "降序") : "")
    }
}

private enum ClientColumns {
    static let inset = CGFloat(ClientColumnShare.inset)
}

/// One point size for the clients-table row body. Status, name, last online,
/// the usage figures, and the quota all use it, matching `Theme.body`, so none
/// of them reads as a stray larger or smaller label. The email under the name
/// stays smaller; it is a second line, not another column.
private enum ClientRowTypography {
    static let size: CGFloat = 13
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

    /// Bar colour still encodes quota risk. Clients without an individual quota
    /// fall back to the accent colour. The number beside the bar is the used total.
    private var usageTint: Color {
        guard let utilization else { return Theme.accent }
        return UsageTint.color(for: utilization.fraction)
    }

    var body: some View {
        ClientColumnLayout {
            // Status leads the row, dot and word together, so who is online reads
            // down one column beside the names.
            StatusPill(title: client.state.title, tint: client.state.swiftColor, size: ClientRowTypography.size)
                .frame(maxWidth: .infinity, alignment: .leading)

            // No initial avatar: a grey circle holding "杜" twice and "C" once
            // said nothing the name beside it didn't.
            VStack(alignment: .leading, spacing: 2) {
                Text(client.name)
                    .font(.system(size: ClientRowTypography.size, weight: .medium))
                    .lineLimit(1)
                if let email = client.email, !email.isEmpty, email != client.name {
                    Text(email)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(client.lastOnlineText())
                .font(Theme.number(ClientRowTypography.size, weight: .medium))
                .foregroundStyle(client.isConnected ? AnyShapeStyle(ClientState.online.swiftColor) : AnyShapeStyle(.secondary))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .leading)

            usageLine

            Text(client.quotaLabel)
                .font(Theme.number(ClientRowTypography.size, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help("配额上限")

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
                    .frame(width: CGFloat(ClientColumnShare.copy.minimum), height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(copied ? "已复制" : "复制邮箱")
            // Every row carries the same icon, so VoiceOver announced nineteen
            // identical "拷贝" buttons. Name the client in the label.
            .accessibilityLabel(copied ? "已复制 \(client.name) 的邮箱" : "复制 \(client.name) 的邮箱")
            .opacity(hovered || copied ? 1 : 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    /// Bar, used total, then upload and download on the same line. The bar takes
    /// the spare width. The figures keep a fixed gap, and a little trailing room
    /// separates the download figure from the quota, without stacking or adding a column.
    private var usageLine: some View {
        HStack(spacing: 6) {
            UsageBar(value: usageFraction, tint: usageTint)
                .frame(minWidth: 28, maxWidth: .infinity)
                .help("长度＝相对最大用量，颜色＝配额占用风险")
            HStack(spacing: CGFloat(ClientColumnShare.usageTokenGap)) {
                Text(ByteFormat.string(client.used))
                    .font(Theme.number(ClientRowTypography.size, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .layoutPriority(1)
                directionMark("↑", bytes: client.up, access: "上传")
                directionMark("↓", bytes: client.down, access: "下载")
            }
            .layoutPriority(1)
            .padding(.trailing, CGFloat(ClientColumnShare.usageQuotaPadding))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func directionMark(_ symbol: String, bytes: Int?, access: String) -> some View {
        HStack(spacing: 2) {
            Text(symbol)
                .font(.system(size: ClientRowTypography.size, weight: .medium))
                .foregroundStyle(.secondary)
            Text(ByteFormat.compact(bytes))
                .font(Theme.number(ClientRowTypography.size, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .layoutPriority(1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(access) \(ByteFormat.compact(bytes))")
    }
}

/// Shares one row across the clients columns. Header and body both use it, so
/// they stay aligned, and a wider window widens the columns instead of leaving
/// an empty band on the right.
struct ClientColumnLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let width = resolvedWidth(proposal)
        let widths = columnWidths(available: width, count: subviews.count)
        var height: CGFloat = 0
        for (offset, subview) in subviews.enumerated() {
            let columnWidth = offset < widths.count ? widths[offset] : 0
            let measured = subview.sizeThatFits(
                ProposedViewSize(width: columnWidth, height: proposal.height)
            ).height
            height = max(height, measured)
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let widths = columnWidths(available: bounds.width, count: subviews.count)
        var x = bounds.minX
        for (offset, subview) in subviews.enumerated() {
            let columnWidth = offset < widths.count ? widths[offset] : 0
            subview.place(
                at: CGPoint(x: x, y: bounds.midY),
                anchor: .leading,
                proposal: ProposedViewSize(width: columnWidth, height: bounds.height)
            )
            x += columnWidth + CGFloat(ClientColumnShare.spacing)
        }
    }

    private func resolvedWidth(_ proposal: ProposedViewSize) -> CGFloat {
        if let proposed = proposal.width, proposed.isFinite, proposed > 0 {
            return proposed
        }
        return CGFloat(ClientColumnShare.minimumRowWidth)
    }

    private func columnWidths(available: CGFloat, count: Int) -> [CGFloat] {
        if count == ClientColumnShare.columns.count {
            return ClientColumnShare.widths(available: Double(available)).map { CGFloat($0) }
        }
        guard count > 0 else { return [] }
        let gaps = CGFloat(ClientColumnShare.spacing) * CGFloat(count - 1)
        let each = max(0, available - gaps) / CGFloat(count)
        return Array(repeating: each, count: count)
    }
}
