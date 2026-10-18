import Foundation

enum XUIClient {
    static func fetch(_ settings: AppSettings) async throws -> XUIOverview {
        try await withConnection(settings) { base, session, csrf in
            try await overview(base: base, settings: settings, session: session, csrf: csrf)
        }
    }

    // MARK: - Writes
    //
    // Written against 3X-UI v3, where a client is one record (addressed by email)
    // that can be attached to several inbounds. The per-inbound `updateClient`
    // and `resetClientTraffic` routes of v2 no longer exist there.

    /// Applies `changes` to one client.
    ///
    /// Enabling and disabling go through `bulkEnable` / `bulkDisable`, which touch
    /// nothing else. Quota and expiry need `update`, which replaces the whole
    /// client row, so the stored record is read first and sent back with only
    /// those fields changed — converted the same way the panel's own
    /// `ClientRecord.ToClient` does, which is also what its traffic reset uses.
    static func updateClient(_ settings: AppSettings, client: Client, changes: ClientChanges) async throws {
        guard !changes.isEmpty else { return }
        guard let email = client.email, !email.isEmpty else { throw XUIError.missingClientData }
        try await withConnection(settings) { base, session, csrf in
            if changes.totalBytes != nil || changes.expiryTime != nil {
                let raw = try await request(
                    "GET", base: base, path: "/panel/api/clients/get/" + pathComponent(email),
                    settings: settings, session: session, csrf: csrf
                )
                let record = JSONValue.object(JSONValue.object(raw)["client"])
                guard !record.isEmpty, JSONValue.string(record["email"]) == email else {
                    throw XUIError.missingClientData
                }
                var payload = clientPayload(fromRecord: record)
                if let total = changes.totalBytes { payload["totalGB"] = max(0, total) }
                if let expiry = changes.expiryTime { payload["expiryTime"] = expiry }
                if let enable = changes.enable { payload["enable"] = enable }
                _ = try await request(
                    "POST", base: base, path: "/panel/api/clients/update/" + pathComponent(email),
                    settings: settings, session: session, csrf: csrf, json: payload
                )
            } else if let enable = changes.enable {
                let raw = try await request(
                    "POST", base: base,
                    path: enable ? "/panel/api/clients/bulkEnable" : "/panel/api/clients/bulkDisable",
                    settings: settings, session: session, csrf: csrf, json: ["emails": [email]]
                )
                // A refusal for this one email comes back inside a successful
                // response, as a skipped entry with the reason.
                for item in JSONValue.array(JSONValue.object(raw)["skipped"]) {
                    let entry = JSONValue.object(item)
                    if JSONValue.string(entry["email"]) == email {
                        let reason = JSONValue.string(entry["reason"])
                        throw XUIError.rejected(reason.isEmpty ? "面板跳过了这个客户端" : reason)
                    }
                }
            }
        }
    }

    /// Zeroes the client's counters on every inbound it is attached to. On v3 the
    /// panel also re-enables a client that was switched off.
    static func resetTraffic(_ settings: AppSettings, client: Client) async throws {
        guard let email = client.email, !email.isEmpty else { throw XUIError.missingClientData }
        try await withConnection(settings) { base, session, csrf in
            _ = try await request(
                "POST", base: base, path: "/panel/api/clients/resetTraffic/" + pathComponent(email),
                settings: settings, session: session, csrf: csrf
            )
        }
    }

    /// The panel's subscription addresses, to which a client's `subId` is
    /// appended: the standard link list and the Clash YAML, each nil when that
    /// format is switched off on the panel.
    ///
    /// `defaultSettings` is what the panel's own QR dialog uses: it already folds
    /// the sub domain, port, path and TLS into each URI (filling in any left
    /// blank), and unlike `setting/all` it carries no secrets.
    static func subscriptionBases(_ settings: AppSettings) async throws -> SubscriptionBases {
        try await withConnection(settings) { base, session, csrf in
            let raw = try await request(
                "POST", base: base, path: "/panel/api/setting/defaultSettings",
                settings: settings, session: session, csrf: csrf
            )
            let object = JSONValue.object(raw)
            func uri(_ enableKey: String, _ uriKey: String) -> String? {
                guard JSONValue.bool(object[enableKey]) else { return nil }
                let value = JSONValue.string(object[uriKey]).trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }
            return SubscriptionBases(
                standard: uri("subEnable", "subURI"),
                clash: uri("subClashEnable", "subClashURI")
            )
        }
    }

