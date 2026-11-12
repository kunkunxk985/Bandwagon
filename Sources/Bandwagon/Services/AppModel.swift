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
    /// Status of syncing 3X-UI client traffic resets with the Bandwagon server cycle.
    var resetSyncWorking = false
    var resetSyncMessage: String?
    /// The panel's subscription addresses; nil until asked once this session.
    private(set) var subscriptionBases: SubscriptionBases?
    private var refreshTask: Task<Void, Never>?
    private var started = false
    private var autoRefreshTask: Task<Void, Never>?
    private var resetSyncTimerTask: Task<Void, Never>?
    private var scheduledResetTarget = 0
    private var resetPolicyCheckInFlight = false
    private var attemptedStartForResetAt = 0
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
        if let cached = await Task.detached(priority: .utility) { OverviewCacheStore.load() }.value {
            overview = cached
            await recomputeForecastFromOverview()
        }
        await load()
        startAutoRefresh()
    }

    /// Polls on the configured interval. Idempotent on purpose: calling it while a
    /// poller is already running leaves the existing countdown alone, so window
    /// activation does not keep resetting the timer and starving it of a tick.
    func startAutoRefresh() {
        guard settingsRestored, autoRefreshTask == nil else { return }
        autoRefreshTask = Task { [weak self] in
            var consecutiveFailures = 0
            while !Task.isCancelled {
                guard let self else { return }
                // Nothing configured, or polling switched off: stop rather than spin.
                guard self.settings.bwhReady || self.settings.xuiReady else { return }
                let seconds = self.settings.refreshSeconds
                guard seconds > 0 else { return }
                let delay: Double
                if consecutiveFailures > 0 {
                    let backoff = Double(seconds) * pow(1.5, Double(min(consecutiveFailures, 4)))
                    delay = min(max(Double(seconds), backoff), 300)
                } else {
                    delay = Double(seconds)
                }
                do {
                    try await Task.sleep(for: .seconds(delay))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                // A refresh already in flight covers this tick.
                if self.loading { continue }
                await self.load()
                if self.error != nil {
                    consecutiveFailures += 1
                } else {
                    consecutiveFailures = 0
                }
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
        // Advance the clock only when every configured source actually answered.
        // Setting it unconditionally made "更新于" advertise fresh data right after
        // a failed refresh, which is worse than showing nothing.
        let bwhFresh = !snapshot.bwhReady || overview.bwh?.error == nil
        let xuiFresh = !snapshot.xuiReady || overview.xui?.error == nil
        if (snapshot.bwhReady || snapshot.xuiReady), bwhFresh, xuiFresh {
            overview.fetchedAt = Date().timeIntervalSince1970
            let toCache = overview
            Task.detached(priority: .utility) {
                _ = OverviewCacheStore.save(toCache)
            }
        }
        if settingsRestored {
            await coordinateServerResetSync()
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

    private func recomputeForecastFromOverview() async {
        guard let bwh = overview.bwh, let history = overview.bwhHistory else {
            forecast = nil
            return
        }
        forecast = await Task.detached(priority: .utility) {
            TrafficForecast.make(
                points: history,
                usedBytes: bwh.usedBytes,
                quotaBytes: bwh.quotaBytes,
                resetAt: bwh.resetAt
            )
        }.value
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
            let forecast = await Task.detached(priority: .utility) {
                TrafficForecast.make(
                    points: history,
                    usedBytes: bwh.usedBytes,
                    quotaBytes: bwh.quotaBytes,
                    resetAt: bwh.resetAt
                )
            }.value
            self.forecast = forecast
        } catch {
            if overview.bwh == nil { overview.bwh = BWHOverview(configured: true) }
            var message = BWHError.safeMessage(error)
            // A connection that never got through may be a dead local proxy node
            // rather than a dead server; resolving the host tells them apart.
            if ProxyDiagnosis.isConnectivityFailure(error) {
                let apiBase = snapshot.bwhApiBase
                let hint = await Task.detached(priority: .utility) {
                    ProxyDiagnosis.explain(error: error, apiBase: apiBase)
                }.value
                if let hint { message = hint }
            }
            overview.bwh?.error = message
            bwhNeedsSettings = BWHError.needsSettings(error)
        }
    }

    // MARK: - Client actions

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

    // MARK: - Server-Synced Client Traffic Reset

    func setSyncClientResetWithServer(_ enabled: Bool) {
        guard settings.syncClientResetWithServer != enabled else { return }
        settings.syncClientResetWithServer = enabled
        if enabled {
            // Re-verify 3X-UI built-in reset policy immediately when turned on.
            settings.normalizedXuiResetPolicyAt = 0
            resetSyncMessage = nil
        } else {
            resetSyncTimerTask?.cancel()
            resetSyncTimerTask = nil
            scheduledResetTarget = 0
            resetSyncMessage = nil
        }
        if settingsRestored {
            let snapshot = settings
            Task.detached(priority: .utility) {
                _ = SettingsStore.savePreferences(snapshot)
            }
            if enabled {
                Task { await self.coordinateServerResetSync() }
            }
        }
    }

    func coordinateServerResetSync() async {
        guard settingsRestored else { return }
        guard settings.syncClientResetWithServer else {
            resetSyncTimerTask?.cancel()
            resetSyncTimerTask = nil
            scheduledResetTarget = 0
            return
        }

        let nowSec = Int(Date().timeIntervalSince1970)
        if let clients = overview.xui?.clients, !clients.isEmpty, overview.xui?.error == nil {
            let needsPolicySync = settings.normalizedXuiResetPolicyAt == 0 ||
                (nowSec - settings.normalizedXuiResetPolicyAt >= 86_400)
            if needsPolicySync, !resetPolicyCheckInFlight {
                resetPolicyCheckInFlight = true
                resetSyncWorking = true
                do {
                    let result = try await XUIClient.normalizeBuiltInTrafficResetToNever(settings, clients: clients)
                    settings.normalizedXuiResetPolicyAt = Int(Date().timeIntervalSince1970)
                    let snapshot = settings
                    Task.detached(priority: .utility) {
                        _ = SettingsStore.savePreferences(snapshot)
                    }
                    if result.updated > 0 {
                        resetSyncMessage = "已将 \(result.updated) 个客户端的面板内置重置改为「不自动重置」"
                    }
                } catch {
                    resetSyncMessage = "同步面板重置策略未完成：\(XUIError.safeMessage(error))"
                }
                resetSyncWorking = false
                resetPolicyCheckInFlight = false
            }
        }

        let rawResetAt = overview.bwh?.resetAt ?? 0
        let serverResetSec = rawResetAt > 1_000_000_000_000 ? rawResetAt / 1000 : rawResetAt
        let pending = settings.pendingServerResetAt

        let exactTimeReached = pending > 0 &&
            nowSec >= pending &&
            settings.lastExecutedServerResetAt < pending
        let cycleRolledOver = pending > 0 &&
            serverResetSec > pending + 3600 &&
            nowSec >= pending - 300 &&
            settings.lastExecutedServerResetAt < pending

        if (exactTimeReached || cycleRolledOver), !resetSyncWorking {
            let statusLower = (overview.bwh?.status ?? "").lowercased()
            let isStopped = statusLower.contains("stop") || statusLower.contains("offline")
            let quotaAvailable = (overview.bwh?.usedPercent ?? 0) < 95 || serverResetSec > pending
            if isStopped, quotaAvailable, settings.bwhReady, attemptedStartForResetAt != pending {
                attemptedStartForResetAt = pending
                resetSyncMessage = "已到达流量重置时间，正在请求开机启动服务器…"
                try? await BWHClient.start(settings)
            }

            if let clients = overview.xui?.clients, !clients.isEmpty, overview.xui?.error == nil {
                resetSyncWorking = true
                do {
                    let count = try await XUIClient.resetAllClientsTraffic(settings, clients: clients)
                    settings.lastExecutedServerResetAt = pending
                    if serverResetSec > nowSec {
                        settings.pendingServerResetAt = serverResetSec
                    }
                    let snapshot = settings
                    Task.detached(priority: .utility) {
                        _ = SettingsStore.savePreferences(snapshot)
                    }
                    resetSyncMessage = "已按服务器重置时间自动清零 \(count) 个客户端流量"
                    await refreshXUI(settings)
                } catch {
                    resetSyncMessage = "到点自动清零未完成（稍后自动重试）：\(XUIError.safeMessage(error))"
                }
                resetSyncWorking = false
            } else {
                resetSyncMessage = "已到达重置时间，等待服务器开机及 3X-UI 恢复连接后自动清零…"
            }
        }

        // Only advance pendingServerResetAt to the new billing cycle once any due reset
        // for the previous cycle has actually completed on 3X-UI. Otherwise, if the VPS
        // was stopped and takes a few minutes to boot after resetAt, the new cycle's
        // timestamp would overwrite pendingServerResetAt before 3X-UI comes back online.
        let dueResetStillPending = settings.pendingServerResetAt > 0 &&
            nowSec >= settings.pendingServerResetAt &&
            settings.lastExecutedServerResetAt < settings.pendingServerResetAt

        if !dueResetStillPending,
           serverResetSec > nowSec,
           settings.pendingServerResetAt != serverResetSec {
            settings.pendingServerResetAt = serverResetSec
            let snapshot = settings
            Task.detached(priority: .utility) {
                _ = SettingsStore.savePreferences(snapshot)
            }
        }

        if dueResetStillPending {
            // Poll every 15 seconds while waiting for a booting VPS / 3X-UI panel to come online.
            scheduleExactResetTimer(targetResetAt: nowSec + 15)
        } else if settings.pendingServerResetAt > nowSec,
                  settings.lastExecutedServerResetAt < settings.pendingServerResetAt {
            scheduleExactResetTimer(targetResetAt: settings.pendingServerResetAt)
        } else {
            resetSyncTimerTask?.cancel()
            resetSyncTimerTask = nil
            scheduledResetTarget = 0
        }
    }

    private func scheduleExactResetTimer(targetResetAt: Int) {
        guard settingsRestored, settings.syncClientResetWithServer, targetResetAt > 0 else {
            resetSyncTimerTask?.cancel()
            resetSyncTimerTask = nil
            scheduledResetTarget = 0
            return
        }
        if scheduledResetTarget == targetResetAt, resetSyncTimerTask != nil {
            return
        }
        resetSyncTimerTask?.cancel()
        scheduledResetTarget = targetResetAt
        resetSyncTimerTask = Task { [weak self] in
            while !Task.isCancelled {
                let now = Date().timeIntervalSince1970
                let remaining = Double(targetResetAt) - now
                if remaining <= 0 { break }
                // Re-check wall clock every 5 minutes when far away so macOS sleep
                // pauses on the monotonic clock do not delay wake-up detection.
                let step = min(remaining, 300)
                do {
                    try await Task.sleep(for: .seconds(max(0.5, step)))
                } catch {
                    return
                }
            }
            guard !Task.isCancelled, let self else { return }
            self.scheduledResetTarget = 0
            self.resetSyncTimerTask = nil
            await self.load()
            await self.coordinateServerResetSync()
        }
    }
}
