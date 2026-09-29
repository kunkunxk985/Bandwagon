import Foundation

enum XUIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case authentication(String?)
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "3X-UI 面板地址无效。"
        case .invalidResponse:
            return "3X-UI 返回了无法识别的数据，不是空客户端列表。"
        case .authentication(let serverMessage):
            if let serverMessage, !serverMessage.isEmpty {
                return "3X-UI 拒绝认证（HTTP 200）：\(serverMessage)"
            }
            return "3X-UI 拒绝认证（HTTP 200，success:false）。可能是认证信息无效或触发登录限流，请勿连续重试。"
        case .http(403):
            return "3X-UI 拒绝请求（HTTP 403）：请检查 CSRF / 反向代理访问策略。"
        case .http(let code):
            return "3X-UI 请求失败（HTTP \(code)）。"
        }
    }

    static func safeMessage(_ error: Error) -> String {
        if let error = error as? XUIError { return error.localizedDescription }
        if let error = error as? TransportSecurityError { return error.localizedDescription }
        let e = error as NSError
        if e.domain == NSURLErrorDomain {
            if [-1200, -1201, -1202, -1203, -1204, -1205, -1206].contains(e.code) {
                return "3X-UI TLS 证书验证失败（\(e.code)）。请使用证书匹配的域名或修复证书；未自动关闭 SSL 验证。"
            }
            return "3X-UI 网络连接失败（\(e.code)），请重试。"
        }
        return "3X-UI 返回数据无效，请检查面板版本及地址。"
    }

    static func needsSettings(_ error: Error) -> Bool {
        guard let error = error as? XUIError else { return false }
        switch error {
        case .authentication, .http(401): return true
        default: return false
        }
    }
}