    /// `ClientRecord` (what `clients/get` returns) → `model.Client` (what
    /// `clients/update` binds), field for field as the panel's `ToClient` maps
    /// them. The two shapes disagree on `id` (row number vs UUID), `reverse`
    /// (JSON text vs object) and `allowedIPs` (comma list vs array), so the
    /// record cannot be sent back as it came.
    static func clientPayload(fromRecord record: [String: Any]) -> [String: Any] {
        var out: [String: Any] = [:]
        let copied = [
            "email", "subId", "password", "auth", "flow", "security", "limitIp", "totalGB",
            "expiryTime", "enable", "tgId", "group", "comment", "reset", "resetDay",
            "resetWeekday", "resetMax", "trafficReset", "trafficResetDay",
            "privateKey", "publicKey", "preSharedKey", "forwardedPorts", "secret", "adTag",
            "limitHwid",
        ]
        for key in copied {
            if let value = record[key], !(value is NSNull) { out[key] = value }
        }
        out["id"] = JSONValue.string(record["uuid"])
        let allowed = JSONValue.string(record["allowedIPs"])
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if !allowed.isEmpty { out["allowedIPs"] = allowed }
        let keepAlive = JSONValue.int(record["keepAlive"])
        if keepAlive > 0 { out["keepAlive"] = keepAlive }
        let reverse = JSONValue.string(record["reverse"])
        if !reverse.isEmpty, let data = reverse.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            out["reverse"] = object
        }
        return out
    }

    private static func pathComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? value
    }

    // MARK: - Session

    /// One authenticated session per call: log in (unless an API token is set),
    /// run `body`, tear the session down.
    private static func withConnection<T>(
        _ settings: AppSettings,
        _ body: (String, URLSession, String?) async throws -> T
    ) async throws -> T {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let baseURL = try SecureURLPolicy.baseURL(from: settings.xuiBaseUrl)
        let base = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var csrf: String?
        if settings.xuiApiToken.isEmpty {
            csrf = try await login(base: base, settings: settings, session: session)
        }
        return try await body(base, session, csrf)
    }

    private static func overview(base: String, settings: AppSettings, session: URLSession, csrf: String?) async throws -> XUIOverview {
        let inbounds = try await inboundsList(base: base, settings: settings, session: session, csrf: csrf)
        let online = await onlineEmails(base: base, settings: settings, session: session, csrf: csrf)
        var clients = parseClients(inbounds: inbounds, online: online)
        clients.sort { ($0.used ?? 0) > ($1.used ?? 0) }
        return XUIOverview(
            configured: true,
            error: nil,
            clients: clients,
            onlineCount: clients.filter { $0.online == true }.count,
            clientCount: clients.count
        )
    }

    private static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }

    private static func headers(_ settings: AppSettings) -> [String: String] {
        var headers = [
            "Accept": "application/json",
            "X-Requested-With": "XMLHttpRequest"
        ]
        if var origin = URLComponents(string: settings.xuiBaseUrl) {
            origin.path = ""; origin.query = nil; origin.fragment = nil
            headers["Origin"] = origin.string
            headers["Referer"] = settings.xuiBaseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/"
        }
        if !settings.xuiApiToken.isEmpty {
            headers["Authorization"] = "Bearer \(settings.xuiApiToken)"
        }
        return headers
    }

    private static func login(base: String, settings: AppSettings, session: URLSession) async throws -> String? {
        guard let root = URL(string: base + "/"),
              let tokenURL = URL(string: base + "/csrf-token") else { throw XUIError.invalidURL }
        let (page, pageResponse) = try await session.data(from: root)
        try checkHTTP(pageResponse)
        var token = csrfToken(in: String(data: page, encoding: .utf8) ?? "")
        if token == nil {
            let (data, response) = try await session.data(from: tokenURL)
            let status = (response as? HTTPURLResponse)?.statusCode
            if status != 404 && status != 405 {
                try checkHTTP(response)
                let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                token = obj?["obj"] as? String
            }
        }
        let payload = ["username": settings.xuiUsername, "password": settings.xuiPassword,
                       "twoFactorCode": settings.xuiTwoFactor]
        for path in ["/login", "/panel/login"] {
            guard let url = URL(string: base + path) else { throw XUIError.invalidURL }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
            request.setValue(token, forHTTPHeaderField: "X-CSRF-Token")
            for (k, v) in headers(settings) { request.setValue(v, forHTTPHeaderField: k) }
            request.httpBody = formBody(payload)
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, [404, 405].contains(http.statusCode) { continue }
            try checkHTTP(response)
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw XUIError.invalidResponse
            }
            let message = JSONValue.string(obj["msg"])
            guard JSONValue.bool(obj["success"]) else {
                throw XUIError.authentication(message.isEmpty ? nil : message)
            }
            return token
        }
        throw XUIError.http(404)
    }

    static func csrfToken(in html: String) -> String? {
        let tags = html.matches(of: /<meta\b[^>]*>/)
        for tag in tags {
            let text = String(tag.output)
            guard text.range(of: #"name\s*=\s*["']csrf-token["']"#, options: .regularExpression) != nil,
                  let range = text.range(of: #"content\s*=\s*["'][^"']+["']"#, options: .regularExpression) else { continue }
            let attribute = String(text[range])
            guard let quote = attribute.firstIndex(where: { $0 == "\"" || $0 == "'" }) else { continue }
            return String(attribute[attribute.index(after: quote)..<attribute.index(before: attribute.endIndex)])
        }
        return nil
    }

    private static func formBody(_ values: [String: String]) -> Data? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let body = values.keys.sorted().map { key in
            let value = values[key] ?? ""
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(encodedKey)=\(encodedValue)"
        }.joined(separator: "&")
        return body.data(using: .utf8)
    }

    private static func checkHTTP(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw XUIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw XUIError.http(http.statusCode) }
    }

    private static func request(
        _ method: String,
        base: String,
        path: String,
        settings: AppSettings,
        session: URLSession,
        csrf: String?,
        json: Any? = nil
    ) async throws -> Any {
        guard let url = URL(string: base + path) else { throw XUIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(csrf, forHTTPHeaderField: "X-CSRF-Token")
        for (k, v) in headers(settings) { request.setValue(v, forHTTPHeaderField: k) }
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        }
        let (data, response) = try await session.data(for: request)
        try checkHTTP(response)
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { throw XUIError.invalidResponse }
        if let dict = obj as? [String: Any] {
            if dict["success"] as? Bool == false {
                // A write the panel refused says why in `msg`; keep it for the user.
                let message = JSONValue.string(dict["msg"])
                throw message.isEmpty ? XUIError.invalidResponse : XUIError.rejected(message)
            }
            return dict["obj"] ?? dict
        }
        return obj
    }

    private static func inboundsList(base: String, settings: AppSettings, session: URLSession, csrf: String?) async throws -> [[String: Any]] {
        let raw: Any
        do {
            raw = try await request("GET", base: base, path: "/panel/api/inbounds/list", settings: settings, session: session, csrf: csrf)
        } catch XUIError.http(let code) where [404, 405].contains(code) {
            raw = try await request("POST", base: base, path: "/panel/api/inbounds/list", settings: settings, session: session, csrf: csrf)
        }
        if let arr = raw as? [[String: Any]] { return arr }
        if let arr = raw as? [Any] { return arr.compactMap { $0 as? [String: Any] } }
        if let dict = raw as? [String: Any] {
            let list = dict["list"] ?? dict["obj"]
            if let arr = list as? [[String: Any]] { return arr }
            if let arr = list as? [Any] { return arr.compactMap { $0 as? [String: Any] } }
        }
        throw XUIError.invalidResponse
    }

    private static func onlineEmails(base: String, settings: AppSettings, session: URLSession, csrf: String?) async -> Set<String> {
        let paths = [
            ("POST", "/panel/api/clients/onlines"),
            ("POST", "/panel/api/inbounds/onlines"),
            ("GET", "/panel/api/inbounds/onlines"),
            ("GET", "/panel/api/clients/onlines"),
        ]
        var emails = Set<String>()
        for (method, path) in paths {
            guard let raw = try? await request(method, base: base, path: path, settings: settings, session: session, csrf: csrf) else { continue }
            for item in JSONValue.array(raw) {
                if let s = item as? String, !s.isEmpty { emails.insert(s) }
                if let d = item as? [String: Any] {
                    let email = JSONValue.string(d["email"])
                    if !email.isEmpty { emails.insert(email) }
                }
            }
            if !emails.isEmpty { break }
        }
        return emails
    }

    private static func parseClients(inbounds: [[String: Any]], online: Set<String>) -> [Client] {
        var clients: [Client] = []
        for inbound in inbounds {
            let settingsObj = JSONValue.object(inbound["settings"])
            var meta: [String: [String: Any]] = [:]
            for item in JSONValue.array(settingsObj["clients"]) {
                guard let dict = item as? [String: Any] else { continue }
                let email = JSONValue.string(dict["email"])
                if !email.isEmpty { meta[email] = dict }
            }
            let remark = JSONValue.string(inbound["remark"])
            let proto = JSONValue.string(inbound["protocol"])
            let stats = inbound["clientStats"] ?? inbound["client_stats"]
            for item in JSONValue.array(stats) {
                guard let stat = item as? [String: Any] else { continue }
                let email = JSONValue.string(stat["email"])
                let info = meta[email] ?? [:]
                let up = JSONValue.int(stat["up"])
                let down = JSONValue.int(stat["down"])
                // Despite the name, the panel stores `totalGB` in bytes — its own
                // client dialog multiplies the GB field by 1024³ before saving.
                var total = JSONValue.int(stat["total"])
                if total == 0 { total = JSONValue.int(info["totalGB"]) }
                let used = up + down
                var expiry = JSONValue.int(stat["expiryTime"] ?? info["expiryTime"])
                if expiry > 0, expiry < 100_000_000_000 { expiry *= 1000 }
                clients.append(
                    Client(
                        email: email,
                        comment: JSONValue.string(info["comment"]).isEmpty ? email : JSONValue.string(info["comment"]),
                        inbound: remark,
                        protocol: proto,
                        used: used,
                        up: up,
                        down: down,
                        total: total,
                        percent: total > 0 ? Double(used) * 100 / Double(total) : nil,
                        expiryTime: expiry,
                        lastOnline: JSONValue.int(stat["lastOnline"]),
                        online: online.contains(email),
                        enable: JSONValue.bool(stat["enable"] ?? info["enable"], default: true),
                        subId: JSONValue.string(info["subId"]).isEmpty ? nil : JSONValue.string(info["subId"])
                    )
                )
            }
        }
        return clients
    }
}
