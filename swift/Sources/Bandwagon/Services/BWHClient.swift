import Foundation

enum BWHError: LocalizedError {
    case api(String)
    case http(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .api(let message):
            return message.isEmpty ? "Bandwagon API 拒绝了当前配置。" : "Bandwagon API：\(message)"
        case .http(let code):
            return "Bandwagon API 请求失败（HTTP \(code)）。"
        case .invalidResponse:
            return "Bandwagon API 返回了无法识别的数据。"
        }
    }

    static func needsSettings(_ error: Error) -> Bool {
        guard let error = error as? BWHError else { return false }
        switch error {
        case .api, .http(401), .http(403): return true
        default: return false
        }
    }

    static func safeMessage(_ error: Error) -> String {
        if let error = error as? BWHError { return error.localizedDescription }
        if let error = error as? TransportSecurityError { return error.localizedDescription }
        let code = (error as NSError).code
        if code == NSURLErrorTimedOut {
            return "Bandwagon API 请求超时，请检查网络或本地代理。"
        }
        return "Bandwagon API 请求失败（\(code)），请检查连接与设置。"
    }
}

enum BWHClient {
    static func fetch(_ settings: AppSettings) async throws -> (BWHOverview, [HistoryPoint]) {
        let info = try await call("getServiceInfo", settings: settings, timeout: 20)

        // `ve_used_disk_space_b` and `ve_status` are NOT part of getServiceInfo — KiwiVM
        // only reports them from getLiveServiceInfo, and only on KVM. Read that here, and
        // concurrently with the usage stats, because KiwiVM documents the live call as
        // taking up to 15 seconds; run in series it would add that to every refresh.
        async let liveRaw = optionalData("getLiveServiceInfo", settings: settings, timeout: 45)
        async let statsRaw = optionalData("getRawUsageStats", settings: settings, timeout: 40)
        let (liveBytes, statsBytes) = await (liveRaw, statsRaw)
        let live = liveBytes.flatMap { try? decode($0) } ?? [:]
        let stats = statsBytes.flatMap { try? decode($0) } ?? [:]

        let multiplier = max(JSONValue.double(info["monthly_data_multiplier"]), 1)
        let used = Int(Double(JSONValue.int(info["data_counter"])) * multiplier)
        let quota = Int(Double(JSONValue.int(info["plan_monthly_data"])) * multiplier)
        let ips = JSONValue.array(info["ip_addresses"]).map(JSONValue.string)
        let overview = BWHOverview(
            configured: true,
            error: nil,
            hostname: JSONValue.string(info["hostname"]),
            ip: ips.first,
            location: JSONValue.string(info["node_location"]).isEmpty ? JSONValue.string(info["node_location_id"]) : JSONValue.string(info["node_location"]),
            node: JSONValue.string(info["node_alias"]),
            plan: JSONValue.string(info["plan"]),
            os: JSONValue.string(info["os"]),
            vmType: JSONValue.string(info["vm_type"]),
            status: {
                let liveStatus = JSONValue.string(live["ve_status"])
                if !liveStatus.isEmpty { return liveStatus }
                let ve = JSONValue.string(info["ve_status"])
                if !ve.isEmpty { return ve }
                let plain = JSONValue.string(info["status"])
                if !plain.isEmpty { return plain }
                // Only reached when the live call fails. The panel omits the field for
                // a healthy VE, so the deployed app has always read that as "running".
                return "running"
            }(),
            usedBytes: used,
            quotaBytes: quota,
            usedPercent: quota > 0 ? (Double(used) * 100 / Double(quota)) : 0,
            resetAt: JSONValue.int(info["data_next_reset"]),
            multiplier: multiplier,
            ramBytes: JSONValue.int(info["plan_ram"]),
            ramUsedBytes: ramUsed(info, live: live),
            diskBytes: JSONValue.int(info["plan_disk"]),
            diskUsedBytes: diskUsed(live)
        )

        var history: [HistoryPoint] = []
        if !stats.isEmpty {
            let rows = JSONValue.array(stats["data"]).isEmpty ? JSONValue.array(stats["array"]) : JSONValue.array(stats["data"])
            history = rows.compactMap(parseRow)
            history.sort { ($0.t ?? 0) < ($1.t ?? 0) }
            history = merged(history, limit: 2_000)
        }
        return (overview, history)
    }

    /// KiwiVM reports used disk only from `getLiveServiceInfo`, and the shape differs by
    /// hypervisor: KVM exposes `ve_used_disk_space_b`, OpenVZ nests the figures under
    /// `vz_quota`. Only the KVM field is parsed. Guessing at the OpenVZ inner keys would
    /// risk showing a confident wrong number, which is worse than showing none.
    private static func diskUsed(_ live: [String: Any]) -> Int? {
        let bytes = JSONValue.int(live["ve_used_disk_space_b"])
        return bytes > 0 ? bytes : nil
    }

