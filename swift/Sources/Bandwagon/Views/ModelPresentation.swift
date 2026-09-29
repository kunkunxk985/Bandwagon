import SwiftUI

/// Presentation rules for model types. These live in the view layer on purpose: the
/// models stay free of `SwiftUI`, and every page reads one definition instead of
/// re-deriving what "healthy" or "needs attention" looks like.
///
/// Status is never carried by colour alone — each tint has a text counterpart.

/// How a failed service request should be presented. Overview, VPS, and Clients each
/// used to carry their own copy of these four decisions, which is exactly how three
/// pages end up wording the same failure differently.
struct ServiceFailure {
    let title: String
    let message: String
    let icon: String
    let actionTitle: String
    /// True when retrying cannot help and the user has to fix the credentials first.
    let goesToSettings: Bool

    init(service: String, error: String, needsSettings: Bool) {
        goesToSettings = needsSettings
        if needsSettings {
            title = "\(service) 登录信息未通过"
            message = "当前保存的账号或密码已被面板拒绝。请重新输入网页登录使用的完整信息；不要连续重试。"
            icon = "lock.trianglebadge.exclamationmark"
            actionTitle = "前往设置"
        } else {
            title = "\(service) 连接失败"
            message = error
            icon = "wifi.exclamationmark"
            actionTitle = "重试"
        }
    }

    /// Same failure, worded for a banner that sits above data which is still on screen.
    var staleTitle: String { "\(title) · 数据可能已过期" }

    /// Runs the recovery this failure actually calls for, so no page has to re-decide
    /// whether a retry could possibly help.
    @MainActor
    func resolve(goToSettings: () -> Void, retry: @escaping () async -> Void) {
        if goesToSettings {
            goToSettings()
        } else {
            Task { await retry() }
        }
    }
}

extension BWHOverview {
    /// Health tint derived from the panel status string. Overview and VPS both read
    /// this so the two pages can never disagree about whether the server is healthy.
    var healthTint: Color {
        let status = (self.status ?? "").lowercased()
        if status.contains("run") { return ClientState.online.swiftColor }
        if status.contains("stop") || status.contains("suspend") { return ClientState.off.swiftColor }
        if status.isEmpty { return ClientState.online.swiftColor }
        return ClientState.warn.swiftColor
    }

    /// Text counterpart to `healthTint`: status must never be carried by colour alone.
    var healthLabel: String {
        let status = (self.status ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if status.isEmpty { return "运行中" }
        let lowered = status.lowercased()
        if lowered == "running" { return "运行中" }
        if lowered == "stopped" { return "已停止" }
        return status
    }
}

extension TrafficForecast.Verdict {
    var tint: Color {
        switch self {
        case .safe: return ClientState.online.swiftColor
        case .tight: return ClientState.warn.swiftColor
        case .over: return ClientState.off.swiftColor
        }
    }

    var icon: String {
        switch self {
        case .safe: return "checkmark.circle.fill"
        case .tight: return "exclamationmark.circle.fill"
        case .over: return "exclamationmark.triangle.fill"
        }
    }
}

extension ClientState {
    var swiftColor: Color {
        switch self {
        case .online: Color(red: 0.20, green: 0.72, blue: 0.42)
        case .warn: Color(red: 0.90, green: 0.55, blue: 0.12)
        case .off: Color(red: 0.86, green: 0.22, blue: 0.27)
        case .idle: .secondary
        }
    }

    var tagColor: Color {
        switch self {
        case .online: Color(red: 0.20, green: 0.72, blue: 0.42).opacity(0.14)
        case .warn: Color(red: 0.90, green: 0.55, blue: 0.12).opacity(0.14)
        case .off: Color(red: 0.86, green: 0.22, blue: 0.27).opacity(0.14)
        case .idle: Color.clear
        }
    }
}
