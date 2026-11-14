import Foundation

@main
struct UICompositionRegression {
    static func main() throws {
        let theme = try source("Sources/Bandwagon/Views/DesignSystem/Theme.swift")
        let statusViews = try source("Sources/Bandwagon/Views/Components/StatusViews.swift")
        let failureBanner = try source("Sources/Bandwagon/Views/Components/BandwagonFailureBanner.swift")
        let modelPresentation = try source("Sources/Bandwagon/Views/DesignSystem/ModelPresentation.swift")
        let settings = try source("Sources/Bandwagon/Views/Pages/SettingsView.swift")
        let overview = try source("Sources/Bandwagon/Views/Pages/OverviewView.swift")
        let clients = try source("Sources/Bandwagon/Views/Pages/ClientsView.swift")
        let settingsStore = try source("Sources/Bandwagon/Services/SettingsStore.swift")
        let app = try source("Sources/Bandwagon/BandwagonApp.swift")
        let appRoot = try source("Sources/Bandwagon/Views/Shell/AppRootView.swift")
        let onboarding = try source("Sources/Bandwagon/Views/Pages/ConnectionOnboardingView.swift")
        let launchOnboarding = try source("Sources/Bandwagon/Services/LaunchOnboarding.swift")

        require(
            theme.contains("VStack(alignment: .leading, spacing: 0) {\n            content"),
            "Panel must wrap multi-view content in one stack so a section renders as one surface"
        )
        require(
            statusViews.contains("let action: (() -> Void)?") &&
            statusViews.contains("let actionTitle: String?") &&
            statusViews.contains("if let action, let actionTitle"),
            "StatusCard must omit its action button when no action is available"
        )
        require(
            !settings.contains("bwhConnectionOpen") &&
            !settings.contains("bwhCredentialsOpen") &&
            !settings.contains("xuiConnectionOpen") &&
            !settings.contains("xuiCredentialsOpen") &&
            !settings.contains("xuiAdvancedOpen"),
            "Settings must not use nested accordion state"
        )
        let connectionFields = try source("Sources/Bandwagon/Views/Pages/ConnectionFields.swift")
        require(
            occurrences(of: "settingsSection(\"", in: settings) == 3 &&
            settings.contains("settingsSection(\"Bandwagon\"") &&
            settings.contains("settingsSection(\"3X-UI\"") &&
            settings.contains("settingsSection(\"高级\"") &&
            settings.contains("blockHeading(\"连接\")") &&
            settings.contains("blockHeading(\"偏好\")") &&
            connectionFields.contains("labeledField(\"面板地址\"") &&
            connectionFields.contains("labeledCredential(\"用户名\"") &&
            connectionFields.contains("labeledSecret(\"密码\"") &&
            settings.contains("ConnectionFields.bandwagon") &&
            settings.contains("ConnectionFields.xui") &&
            !settings.contains("$draft.xuiApiToken") &&
            !settings.contains("$draft.xuiTwoFactor") &&
            !connectionFields.contains("不在此填写 API Token"),
            "Settings must group connection, preferences, and advanced sections with shared connection fields"
        )
        require(
            settings.contains("PageHeader(title: \"设置\")") &&
            !settings.contains("日常维护连接与偏好") &&
            !settings.contains("当前版本") &&
            !settings.contains("尚未检查") &&
            !settings.contains("refreshHint") &&
            !settings.contains("在系统菜单栏显示套餐用量与预测") &&
            !settings.contains("在搬瓦工流量周期重置时") &&
            !connectionFields.contains("使用面板 Web 登录") &&
            settings.contains("showApiKeyHint: false") &&
            settings.contains("showCredentialHint: false") &&
            settings.contains("Text(\"自动刷新\")") &&
            settings.contains("Text(\"菜单栏\")") &&
            settings.contains("Text(\"流量重置与服务器同步\")") &&
            settings.contains("Text(\"软件更新\")") &&
            settings.contains("检查更新") &&
            settings.contains("StatusPill(") &&
            connectionFields.contains("labeledField(\"面板地址\"") &&
            connectionFields.contains("labeledField(\"VEID\""),
            "Settings cards keep titles, field labels, pills, and actions, without gray helper captions"
        )
        require(
            !overview.contains("action: {},") && !clients.contains("action: {},"),
            "Loading states must not create empty action buttons"
        )

        let contentView = try source("Sources/Bandwagon/Views/Shell/ContentView.swift")
        require(
            overview.contains("@Binding var selectedTab: ContentView.Tab") &&
            overview.contains("selectedTab = .settings") &&
            contentView.contains("OverviewView(selectedTab: $tab)"),
            "Overview authentication errors must navigate to Settings"
        )

        require(
            overview.contains("model.xuiNeedsSettings") &&
            clients.contains("model.xuiNeedsSettings"),
            "Overview and Clients must route typed XUI authentication failures to Settings"
        )

        let vps = try source("Sources/Bandwagon/Views/Pages/VPSView.swift")
        require(
            vps.contains("@Binding var selectedTab: ContentView.Tab") &&
            contentView.contains("VPSView(selectedTab: $tab)") &&
            overview.contains("model.bwhNeedsSettings") &&
            vps.contains("model.bwhNeedsSettings") &&
            overview.contains("!model.settings.bwhReady") &&
            vps.contains("!model.settings.bwhReady"),
            "Bandwagon authentication and unconfigured states must navigate to Settings instead of showing empty quota data"
        )
        require(
            theme.contains("struct UsageHero: View") &&
            overview.contains("UsageHero(") &&
            vps.contains("UsageHero("),
            "Overview and VPS must share a full-width quota composition without dead space"
        )
        let loadedStart = vps.range(of: "private var loadedSections")?.lowerBound ?? vps.endIndex
        let loaded = vps[loadedStart...]
        let loadedEnd = loaded.range(of: "private var heroCard")?.lowerBound ?? loaded.endIndex
        let loadedBody = loaded[..<loadedEnd]
        require(
            (loadedBody.range(of: "heroCard")?.lowerBound ?? loadedBody.endIndex) <
            (loadedBody.range(of: "historyCard")?.lowerBound ?? loadedBody.startIndex) &&
            (loadedBody.range(of: "historyCard")?.upperBound ?? loadedBody.startIndex) <
            (loadedBody.range(of: "systemCard")?.lowerBound ?? loadedBody.startIndex),
            "VPS must show the usage hero, then the traffic trend, then system specs"
        )
        let skeleton = try source("Sources/Bandwagon/Views/DesignSystem/LoadingSkeleton.swift")
        let skeletonStart = skeleton.range(of: "struct VPSLoadingSkeleton")?.lowerBound ?? skeleton.endIndex
        let vpsSkeleton = skeleton[skeletonStart...]
        let skeletonEnd = vpsSkeleton.range(of: "private var systemSkeleton")?.lowerBound ?? vpsSkeleton.endIndex
        let skeletonBody = vpsSkeleton[..<skeletonEnd]
        require(
            (skeletonBody.range(of: "UsageHeroSkeleton()")?.lowerBound ?? skeletonBody.endIndex) <
            (skeletonBody.range(of: "SkeletonBlock(height: 200")?.lowerBound ?? skeletonBody.startIndex) &&
            (skeletonBody.range(of: "SkeletonBlock(height: 200")?.upperBound ?? skeletonBody.startIndex) <
            (skeletonBody.range(of: "systemSkeleton")?.lowerBound ?? skeletonBody.startIndex),
            "VPS loading skeleton must follow the page: usage hero, traffic trend, then system specs"
        )
        require(
            !contentView.contains("Bandwagon v3.0"),
            "Sidebar must not spend space on decorative version microcopy"
        )
        let primaryNav = contentView.range(of: "ForEach(Tab.primary)")
        let sidebarSpacer = contentView.range(of: "Spacer()")
        let pinnedSettings = contentView.range(of: "sidebarItem(.settings)")
        require(
            contentView.contains("static var primary: [Tab]") &&
            contentView.contains("allCases.filter { $0 != .settings }") &&
            primaryNav != nil && sidebarSpacer != nil && pinnedSettings != nil &&
            primaryNav!.upperBound < sidebarSpacer!.lowerBound &&
            sidebarSpacer!.upperBound < pinnedSettings!.lowerBound &&
            contentView.contains(".font(.system(size: 14, weight: tab == item ? .semibold : .regular))") &&
            contentView.contains(".padding(.vertical, 10)") &&
            contentView.contains("VStack(spacing: 4)") &&
            contentView.contains(".padding(.bottom, 26)"),
            "Settings must stay pinned under a spacer, with slightly larger labels and more air under the wordmark"
        )

        let trafficChart = try source("Sources/Bandwagon/Views/Pages/TrafficHistoryChart.swift")
        require(
            trafficChart.contains("ForEach(visibleBuckets)") &&
            !trafficChart.contains("ForEach(Array(visibleBuckets.enumerated()), id: \\.offset)"),
            "Traffic chart marks must use stable bucket identity instead of array offsets"
        )
        require(
            trafficChart.contains("AreaMark(") &&
            trafficChart.contains("xAxisLabels(proxy: proxy, geometry: geometry)") &&
            trafficChart.contains("frame.origin.x + x") &&
            trafficChart.contains(".padding(.trailing, 10)"),
            "Traffic chart must retain shaded data and precisely positioned x-axis labels"
        )

        let components = try source("Sources/Bandwagon/Views/Components/Components.swift")
        require(
            components.contains("struct UsageBar: View") &&
            components.contains("struct StatusPill: View") &&
            components.contains("struct InfoCell: View") &&
            components.contains("struct HeroChip: View") &&
            components.contains("struct SummaryTile: View"),
            "Shared monitoring components must exist for tiles, utilization bars, pills, and chips"
        )
        require(
            clients.contains("UsageBar(") &&
            clients.contains("StatusPill(") &&
            clients.contains("SummaryTile("),
            "Clients page must use the shared utilization bar, state pill, and summary tiles"
        )
        require(
            components.contains("fraction >= UsageThreshold.critical") &&
            components.contains("fraction >= UsageThreshold.warn") &&
            !components.contains("fraction >= 0.9") &&
            !components.contains("fraction >= 0.7"),
            "Utilisation colour must read the shared thresholds instead of its own literals"
        )
        require(
            clients.contains("ClientRow(client: client, maxUsed: busiestUsage)") &&
            clients.contains("UsageBar(value: usageFraction") &&
            clients.contains("private var busiestUsage: Int") &&
            !clients.contains("UsageBar(value: utilization.fraction"),
            "Client bars must scale to the busiest client so they agree with the usage ordering"
        )
        require(
            !clients.contains(".ultraThinMaterial") &&
            !clients.contains(".background(.regularMaterial"),
            "Repeated client rows must not use per-row real-time blur"
        )
        require(
            clients.contains("Text(client.name)") &&
            clients.contains("Text(email)") &&
            !clients.contains("prefix(1)") &&
            clients.contains(".frame(minWidth: 64, maxWidth: 120)"),
            "Client rows lead with name and email (no initial avatar) and shrink the usage bar before names"
        )
        require(
            clients.contains(".accessibilityLabel(copied ? \"已复制 \\(client.name) 的邮箱\"") &&
            overview.contains(".accessibilityLabel(copied ? \"已复制 \\(client.name) 的邮箱\""),
            "Copy buttons must name their client instead of repeating one identical VoiceOver label"
        )
        let miniTraffic = try source("Sources/Bandwagon/Views/Pages/MiniTrafficCard.swift")
        let chartData = try source("Sources/Bandwagon/Models/TrafficChartData.swift")
        require(
            miniTraffic.contains("legend(\"下载\"") &&
            miniTraffic.contains("legend(\"上传\"") &&
            miniTraffic.contains("VStack(alignment: .leading, spacing: 9)"),
            "Mini traffic legends must stay on a separate row at the minimum window size"
        )
        require(
            miniTraffic.contains("sampleCache.buckets(for: points, range: .week)") &&
            trafficChart.contains("sampleCache.buckets(for: points, range: range)") &&
            chartData.contains("TrafficChartData.trimmed(") &&
            !miniTraffic.contains(".suffix(7)") &&
            !trafficChart.contains(".suffix(7)") &&
            trafficChart.contains("TrafficChartData.summary(for: visibleBuckets)"),
            "Mini card and trend chart must share one range definition instead of trimming independently"
        )
        require(
            miniTraffic.contains("@State private var sampleCache = TrafficSampleCache()") &&
            trafficChart.contains("@State private var sampleCache = TrafficSampleCache()"),
            "Both traffic views must memoise their sample derivation; re-reading it per access is the stutter"
        )
        require(
            modelPresentation.contains("var healthTint: Color") &&
            overview.contains("StatusPill(title: bwh.healthLabel, tint: bwh.healthTint)") &&
            vps.contains("bwh.healthTint") &&
            !overview.contains("dotColor: ClientState.online.swiftColor"),
            "Server health must come from the panel status on both pages, never a hardcoded green"
        )
        require(
            overview.contains("InfoCell(") && vps.contains("InfoCell("),
            "Overview and VPS must render spec info cells"
        )
        require(
            (overview.contains("ByteFormat.resetDate(") && vps.contains("ByteFormat.resetDate(")),
            "Quota heroes must show the concrete reset date, not only a relative countdown"
        )

        // A monitoring panel that never re-reads the panel is the whole bug: the
        // window must poll on a timer, top up when it comes back, and stop when hidden.
        require(
            app.contains("model.startAutoRefresh()") &&
            app.contains("model.refreshIfStale()") &&
            app.contains("model.stopAutoRefresh()") &&
            app.contains("keyboardShortcut(\"r\", modifiers: .command)") &&
            appRoot.contains(".task { await model.start() }"),
            "The app must poll on a timer, top up on activation, expose a refresh shortcut, and start from the shell"
        )
        require(
            settings.contains("refreshCard") &&
            settings.contains("$draft.refreshSeconds") &&
            !settings.contains("settingsSection(\"刷新\"") &&
            !settings.contains("saveBar") &&
            !settings.contains("保存并连接") &&
            settings.contains("确认并连接") &&
            !settings.contains("保存并刷新") &&
            !settings.contains("openConfigFolderRow") &&
            settings.contains("trafficResetSyncRow") &&
            settings.contains("onChange(of: draft.refreshSeconds)") &&
            settings.contains("onChange(of: draft.syncClientResetWithServer)"),
            "Refresh and advanced prefs must persist without the global save bar; connections use inline 确认并连接"
        )
        require(
            app.contains("AppRootView()") &&
            appRoot.contains("ConnectionOnboardingView") &&
            appRoot.contains("LaunchOnboarding.shouldShowWizard") &&
            onboarding.contains("跳过") &&
            launchOnboarding.contains("BandwagonHasLaunchedBefore") &&
            clients.contains("title: \"未配置\""),
            "First launch must use a one-time full-screen wizard; Clients must nudge unconfigured 3X-UI to Settings"
        )
        require(
            settings.contains("private var isDirty: Bool { draft != model.settings }") &&
            settings.contains("有未保存的更改") &&
            settings.contains("performSave"),
            "Settings must surface unsaved draft changes and route every save action through one handler"
        )
        require(
            settings.contains("inlineSave: performSave") &&
            settings.contains("saveButtonTitle: \"确认并连接\"") &&
            !settings.contains("inlineSave: nil") &&
            connectionFields.contains("saveButtonTitle: String = \"保存并连接\""),
            "Settings connection cards must expose inline confirm wired to performSave with Settings-specific copy"
        )
        require(
            settingsStore.contains("if let stored = object[\"REFRESH_SECONDS\"]") &&
            settingsStore.contains("object[\"REFRESH_SECONDS\"] = settings.refreshSeconds"),
            "Polling off must survive a round trip, so the read must key off key presence"
        )

        require(
            components.contains("struct ForecastStrip: View") &&
            overview.contains("ForecastStrip(forecast: forecast)") &&
            vps.contains("ForecastStrip(forecast: forecast)") &&
            !overview.contains("model.overview.budget"),
            "Both quota heroes must state whether the cycle will overrun, from the forecast rather than a dead Budget"
        )

        // A monitoring panel that blanks itself on a transient failure is worse than
        // one that shows stale numbers and says so.
        require(
            statusViews.contains("struct StatusBanner: View") &&
            modelPresentation.contains("var staleTitle: String") &&
            modelPresentation.contains("数据可能已过期") &&
            failureBanner.contains("failure.staleTitle") &&
            overview.contains("BandwagonFailureBanner(") &&
            vps.contains("BandwagonFailureBanner(") &&
            !overview.contains("private func bwhBanner") &&
            !vps.contains("private func bwhBanner"),
            "A failed refresh must degrade to a banner, worded as stale, instead of replacing the dashboard"
        )
        require(
            theme.contains("var tint: Color = Theme.accent") &&
            !theme.contains("AngularGradient(") &&
            components.contains("forecast == .over") &&
            components.contains("forecast == .tight") &&
            overview.contains("tint: UsageRing.color(for: progress, forecast: model.forecast?.verdict)") &&
            vps.contains("tint: UsageRing.color(for: progress, forecast: model.forecast?.verdict)"),
            "The hero ring must take its colour from usage and the forecast instead of a fixed gradient"
        )
        require(
            components.contains("struct ForecastTimeline: View") &&
            components.contains("ForecastTimeline(forecast: forecast)") &&
            overview.contains("ForecastStrip(forecast: forecast)") &&
            vps.contains("ForecastStrip(forecast: forecast)"),
            "The forecast must be drawn as a today-to-reset timeline under its sentence on both quota heroes"
        )
        require(
            clients.contains("ClientTableHeader(sort: $sort, ascending: $ascending)") &&
            clients.contains("private func sortable(") &&
            clients.contains("ascending.toggle()") &&
            !clients.contains("private var sortMenu"),
            "Client columns must sort by clicking their headers, with a second click flipping the direction"
        )
        // Three pages each carrying their own copy of the same four decisions is how
        // they drift apart; they must share one rule instead.
        require(
            modelPresentation.contains("struct ServiceFailure") &&
            !overview.contains("private func errorTitle") &&
            !clients.contains("private func errorTitle") &&
            !overview.contains("NeedsSettings ?") &&
            !vps.contains("NeedsSettings ?"),
            "Service failures must be presented from one shared rule, not per page"
        )
        // The traffic card used to be capped at 430pt while its chart was a fixed
        // height, so it sat narrower and shorter than the clients card beside it.
        require(
            !overview.contains("maxWidth: 430") &&
            overview.contains("Panel(padding: 0, fillsHeight: true)") &&
            miniTraffic.contains("fillsHeight: true") &&
            miniTraffic.contains("onGeometryChange") &&
            miniTraffic.contains(".frame(minHeight: 116, maxHeight: .infinity"),
            "The overview row must be two equal columns whose cards share one height"
        )
        // The y-axis must cover the single-direction series it plots, while the peak
        // tile sits beside a combined average and has to match it. One figure cannot
        // serve both: it made the peak read as smaller than the average.
        require(
            trafficChart.contains("Double(summary.peak) * 1.18") &&
            trafficChart.contains("TrafficChartData.valueLabel(summary.combinedPeak)"),
            "The peak tile must report the combined figure while the y-axis keeps the per-direction one"
        )
        require(
            overview.contains("usageLabel(total: bwh?.ramBytes") &&
            vps.contains("usageLabel(total: bwh?.ramBytes") &&
            !overview.contains("diskUsageLabel"),
            "Memory and disk cells must share one usage formatter"
        )
        require(
            contentView.contains("accessibilityReduceMotion") &&
            (clients.contains("accessibilityReduceMotion") || !clients.contains(".animation(")) &&
            settings.contains("accessibilityReduceMotion") &&
            trafficChart.contains("accessibilityReduceMotion"),
            "Reduce Motion must be honoured wherever the app animates"
        )
        require(
            settings.contains("frame(maxHeight: isOpen.wrappedValue ? .infinity : 0") &&
            settings.contains(".compositingGroup()") &&
            settings.contains(".clipShape(RoundedRectangle(cornerRadius: Theme.panelRadius"),
            "Settings disclosure sections must keep expand/collapse inside the panel bounds"
        )
        require(
            miniTraffic.contains("return \"今日\"") &&
            trafficChart.contains("return \"今日\"") &&
            clients.contains("client.expiryWarning"),
            "Partial-day bars and expiry-driven warnings must be named, not left to guesswork"
        )
        require(
            !clients.contains("DateFormatter()") &&
            !miniTraffic.contains("DateFormatter()") &&
            !trafficChart.contains("DateFormatter()") &&
            !contentView.contains("DateFormatter()"),
            "Formatters must be cached, not rebuilt per row per frame"
        )

        let xuiClient = try source("Sources/Bandwagon/Services/XUIClient.swift")
        let appModel = try source("Sources/Bandwagon/Services/AppModel.swift")
        require(
            !clients.contains("serverResetSyncBar") &&
            !clients.contains("流量重置与服务器同步") &&
            !clients.contains("在设置中管理") &&
            !clients.contains("setSyncClientResetWithServer") &&
            settings.contains("$draft.syncClientResetWithServer") &&
            settings.contains("trafficResetSyncRow") &&
            xuiClient.contains("func resetAllClientsTraffic(") &&
            xuiClient.contains("func normalizeBuiltInTrafficResetToNever(") &&
            appModel.contains("func coordinateServerResetSync()"),
            "Traffic reset sync is configured only in Settings; Clients shows no sync UI"
        )
        require(
            !overview.contains("3X-UI 已连接") &&
            !overview.contains("面板运行正常") &&
            !overview.contains("查看客户端") &&
            overview.contains("xuiSection") &&
            overview.contains("if let xui = model.overview.xui, let error = xui.error") &&
            !overview.contains("else { return }"),
            "Overview must omit the healthy 3X-UI status strip and still handle XUI failures"
        )

        print("PASS unified cards, optional actions, flat settings, error navigation, quota composition, stable chart marks, shared monitoring components, refresh cadence, overrun verdicts, stale-data banners, ring tint, reduce motion, and cached formatters")
    }

    private static func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    private static func occurrences(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            print("FAIL \(message)")
            exit(1)
        }
    }
}
