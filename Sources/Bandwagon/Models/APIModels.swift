import Foundation

struct OverviewResponse: Codable {
    var fetchedAt: Double? = nil
    var bwh: BWHOverview? = nil
    var bwhHistory: [HistoryPoint]? = nil
    var xui: XUIOverview? = nil
}

struct BWHOverview: Codable {
    var configured: Bool?
    var error: String?
    var hostname: String?
    var ip: String?
    var location: String?
    var node: String?
    var plan: String?
    var os: String?
    var vmType: String?
    var status: String?
    var usedBytes: Int?
    var quotaBytes: Int?
    var usedPercent: Double?
    var resetAt: Int?
    var ramBytes: Int?
    var ramUsedBytes: Int?
    var diskBytes: Int?
    var diskUsedBytes: Int?
}

struct XUIOverview: Codable {
    var configured: Bool?
    var error: String?
    var clients: [Client]?
    var onlineCount: Int?
    var clientCount: Int?
}

/// Single source of truth for quota-utilisation thresholds. Both the client state
/// pill and the utilisation bar read these, so one row can never show a warning
/// bar beside a state that says everything is fine.
enum UsageThreshold {
    static let warn = 0.7
    static let critical = 0.9
    static var warnPercent: Double { warn * 100 }
}

struct Client: Codable, Identifiable, Hashable {
    var email: String?
    var comment: String?
    var inbound: String?
    var `protocol`: String?
    var used: Int?
    var up: Int?
    var down: Int?
    var total: Int?
    var percent: Double?
    var expiryTime: Int?
    var lastOnline: Int?
    var online: Bool?
    var enable: Bool?
    /// Subscription id; the subscription link is the panel's sub URI plus this.
    var subId: String? = nil

    var id: String { "\(email ?? "")|\(inbound ?? "")" }

    /// Expiry as a date, when it is one. 3X-UI stores a negative value for
    /// "N days after first use", which is a duration, not a date.
    var expiryDate: Date? {
        guard let expiryTime, expiryTime > 0 else { return nil }
        return Date(timeIntervalSince1970: Double(expiryTime) / 1000)
    }

    /// Days of a "starts on first use" expiry, or nil when the expiry is a date
    /// or unset.
    var delayedStartDays: Int? {
        guard let expiryTime, expiryTime < 0 else { return nil }
        return Int((Double(-expiryTime) / 86_400_000).rounded())
    }

    var name: String {
        let comment = (comment ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !comment.isEmpty { return comment }
        return email ?? "未命名"
    }

    var state: ClientState {
        let now = Date().timeIntervalSince1970 * 1000
        let expiry = Double(expiryTime ?? 0)
        if enable == false { return .off }
        if expiry > 0, expiry < now { return .off }
        if let percent, percent >= UsageThreshold.warnPercent { return .warn }
        if expiry > 0, expiry - now < 5 * 86400_000 { return .warn }
        if online == true { return .online }
        return .idle
    }

    /// Set only when the warning comes from the expiry date rather than from quota
    /// use. The state pill cannot say which triggered it, so a warned client with a
    /// low, green utilisation bar used to look like a contradiction.
    var expiryWarning: String? {
        guard state == .warn, let expiryTime, expiryTime > 0 else { return nil }
        if let percent, percent >= UsageThreshold.warnPercent { return nil }
        let days = (Double(expiryTime) - Date().timeIntervalSince1970 * 1000) / 86_400_000
        if days <= 0 { return "已过期" }
        if days < 1 { return "今日到期" }
        return "\(Int(days.rounded(.up))) 天后到期"
    }
}

enum ClientState: String {
    case online, warn, off, idle

    var title: String {
        switch self {
        case .online: "在线"
        case .warn: "预警"
        case .off: "停用"
        case .idle: "离线"
        }
    }
}

/// The panel's subscription addresses, each waiting for a client's `subId`.
/// Nil means that format is switched off on the panel.
struct SubscriptionBases: Equatable, Sendable {
    /// Base64 link list — what Shadowrocket, v2rayN and most clients import.
    var standard: String?
    /// Clash / Mihomo YAML.
    var clash: String?
}

/// One ready-to-import subscription link for a client.
struct SubscriptionLink: Identifiable, Hashable, Sendable {
    enum Format: String, CaseIterable, Sendable {
        case standard, clash
    }

    let format: Format
    let url: String
    var id: Format { format }
}

/// Edits to one 3X-UI client. Nil leaves a field as the panel has it.
struct ClientChanges: Equatable, Sendable {
    var enable: Bool? = nil
    /// Quota in bytes; 0 means unlimited.
    var totalBytes: Int? = nil
    /// Expiry in Unix milliseconds; 0 means never.
    var expiryTime: Int? = nil

    var isEmpty: Bool { enable == nil && totalBytes == nil && expiryTime == nil }
}

struct HistoryPoint: Codable, Hashable {
    var t: Int?
    var inbound: Int?
    var out: Int?
    var cpu: Double?

    enum CodingKeys: String, CodingKey {
        case t, out, cpu
        case inbound = "in"
    }
}

/// Cached date formatters. Building a `DateFormatter` means parsing the format and
/// resolving the locale, which is far too expensive to repeat per row per frame in
/// the client list and the chart axis.
enum DateFormats {
    private static let lock = NSLock()
    // Guarded by `lock`; `nonisolated(unsafe)` is the Swift 6 way to say so.
    nonisolated(unsafe) private static var cache: [String: DateFormatter] = [:]

    static func formatter(_ format: String) -> DateFormatter {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[format] { return cached }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = format
        cache[format] = formatter
        return formatter
    }

    static func string(_ format: String, _ date: Date) -> String {
        formatter(format).string(from: date)
    }
}

enum ByteFormat {
    static func string(_ bytes: Int?) -> String {
        // Absent and zero are different answers: an unused client is not a client
        // with no data, and an exhausted quota is not a missing one.
        guard let bytes else { return "—" }
        guard bytes > 0 else { return "0 MB" }
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 100 { return String(format: "%.0f GB", gb) }
        if gb >= 10 { return String(format: "%.1f GB", gb) }
        if gb >= 1 { return String(format: "%.2f GB", gb) }
        let mb = Double(bytes) / 1_048_576
        return String(format: "%.0f MB", mb)
    }

    static func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.0f%%", value)
    }

    static func daysLeft(resetAt: Int?) -> String {
        guard let resetAt, resetAt > 0 else { return "—" }
        let seconds = resetAt > 1_000_000_000_000 ? Double(resetAt) / 1000 : Double(resetAt)
        let days = max(0, (seconds - Date().timeIntervalSince1970) / 86400)
        if days >= 10 { return String(format: "%.0f 天", days) }
        return String(format: "%.1f 天", days)
    }

    static func resetDate(_ resetAt: Int?) -> String? {
        guard let resetAt, resetAt > 0 else { return nil }
        let seconds = resetAt > 1_000_000_000_000 ? Double(resetAt) / 1000 : Double(resetAt)
        return DateFormats.string("M月d日", Date(timeIntervalSince1970: seconds))
    }
}
