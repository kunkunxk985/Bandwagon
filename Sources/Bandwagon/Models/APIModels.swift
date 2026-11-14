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
        if isDeactivated { return .off }
        if isWarned { return .warn }
        if isConnected { return .online }
        return .idle
    }

    /// Connected right now. The 在线 chip and the header count both use this, so a
    /// client who is over quota or near expiry stays in 在线 while the pill still
    /// reads 预警. `state` is one word for the pill; the filters overlap.
    var isConnected: Bool { online == true }

    /// Switched off, or a dated expiry that has already passed.
    var isDeactivated: Bool {
        if enable == false { return true }
        let expiry = Double(expiryTime ?? 0)
        return expiry > 0 && expiry < nowMillis
    }

    /// Quota at the shared warn threshold, or a dated expiry inside five days.
    /// Still true when the client is connected. A deactivated client is not warned.
    var isWarned: Bool {
        if isDeactivated { return false }
        if let percent, percent >= UsageThreshold.warnPercent { return true }
        let expiry = Double(expiryTime ?? 0)
        return expiry > 0 && expiry - nowMillis < 5 * 86400_000
    }

    private var nowMillis: Double { Date().timeIntervalSince1970 * 1000 }

    /// Clients column. "现在" while connected. Otherwise the panel's last-online
    /// instant (`lastOnline`, not the subscription fetch) as
    /// `yyyy/MM/dd HH:mm:ss` in `timeZone`. "—" when the panel has never seen it.
    func lastOnlineText(timeZone: TimeZone = .current) -> String {
        if isConnected { return "现在" }
        guard let date = Self.unixDate(lastOnline) else { return "—" }
        return DateFormats.string("yyyy/MM/dd HH:mm:ss", date, timeZone: timeZone)
    }

    /// Concrete expiry for the clients column. No expiry is a dash, not a sentence.
    /// A "starts on first use" duration stays one short phrase.
    func expiryLabel(timeZone: TimeZone = .current) -> String {
        if let expiryDate {
            return DateFormats.string("yyyy/MM/dd", expiryDate, timeZone: timeZone)
        }
        if let days = delayedStartDays {
            return "首用后 \(days) 天"
        }
        return "—"
    }

    /// Quota cap for the clients column: `∞` when the panel stores unlimited, otherwise `100G`.
    var quotaLabel: String { ByteFormat.quota(total) }

    private static func unixDate(_ stamp: Int?) -> Date? {
        guard var stamp, stamp > 0 else { return nil }
        if stamp < 100_000_000_000 { stamp *= 1000 }
        return Date(timeIntervalSince1970: Double(stamp) / 1000)
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

struct HistoryPoint: Codable, Hashable, Sendable {
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

    static func formatter(_ format: String, timeZone: TimeZone = .current) -> DateFormatter {
        let key = "\(format)|\(timeZone.identifier)"
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[key] { return cached }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        cache[key] = formatter
        return formatter
    }

    static func string(_ format: String, _ date: Date, timeZone: TimeZone = .current) -> String {
        formatter(format, timeZone: timeZone).string(from: date)
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

    /// Short magnitude for a clients-row amount (`12.5G`, `800M`). Nil is unknown.
    static func compact(_ bytes: Int?) -> String {
        guard let bytes else { return "—" }
        if bytes <= 0 { return "0" }
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 { return magnitude(gb, "G") }
        let mb = Double(bytes) / 1_048_576
        if mb >= 1 { return magnitude(mb, "M") }
        let kb = Double(bytes) / 1024
        if kb >= 1 { return magnitude(kb, "K") }
        return "\(bytes)B"
    }

    /// Panel quota cap. `0` is unlimited, same as an absent cap.
    static func quota(_ bytes: Int?) -> String {
        guard let bytes, bytes > 0 else { return "∞" }
        return compact(bytes)
    }

    private static func magnitude(_ value: Double, _ unit: String) -> String {
        if value >= 100 { return String(format: "%.0f\(unit)", value) }
        let tenths = (value * 10).rounded() / 10
        if abs(tenths - tenths.rounded()) < 0.001 {
            return String(format: "%.0f\(unit)", tenths)
        }
        return String(format: "%.1f\(unit)", tenths)
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

    static func resetDateTime(_ resetAt: Int?) -> String? {
        guard let resetAt, resetAt > 0 else { return nil }
        let seconds = resetAt > 1_000_000_000_000 ? Double(resetAt) / 1000 : Double(resetAt)
        return DateFormats.string("M月d日 HH:mm", Date(timeIntervalSince1970: seconds))
    }
}
