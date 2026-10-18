import Foundation

@main
struct UsagePolicyRegression {
    static func main() {
        guard UsageThreshold.warnPercent == UsageThreshold.warn * 100 else {
            fail("warn percent must derive from the warn fraction")
        }
        guard UsageThreshold.warn < UsageThreshold.critical else {
            fail("the warning threshold must sit below the critical threshold")
        }

        // The state pill and the utilisation bar share these thresholds. A row must
        // never draw a warning bar beside a state that says nothing is wrong.
        let below = makeClient(percent: UsageThreshold.warnPercent - 0.5, online: true)
        let at = makeClient(percent: UsageThreshold.warnPercent, online: true)
        guard below.state == .online, at.state == .warn else {
            fail("client state must flip to warn at exactly the shared threshold")
        }

        let critical = makeClient(percent: UsageThreshold.critical * 100, online: true)
        guard critical.state == .warn else {
            fail("a client past the critical threshold must still be flagged")
        }

        // Disabled and expired clients stay off regardless of utilisation, so the
        // quota rule can never mask a client that is already out of service.
        let disabled = makeClient(percent: 99, online: true, enable: false)
        guard disabled.state == .off else {
            fail("a disabled client must read as off, not warn")
        }
        let expired = makeClient(percent: 99, online: true, expiryTime: 1)
        guard expired.state == .off else {
            fail("an expired client must read as off, not warn")
        }

        // No quota configured means no utilisation signal; the row falls back to a
        // neutral bar rather than inventing a percentage.
        let quotaLess = makeClient(percent: nil, online: false)
        guard quotaLess.state == .idle else {
            fail("a client without a quota must not be flagged from utilisation")
        }

        print("PASS quota thresholds are shared between client state and utilisation colour")
    }

    private static func makeClient(
        percent: Double?,
        online: Bool,
        enable: Bool = true,
        expiryTime: Int? = nil
    ) -> Client {
        Client(
            email: "probe@example.com",
            comment: nil,
            inbound: nil,
            `protocol`: nil,
            used: 1,
            up: nil,
            down: nil,
            total: 100,
            percent: percent,
            expiryTime: expiryTime,
            lastOnline: nil,
            online: online,
            enable: enable
        )
    }

    private static func fail(_ message: String) -> Never {
        print("FAIL \(message)")
        exit(1)
    }
}
