import Foundation

enum TransportSecurityError: LocalizedError {
    case invalidURL
    case publicCleartextURL

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "服务地址无效。"
        case .publicCleartextURL:
            return "为保护账号与凭证，公网服务地址必须使用 HTTPS。"
        }
    }
}

enum SecureURLPolicy {
    static func baseURL(from value: String) throws -> URL {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              !host.isEmpty else {
            throw TransportSecurityError.invalidURL
        }

        guard scheme == "https" || (scheme == "http" && isLoopback(host)) else {
            throw TransportSecurityError.publicCleartextURL
        }

        components.fragment = nil
        guard let url = components.url else {
            throw TransportSecurityError.invalidURL
        }
        return url
    }

    private static func isLoopback(_ host: String) -> Bool {
        host == "localhost" || host == "::1" || host.hasPrefix("127.")
    }
}
