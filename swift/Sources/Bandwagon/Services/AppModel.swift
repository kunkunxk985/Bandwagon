import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    var settings = AppSettings()
    var overview = OverviewResponse()
    /// Whether this cycle's quota is projected to hold. Computed once per refresh
    /// rather than per render, because it walks the whole history.
    var forecast: TrafficForecast?
    var xuiLoading = false
    var bwhLoading = false
    var xuiNeedsSettings = false
    var bwhNeedsSettings = false
    var loading: Bool { xuiLoading || bwhLoading }
    var error: String? { overview.xui?.error ?? overview.bwh?.error }
    /// Three missed polls. With polling switched off the bar is much higher, so a
    /// deliberate manual-only setup does not read as broken.
    var isStale: Bool {
        guard let fetchedAt = overview.fetchedAt else { return false }
        let interval = settings.refreshSeconds
        let limit = interval > 0 ? Double(interval) * 3 : 6 * 3600
        return Date().timeIntervalSince1970 - fetchedAt > limit
    }
    /// The client whose detail sheet is open. Lives here, not in a view, so the
    /// overview, the clients page and the menu bar can all open the same sheet.
    var inspectedClientID: String?
    /// The panel's subscription addresses; nil until asked once this session.
    private(set) var subscriptionBases: SubscriptionBases?
    private var refreshTask: Task<Void, Never>?
    private var started = false
    private var autoRefreshTask: Task<Void, Never>?
    private var restoreTask: Task<AppSettings, Never>?
    private var settingsRestored = false

    func restoreSettings() async {
        guard !settingsRestored else { return }
        if restoreTask == nil {
            restoreTask = Task.detached(priority: .userInitiated) { SettingsStore.load() }
        }
        guard let restoreTask else { return }
        settings = await restoreTask.value
        settingsRestored = true
        self.restoreTask = nil
    }

    /// Launch sequence, safe to call from every scene that may appear first (the
    /// window or the menu bar item).
    func start() async {
        guard !started else { return }
        started = true
        await restoreSettings()
        await load()
        startAutoRefresh()
    }

    /// Polls on the configured interval. Idempotent on purpose: calling it while a
    /// poller is already running leaves the existing countdown alone, so window
    /// activation does not keep resetting the timer and starving it of a tick.
    func startAutoRefresh() {
        guard settingsRestored, autoRefreshTask == nil else { return }
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                // Nothing configured, or polling switched off: stop rather than spin.
                guard self.settings.bwhReady || self.settings.xuiReady else { return }
                let seconds = self.settings.refreshSeconds
                guard seconds > 0 else { return }
                do {
                    try await Task.sleep(for: .seconds(Double(seconds)))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                // A refresh already in flight covers this tick.
                if self.loading { continue }
                await self.load()
            }
        }
    }

    func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    /// Refresh on activation, but only once the snapshot is genuinely stale, so
    /// switching between windows does not hammer the panel.
    func refreshIfStale(olderThan seconds: Double = 60) async {
        guard settingsRestored else { return }
        guard let fetchedAt = overview.fetchedAt else {
            await load()
            return
        }
        guard Date().timeIntervalSince1970 - fetchedAt >= seconds else { return }
        await load()
    }

    func load() async {
        if let refreshTask { await refreshTask.value; return }
        let snapshot = settings
        xuiLoading = snapshot.xuiReady
        bwhLoading = snapshot.bwhReady
        let task = Task { await self.refresh(snapshot) }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    private func refresh(_ snapshot: AppSettings) async {
        if !snapshot.xuiReady { overview.xui = nil }
        if !snapshot.bwhReady { overview.bwh = nil; overview.bwhHistory = nil; forecast = nil }
        async let xui: Void = refreshXUI(snapshot)
        async let bwh: Void = refreshBWH(snapshot)
        _ = await (xui, bwh)
        // A 2FA code is single-use: never reuse or persist it past one refresh attempt.
        if !settings.xuiTwoFactor.isEmpty {
            settings.xuiTwoFactor = ""
        }
        overview.ok = error == nil
        // Advance the clock only when every configured source actually answered.
        // Setting it unconditionally made "更新于" advertise fresh data right after
        // a failed refresh, which is worse than showing nothing.
        let bwhFresh = !snapshot.bwhReady || overview.bwh?.error == nil
        let xuiFresh = !snapshot.xuiReady || overview.xui?.error == nil
        if (snapshot.bwhReady || snapshot.xuiReady), bwhFresh, xuiFresh {
            overview.fetchedAt = Date().timeIntervalSince1970
        }
    }

    private func refreshXUI(_ snapshot: AppSettings) async {
        xuiNeedsSettings = false
        guard snapshot.xuiReady else { return }
        defer { xuiLoading = false }
        overview.xui?.error = nil
        do {
            overview.xui = try await XUIClient.fetch(snapshot)
        } catch {
            // Retain the last successful data, but never manufacture an empty list.
            if overview.xui == nil { overview.xui = XUIOverview(configured: true) }
            overview.xui?.error = XUIError.safeMessage(error)
            xuiNeedsSettings = XUIError.needsSettings(error)
        }
    }

    private func refreshBWH(_ snapshot: AppSettings) async {
        bwhNeedsSettings = false
        guard snapshot.bwhReady else { return }
        defer { bwhLoading = false }
        overview.bwh?.error = nil
        do {
            let (bwh, history) = try await BWHClient.fetch(snapshot)
            overview.bwh = bwh
            overview.bwhHistory = history
            forecast = TrafficForecast.make(
                points: history,
                usedBytes: bwh.usedBytes,
                quotaBytes: bwh.quotaBytes,
                resetAt: bwh.resetAt
            )
        } catch {
            if overview.bwh == nil { overview.bwh = BWHOverview(configured: true) }
            overview.bwh?.error = BWHError.safeMessage(error)
            bwhNeedsSettings = BWHError.needsSettings(error)
        }
    }

    // MARK: - Client actions

    var inspectedClient: Client? {
        guard let inspectedClientID else { return nil }
        return overview.xui?.clients?.first { $0.id == inspectedClientID }
    }

    /// Edits one client on the panel, then refreshes so every page shows the
    /// panel's own view of the result rather than an optimistic guess.
    func updateClient(_ client: Client, changes: ClientChanges) async throws {
        if let refreshTask { await refreshTask.value }
        try await XUIClient.updateClient(settings, client: client, changes: changes)
        await load()
    }

    func resetTraffic(_ client: Client) async throws {
        if let refreshTask { await refreshTask.value }
        try await XUIClient.resetTraffic(settings, client: client)
        await load()
    }

    /// Every subscription link the panel serves for `client`, standard first,
    /// asking the panel for its addresses once per session. Empty when the client
    /// has no subId or every format is switched off.
    func subscriptionLinks(for client: Client) async throws -> [SubscriptionLink] {
        guard let subId = client.subId, !subId.isEmpty else { return [] }
        if subscriptionBases == nil {
            subscriptionBases = try await XUIClient.subscriptionBases(settings)
        }
        guard let bases = subscriptionBases else { return [] }
        return [
            bases.standard.map { SubscriptionLink(format: .standard, url: $0 + subId) },
            bases.clash.map { SubscriptionLink(format: .clash, url: $0 + subId) },
        ].compactMap { $0 }
    }

    func saveSettings(_ newValue: AppSettings) async -> Bool {
        // Join any old refresh before applying new credentials; no stale result can win.
        if let refreshTask { await refreshTask.value }
        let previous = settings
        settings = newValue
        let persistence = Task.detached(priority: .userInitiated) { SettingsStore.save(newValue) }
        guard await persistence.value else {
            settings = previous
            return false
        }
        overview = OverviewResponse()
        subscriptionBases = nil
        // Restart so a changed interval takes effect now rather than after the
        // old countdown finishes.
        stopAutoRefresh()
        await load()
        startAutoRefresh()
        return error == nil
    }
}
