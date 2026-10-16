import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tab: Tab = .overview
    @State private var sidebarHover: Tab?

    enum Tab: String, Hashable, CaseIterable, Identifiable {
        case overview, vps, clients, settings
        var id: String { rawValue }

        var title: String {
            switch self {
            case .overview: "总览"
            case .vps: "VPS"
            case .clients: "客户端"
            case .settings: "设置"
            }
        }

        var icon: String {
            switch self {
            case .overview: "square.grid.2x2"
            case .vps: "server.rack"
            case .clients: "person.2"
            case .settings: "gearshape"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            ZStack {
                pageBackground
                Group {
                    switch tab {
                    case .overview: OverviewView(selectedTab: $tab)
                    case .vps: VPSView(selectedTab: $tab)
                    case .clients: ClientsView(selectedTab: $tab)
                    case .settings: SettingsView()
                    }
                }
                // A plain cross-fade; sliding whole pages was more motion than a tab
                // switch deserves.
                .transition(.opacity)
            }
            // A solid bar in the canvas colour: pages scroll beneath it instead of
            // their text running into the toolbar's.
            .toolbarBackground(Theme.canvas, for: .windowToolbar)
            .toolbarBackground(.visible, for: .windowToolbar)
            // Each page draws its own large title; the toolbar keeps only the
            // freshness label and refresh.
            .toolbar(removing: .title)
            .toolbar {
                RefreshToolbar(model: model)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .background(WindowChrome())
        .sheet(isPresented: Binding(
            get: { model.inspectedClientID != nil },
            set: { if !$0 { model.inspectedClientID = nil } }
        )) {
            if let id = model.inspectedClientID {
                ClientDetailSheet(clientID: id)
                    .environment(model)
            }
        }
        .task {
            if DevSnapshot.directory != nil {
                await DevSnapshot.run(model: model) { tab = $0 }
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: tab)
    }

    static func updatedLabel(_ timestamp: Double, now: Date) -> String {
        let date = Date(timeIntervalSince1970: timestamp)
        let age = now.timeIntervalSince(date)
        if age < 60 { return "更新于 刚刚" }
        if age < 3600 { return "更新于 \(Int(age / 60)) 分钟前" }
        if Calendar.current.isDate(date, inSameDayAs: now) {
            return "更新于 \(DateFormats.string("HH:mm", date))"
        }
        return "更新于 \(DateFormats.string("M/d HH:mm", date))"
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text("Bandwagon")
                    .font(.system(size: 14, weight: .semibold))
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 18)

            VStack(spacing: 1) {
                ForEach(Tab.allCases) { item in
                    SidebarButton(item: item, tab: $tab, isHovered: sidebarHover == item)
                        .onHover { hovering in
                            if hovering { sidebarHover = item } else if sidebarHover == item { sidebarHover = nil }
                        }
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            if let error = model.error {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.warning)
                    Text(error)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(.horizontal, 10)
                .padding(.bottom, 14)
            }
        }
        .background {
            VisualEffectView(material: .sidebar)
                .ignoresSafeArea()
        }
        .navigationSplitViewColumnWidth(min: 196, ideal: 214, max: 232)
    }

    private var pageBackground: some View {
        Theme.canvas
            .ignoresSafeArea()
    }
}

private struct SidebarButton: View {
    let item: ContentView.Tab
    @Binding var tab: ContentView.Tab
    var isHovered: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : .interactiveSpring(response: 0.18, dampingFraction: 0.9)) {
                tab = item
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(tab == item ? Theme.accent : Color.secondary)
                    .frame(width: 18)
                Text(item.title)
                    .font(.system(size: 13, weight: tab == item ? .semibold : .regular))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                tab == item
                ? Theme.accent.opacity(0.12)
                : (isHovered ? Theme.fill : Color.clear),
                in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(tab == item ? .isSelected : [])
    }
}

/// Freshness label and refresh button, pushed to the trailing edge. With the title
/// removed the toolbar would otherwise pack them against the sidebar toggle.
private struct RefreshToolbar: ToolbarContent {
    let model: AppModel

    var body: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarSpacer(.flexible)
        }
        ToolbarItem(placement: .automatic) {
            HStack(spacing: 10) {
                if let fetchedAt = model.overview.fetchedAt {
                    // Ticks, so the age stays honest while the window sits
                    // open, and falls back to a date once it is a day old.
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
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(model.loading)
                .help("刷新 (⌘R)")
            }
        }
    }
}
