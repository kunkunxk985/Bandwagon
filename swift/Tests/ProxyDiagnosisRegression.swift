import Foundation

@main
struct ProxyDiagnosisRegression {
    static func main() throws {
        func require(_ condition: Bool, _ message: String) {
            if !condition { print("FAIL \(message)"); exit(1) }
        }

        // 198.18.0.0/15 and nothing either side of it.
        for address in ["198.18.0.16", "198.18.0.0", "198.19.255.255"] {
            require(ProxyDiagnosis.isFakeIP(address), "\(address) is in the fake-ip range")
        }
        for address in ["198.17.255.255", "198.20.0.1", "104.26.3.83", "198.18.0", "198.18.0.1.5", "198.18..1", "x.18.0.1", ""] {
            require(!ProxyDiagnosis.isFakeIP(address), "\(address) is not a fake-ip address")
        }

        // Only failures where the connection never got through are diagnosed.
        require(ProxyDiagnosis.isConnectivityFailure(URLError(.timedOut)), "timeouts are connectivity failures")
        require(ProxyDiagnosis.isConnectivityFailure(URLError(.cannotConnectToHost)), "refused connections are connectivity failures")
        require(!ProxyDiagnosis.isConnectivityFailure(URLError(.badServerResponse)), "a server answer is not a connectivity failure")
        require(!ProxyDiagnosis.isConnectivityFailure(BWHError.api("bad key")), "an API rejection is not a connectivity failure")

        let base = "https://api.64clouds.com/v1"
        let viaProxy = ProxyDiagnosis.explain(error: URLError(.timedOut), apiBase: base) { _ in ["198.18.0.16"] }
        require(viaProxy?.contains("api.64clouds.com") == true && viaProxy?.contains("198.18.0.16") == true,
                "a timeout to a fake-ip address must name the host, the address and the proxy")
        require(ProxyDiagnosis.explain(error: URLError(.timedOut), apiBase: base) { _ in ["104.26.3.83"] } == nil,
                "a timeout to a real address must not blame the proxy")
        require(ProxyDiagnosis.explain(error: BWHError.api("bad key"), apiBase: base) { _ in ["198.18.0.16"] } == nil,
                "a credential failure must not be blamed on the proxy even behind fake-ip")

        require(ProxyDiagnosis.resolveIPv4("127.0.0.1") == ["127.0.0.1"], "the resolver returns literal IPv4 addresses")

        let appModel = try String(contentsOfFile: "Sources/Bandwagon/Services/AppModel.swift", encoding: .utf8)
        require(appModel.contains("ProxyDiagnosis.explain(error: error, apiBase: apiBase)") &&
                appModel.contains("Task.detached(priority: .utility)"),
                "Bandwagon failures must be diagnosed off the main actor")

        print("PASS fake-ip range, connectivity classification, proxy hint only behind fake-ip, resolver, wiring")
    }
}
