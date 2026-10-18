import Darwin
import Foundation

/// Tells a dead local proxy apart from a dead server.
///
/// Clash-family proxies in fake-ip mode answer DNS with an address from
/// 198.18.0.0/15 (RFC 2544's benchmarking range, never a public host) and carry
/// the connection through their TUN interface. When the proxy's chosen node is
/// down, the app sees a plain timeout and blames "the connection", while the
/// server itself is fine. Seeing the API host resolve into that range is what
/// gives it away. See Docs/TROUBLESHOOTING.md.
enum ProxyDiagnosis {
    /// True for an IPv4 address inside 198.18.0.0/15.
    static func isFakeIP(_ address: String) -> Bool {
        let parts = address.split(separator: ".", omittingEmptySubsequences: false)
        let octets = parts.compactMap { UInt8($0) }
        guard parts.count == 4, octets.count == 4 else { return false }
        return octets[0] == 198 && (octets[1] == 18 || octets[1] == 19)
    }

    /// Failures where the TCP connection never got through, as opposed to the
    /// server answering with an error. Only these are worth diagnosing.
    static func isConnectivityFailure(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }
        return [
            NSURLErrorTimedOut,
            NSURLErrorCannotConnectToHost,
            NSURLErrorNetworkConnectionLost,
        ].contains(nsError.code)
    }

    /// IPv4 addresses the system resolver gives for `host`. Blocking: call it off
    /// the main actor.
    static func resolveIPv4(_ host: String) -> [String] {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else { return [] }
        defer { freeaddrinfo(first) }
        var addresses: [String] = []
        var cursor: UnsafeMutablePointer<addrinfo>? = first
        while let info = cursor {
            if let sockaddr = info.pointee.ai_addr, info.pointee.ai_family == AF_INET {
                var address = sockaddr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                if inet_ntop(AF_INET, &address, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil {
                    let text = String(cString: buffer)
                    if !addresses.contains(text) { addresses.append(text) }
                }
            }
            cursor = info.pointee.ai_next
        }
        return addresses
    }

    /// A user-facing explanation when `error` looks like a dead proxy node, or nil
    /// when nothing points at the proxy. `resolve` is injectable for tests.
    static func explain(
        error: Error,
        apiBase: String,
        resolve: (String) -> [String] = resolveIPv4
    ) -> String? {
        guard isConnectivityFailure(error),
              let host = URL(string: apiBase)?.host, !host.isEmpty else { return nil }
        guard let fake = resolve(host).first(where: isFakeIP) else { return nil }
        return "连不上 Bandwagon API：\(host) 被解析到 \(fake)，这是本地代理 fake-ip 的地址，"
            + "多半是代理当前的节点不通，服务器本身可能正常。换个节点，或让该域名走直连后再刷新。"
    }
}