    /// RAM in use. The plan states the allowance and the live call reports how much is
    /// still available inside the guest, so the difference is what is in use. Clamped to
    /// the plan: a guest that reports more free memory than the plan allows would
    /// otherwise yield a negative figure and an inverted bar.
    private static func ramUsed(_ info: [String: Any], live: [String: Any]) -> Int? {
        let total = JSONValue.int(info["plan_ram"])
        let availableKB = JSONValue.int(live["mem_available_kb"])
        let (availableBytes, overflow) = availableKB.multipliedReportingOverflow(by: 1024)
        guard total > 0, availableKB > 0, !overflow else { return nil }
        let used = total - availableBytes
        return used > 0 ? min(used, total) : nil
    }

    /// Returns the raw body so the two optional calls can run concurrently: `Data` is
    /// `Sendable`, while the decoded dictionary is not and could not cross the `async let`
    /// boundary under strict concurrency.
    private static func optionalData(_ command: String, settings: AppSettings, timeout: TimeInterval) async -> Data? {
        try? await callData(command, settings: settings, timeout: timeout)
    }

    private static func callData(_ command: String, settings: AppSettings, timeout: TimeInterval) async throws -> Data {
        let baseURL = try SecureURLPolicy.baseURL(from: settings.bwhApiBase)
        let base = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/\(command)") else { throw URLError(.badURL) }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "veid": settings.bwhVeid,
            "api_key": settings.bwhApiKey,
        ]
        .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
        .joined(separator: "&")
        request.httpBody = body.data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw BWHError.http(code) }
        return data
    }

    private static func call(_ command: String, settings: AppSettings, timeout: TimeInterval) async throws -> [String: Any] {
        try decode(try await callData(command, settings: settings, timeout: timeout))
    }

    private static func decode(_ data: Data) throws -> [String: Any] {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BWHError.invalidResponse
        }
        if JSONValue.int(obj["error"]) != 0 {
            throw BWHError.api(JSONValue.string(obj["message"]))
        }
        return obj
    }

    /// KiwiVM returns one delta sample every few minutes, so a month holds
    /// thousands of rows. Charts need a bounded series, but dropping rows
    /// understates every total; fold consecutive samples into summed windows
    /// instead so day/hour aggregates stay exact.
    static func merged(_ points: [HistoryPoint], limit: Int) -> [HistoryPoint] {
        guard limit > 1, points.count > limit else { return points }
        let groupSize = (points.count + limit - 1) / limit
        var folded: [HistoryPoint] = []
        folded.reserveCapacity((points.count / groupSize) + 1)
        var index = 0
        while index < points.count {
            let end = min(index + groupSize, points.count)
            var inbound = 0
            var outbound = 0
            var cpuTotal = 0.0
            for offset in index..<end {
                inbound += points[offset].inbound ?? 0
                outbound += points[offset].out ?? 0
                cpuTotal += points[offset].cpu ?? 0
            }
            folded.append(HistoryPoint(
                t: points[end - 1].t,
                inbound: inbound,
                out: outbound,
                cpu: cpuTotal / Double(end - index)
            ))
            index = end
        }
        return folded
    }

    private static func parseRow(_ row: Any) -> HistoryPoint? {
        if let dict = row as? [String: Any] {
            var ts = JSONValue.int(dict["timestamp"])
            if ts == 0 { ts = JSONValue.int(dict["time"]) }
            if ts == 0 { ts = JSONValue.int(dict["t"]) }
            if ts > 1_000_000_000_000 { ts /= 1000 }
            if ts <= 0 { return nil }
            return HistoryPoint(
                t: ts,
                inbound: JSONValue.int(dict["network_in_bytes"] ?? dict["net_in"] ?? dict["network_in"]),
                out: JSONValue.int(dict["network_out_bytes"] ?? dict["net_out"] ?? dict["network_out"]),
                cpu: JSONValue.double(dict["cpu"] ?? dict["cpu_usage"])
            )
        }
        if let arr = row as? [Any], arr.count >= 3 {
            var ts = JSONValue.int(arr[0])
            if ts > 1_000_000_000_000 { ts /= 1000 }
            if ts <= 0 { return nil }
            let cpu = JSONValue.double(arr[1])
            let netIn = arr.count >= 4 ? JSONValue.int(arr[arr.count - 2]) : 0
            let netOut = arr.count >= 4 ? JSONValue.int(arr[arr.count - 1]) : JSONValue.int(arr[2])
            return HistoryPoint(t: ts, inbound: netIn, out: netOut, cpu: cpu)
        }
        return nil
    }
}
