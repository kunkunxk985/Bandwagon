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
            case .overview: "square.grid.2x2.fill"
            case .vps: "server.rack"
            case .clients: "person.2.fill"
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
                // Reduce Motion: keep the cross-fade, drop the slide.
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .trailing)))
            }
            .toolbarBackground(.hidden, for: .windowToolbar)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    HStack(spacing: 10) {
                        if let fetchedAt = model.overview.fetchedAt {
                            // Ticks, so the age stays honest while the window sits
                            // open, and falls back to a date once it is a day old.
                            TimelineView(.periodic(from: .now, by: 30)) { context in
                                Text(Self.updatedLabel(fetchedAt, now: context.date))
                                    .font(.system(size: 11, weight: .medium))
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
                    }
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .background(WindowChrome())
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: tab)
    }

    private static func updatedLabel(_ timestamp: Double, now: Date) -> String {
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
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text("B")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(
                            LinearGradient(
                                colors: [Theme.accent, Theme.accent.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )
                    Text("Bandwagon")
                        .font(.system(size: 15, weight: .semibold))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 14)

            Divider()
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            VStack(spacing: 2) {
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
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                    Text(error)
                        .font(.system(size: 11))
                        .lineLimit(2)
                }
                .foregroundStyle(.orange)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal, 10)
                .padding(.bottom, 16)
            }
        }
        .background {
            VisualEffectView(material: .sidebar)
                .ignoresSafeArea()
        }
        .navigationSplitViewColumnWidth(min: 196, ideal: 214, max: 232)
    }

    private var pageBackground: some View {
        ZStack {
            VisualEffectView(material: .underWindowBackground, blendingMode: .withinWindow)
            RadialGradient(
                colors: [Theme.accent.opacity(0.12), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 520
            )
            RadialGradient(
                colors: [Color.cyan.opacity(0.08), .clear],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 420
            )
        }
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
            HStack(spacing: 12) {
                Image(systemName: item.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 18)
                Text(item.title)
                    .font(.system(size: 13, weight: tab == item ? .semibold : .regular))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                tab == item
                ? Theme.accent.opacity(0.14)
                : (isHovered ? Color.primary.opacity(0.06) : Color.clear),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        tab == item ? Theme.accent.opacity(0.28) : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(tab == item ? Theme.accent : .primary)
    }
}
