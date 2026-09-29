import Foundation

@main
struct UICompositionRegression {
    static func main() throws {
        let theme = try source("Sources/Bandwagon/Views/Theme.swift")
        let statusViews = try source("Sources/Bandwagon/Views/StatusViews.swift")
        let modelPresentation = try source("Sources/Bandwagon/Views/ModelPresentation.swift")
        let settings = try source("Sources/Bandwagon/Views/SettingsView.swift")
        let overview = try source("Sources/Bandwagon/Views/OverviewView.swift")
        let clients = try source("Sources/Bandwagon/Views/ClientsView.swift")
        let settingsStore = try source("Sources/Bandwagon/Services/SettingsStore.swift")
        let app = try source("Sources/Bandwagon/BandwagonApp.swift")

        require(
            theme.contains("VStack(alignment: .leading, spacing: 0) {\n            content"),
            "GlassCard must wrap multi-view content in one stack so a section renders as one surface"
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
        require(
            occurrences(of: "settingsSection(\"", in: settings) == 2 &&
            settings.contains("settingsSection(\"Bandwagon\"") &&
            settings.contains("settingsSection(\"3X-UI\""),
            "Settings must expose exactly two independent sibling sections"
        )
        require(
            !overview.contains("action: {},") && !clients.contains("action: {},"),
            "Loading states must not create empty action buttons"
        )

        let contentView = try source("Sources/Bandwagon/Views/ContentView.swift")
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

        let vps = try source("Sources/Bandwagon/Views/VPSView.swift")
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
        require(
            !contentView.contains("Bandwagon v3.0"),
            "Sidebar must not spend space on decorative version microcopy"
        )

        let trafficChart = try source("Sources/Bandwagon/Views/TrafficHistoryChart.swift")
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

        let components = try source("Sources/Bandwagon/Views/Components.swift")
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
            clients.contains("Text(String(client.name.prefix(1)))") &&
            clients.contains(".frame(minWidth: 64, maxWidth: 120)"),
            "Client rows must show distinct identity and shrink the usage bar before names"
        )
        require(
            clients.contains(".accessibilityLabel(copied ? \"已复制 \\(client.name) 的邮箱\"") &&
            overview.contains(".accessibilityLabel(copied ? \"已复制 \\(client.name) 的邮箱\""),
            "Copy buttons must name their client instead of repeating one identical VoiceOver label"
        )
        let miniTraffic = try source("Sources/Bandwagon/Views/MiniTrafficCard.swift")
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
            app.contains("keyboardShortcut(\"r\", modifiers: .command)"),
            "The app must poll on a timer, top up on activation, and expose a refresh shortcut"
        )
        require(
            settings.contains("refreshCard") &&
            settings.contains("$draft.refreshSeconds") &&
            !settings.contains("settingsSection(\"刷新\""),
            "Refresh cadence must be adjustable from Settings without a third credentials section"
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
            overview.contains("bwhBanner(") &&
            vps.contains("bwhBanner(") &&
            overview.contains("failure.staleTitle") &&
            vps.contains("failure.staleTitle"),
            "A failed refresh must degrade to a banner, worded as stale, instead of replacing the dashboard"
        )
        require(
            theme.contains("var tint: Color = Theme.accent") &&
            theme.contains("tint: UsageRing.color(for: progress)") &&
            !theme.contains("AngularGradient(colors: [Theme.accent, .cyan, Theme.accent]"),
            "The hero ring must take its colour from usage instead of a fixed gradient"
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
            overview.contains("GlassCard(padding: 20, fillsHeight: true)") &&
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
            clients.contains("accessibilityReduceMotion") &&
            settings.contains("accessibilityReduceMotion") &&
            trafficChart.contains("accessibilityReduceMotion"),
            "Reduce Motion must be honoured wherever the app animates"
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
