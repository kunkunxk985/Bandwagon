import Foundation

enum XUIClient {
    static func fetch(_ settings: AppSettings) async throws -> XUIOverview {
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        let baseURL = try SecureURLPolicy.baseURL(from: settings.xuiBaseUrl)
        let base = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var csrf: String?
        if settings.xuiApiToken.isEmpty {
            csrf = try await login(base: base, settings: settings, session: session)
        }
        let inbounds = try await inboundsList(base: base, settings: settings, session: session, csrf: csrf)
        let online = await onlineEmails(base: base, settings: settings, session: session, csrf: csrf)
        var clients = parseClients(inbounds: inbounds, online: online)
        clients.sort { ($0.used ?? 0) > ($1.used ?? 0) }
        return XUIOverview(
            configured: true,
            error: nil,
            clients: clients,
            inbounds: nil,
            onlineCount: clients.filter { $0.online == true }.count,
            clientCount: clients.count,
            enabledCount: clients.filter { $0.enable != false }.count
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
        csrf: String?
    ) async throws -> Any {
        guard let url = URL(string: base + path) else { throw XUIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(csrf, forHTTPHeaderField: "X-CSRF-Token")
        for (k, v) in headers(settings) { request.setValue(v, forHTTPHeaderField: k) }
        let (data, response) = try await session.data(for: request)
        try checkHTTP(response)
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { throw XUIError.invalidResponse }
        if let dict = obj as? [String: Any] {
            if dict["success"] as? Bool == false { throw XUIError.invalidResponse }
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
                var total = JSONValue.int(stat["total"])
                if total == 0, JSONValue.int(info["totalGB"]) > 0 {
                    total = JSONValue.int(info["totalGB"]) * 1_073_741_824
                }
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
                        enable: JSONValue.bool(stat["enable"] ?? info["enable"], default: true)
                    )
                )
            }
        }
        return clients
    }
}
