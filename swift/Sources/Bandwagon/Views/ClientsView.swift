import SwiftUI

struct ClientsView: View {
    @Environment(AppModel.self) private var model
    @State private var filter: Filter = .all
    @State private var query = ""
    @State private var sort: SortMode = .usage
    @Binding var selectedTab: ContentView.Tab

    enum Filter: String, CaseIterable {
        case all = "全部"
        case online = "在线"
        case warn = "预警"
        case off = "停用"
    }

    enum SortMode: String, CaseIterable {
        case usage = "按用量"
        case name = "按名称"
        case recent = "按最近在线"
    }

    init(selectedTab: Binding<ContentView.Tab>) {
        _selectedTab = selectedTab
    }

    var body: some View {
        VStack(spacing: 0) {
            if let clients = loadedClients, !clients.isEmpty {
                header(clients)
            }
            listContent
        }
        .navigationTitle("客户端")
    }

    private var loadedClients: [Client]? {
        guard let xui = model.overview.xui, xui.error == nil else { return nil }
        return xui.clients
    }

    // MARK: - 汇总与筛选

    private func header(_ clients: [Client]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                SummaryTile(icon: "person.2.fill", tint: Theme.accent, title: "客户端", value: "\(clients.count)")
                SummaryTile(
                    dotColor: ClientState.online.swiftColor,
                    title: "在线",
                    value: "\(clients.filter { $0.online == true }.count)"
                )
                SummaryTile(
                    icon: "exclamationmark.triangle.fill",
                    tint: clients.contains { $0.state == .warn } ? ClientState.warn.swiftColor : Color.secondary,
                    title: "预警",
                    value: "\(clients.filter { $0.state == .warn }.count)"
                )
                SummaryTile(icon: "chart.bar.fill", tint: Theme.accent, title: "总用量", value: ByteFormat.string(totalUsed(clients)))
            }

            CardDivider()

            HStack(spacing: 12) {
                Picker("", selection: $filter) {
                    ForEach(Filter.allCases, id: \.self) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)

                Spacer(minLength: 12)

                sortMenu

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TextField("搜索客户端", text: $query)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
                )
                .frame(width: 200)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 18)
        .padding(.bottom, 16)
    }

    private var sortMenu: some View {
        Menu {
            ForEach(SortMode.allCases, id: \.self) { mode in
                Button {
                    sort = mode
                } label: {
                    if sort == mode {
                        Label(mode.rawValue, systemImage: "checkmark")
                    } else {
                        Text(mode.rawValue)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 10, weight: .semibold))
                Text(sort.rawValue)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.05), in: Capsule())
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
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
            .padding(.horizontal, 28)
        } else if let error = model.overview.xui?.error {
            let failure = ServiceFailure(service: "3X-UI", error: error, needsSettings: model.xuiNeedsSettings)
            StatusCard(
                title: failure.title,
                message: failure.message,
                icon: failure.icon,
                tint: .orange,
                action: { failure.resolve(goToSettings: { selectedTab = .settings }, retry: { await model.load() }) },
                actionTitle: failure.actionTitle
            )
            .padding(.horizontal, 28)
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
                .padding(.horizontal, 28)
            } else if visibleClients.isEmpty {
                filteredEmptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(visibleClients) { client in
                            ClientRow(client: client, maxUsed: busiestUsage)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 28)
                }
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
            .padding(.horizontal, 28)
        }
    }

    private var filteredEmptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)
            Text("没有匹配的客户端")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        switch sort {
        case .usage:
            list.sort { ($0.used ?? 0) > ($1.used ?? 0) }
        case .name:
            list.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .recent:
            list.sort { ($0.lastOnline ?? 0) > ($1.lastOnline ?? 0) }
        }
        return list
    }
}

struct ClientRow: View {
    let client: Client
    let maxUsed: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        HStack(spacing: 14) {
            Text(String(client.name.prefix(1)))
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(client.state.swiftColor)
                .frame(width: 38, height: 38)
                .background(
                    LinearGradient(
                        colors: [client.state.swiftColor.opacity(0.20), client.state.swiftColor.opacity(0.07)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(client.state.swiftColor.opacity(0.22), lineWidth: 0.8)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(client.name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .layoutPriority(1)
                if let email = client.email, !email.isEmpty, email != client.name {
                    Text(email)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            UsageBar(value: usageFraction, tint: usageTint, height: 6)
                .frame(minWidth: 64, maxWidth: 120)
                .help("长度＝相对最大用量，颜色＝配额占用风险")

            VStack(alignment: .trailing, spacing: 3) {
                Text(ByteFormat.string(client.used))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .monospacedDigit()
                if let utilization {
                    Text("\(Int(utilization.percent.rounded()))%")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(UsageTint.color(for: utilization.fraction))
                }
                if let expiryWarning = client.expiryWarning {
                    // Without this the row shows "预警" beside a green, low bar and
                    // leaves the reader to guess what actually triggered it.
                    Text(expiryWarning)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(ClientState.warn.swiftColor)
                        .lineLimit(1)
                }
            }
            .frame(minWidth: 62, alignment: .trailing)

            StatusPill(title: client.state.title, tint: client.state.swiftColor)
                .frame(minWidth: 64)

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
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(copied ? "已复制" : "复制邮箱")
            // Every row carries the same icon, so VoiceOver announced nineteen
            // identical "拷贝" buttons. Name the client in the label.
            .accessibilityLabel(copied ? "已复制 \(client.name) 的邮箱" : "复制 \(client.name) 的邮箱")
            .opacity(hovered || copied ? 1 : 0.6)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(hovered ? 0.065 : 0.032))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            hovered ? Theme.accent.opacity(0.35) : Color.primary.opacity(0.11),
                            Color.primary.opacity(0.035)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(hovered ? 0.075 : 0.025), radius: hovered ? 10 : 3, x: 0, y: hovered ? 5 : 1)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: hovered)
        .onHover { hovering in
            hovered = hovering
        }
    }
}