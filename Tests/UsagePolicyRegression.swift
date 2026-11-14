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

        // Filters overlap. The pill stays 预警, but 在线 still includes the client
        // because they are connected, and 预警 still includes them.
        let warnedOnline = makeClient(percent: UsageThreshold.warnPercent, online: true)
        guard warnedOnline.isConnected, warnedOnline.isWarned, warnedOnline.state == .warn else {
            fail("a connected client at the warn threshold must match both 在线 and 预警")
        }
        let offlineWarned = makeClient(percent: UsageThreshold.warnPercent, online: false)
        guard !offlineWarned.isConnected, offlineWarned.isWarned, offlineWarned.state == .warn else {
            fail("an offline client at the warn threshold must stay in 预警 only")
        }
        guard disabled.isConnected, disabled.isDeactivated, !disabled.isWarned else {
            fail("停用 is enable==false even when the client is still connected; that is not a quota warning")
        }

        let nowMs = Date().timeIntervalSince1970 * 1000
        let expiringOnline = makeClient(
            percent: 1,
            online: true,
            expiryTime: Int(nowMs) + 2 * 86_400_000
        )
        guard expiringOnline.isConnected, expiringOnline.isWarned, expiringOnline.state == .warn,
              expiringOnline.expiryWarning != nil else {
            fail("a connected client expiring inside five days must stay warned and keep the expiry treatment")
        }
        let later = makeClient(
            percent: 1,
            online: true,
            expiryTime: Int(nowMs) + 6 * 86_400_000
        )
        guard later.isConnected, !later.isWarned, later.state == .online else {
            fail("expiry beyond five days must not warn")
        }

        let zone = TimeZone(identifier: "Asia/Shanghai")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let stamped = calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 14, hour: 14, minute: 11, second: 36
        ))!
        let seconds = Int(stamped.timeIntervalSince1970.rounded())
        let millis = seconds * 1000
        let seen = makeClient(percent: 1, online: false, lastOnline: millis)
        guard seen.lastOnlineText(timeZone: zone) == "2026/11/14 14:11:36" else {
            fail("last online must be yyyy/MM/dd HH:mm:ss, got \(seen.lastOnlineText(timeZone: zone))")
        }
        let fromSeconds = makeClient(percent: 1, online: false, lastOnline: seconds)
        guard fromSeconds.lastOnlineText(timeZone: zone) == "2026/11/14 14:11:36" else {
            fail("a seconds-resolution last online must be read as unix seconds")
        }
        let connected = makeClient(percent: 1, online: true, lastOnline: millis)
        guard connected.lastOnlineText(timeZone: zone) == "现在" else {
            fail("a connected client must read 现在")
        }
        guard makeClient(percent: 1, online: false, lastOnline: nil).lastOnlineText() == "—",
              makeClient(percent: 1, online: false, lastOnline: 0).lastOnlineText() == "—" else {
            fail("a missing last online must be a dash")
        }
        let rendered = seen.lastOnlineText(timeZone: zone)
        guard !rendered.contains("前"), !rendered.contains("刚刚") else {
            fail("last online must not be a relative age")
        }

        guard ByteFormat.quota(nil) == "∞", ByteFormat.quota(0) == "∞" else {
            fail("an unlimited quota must read ∞")
        }
        guard ByteFormat.quota(100 * 1_073_741_824) == "100G" else {
            fail("a 100 GiB cap must read 100G, got \(ByteFormat.quota(100 * 1_073_741_824))")
        }
        guard ByteFormat.quota(1_073_741_824) == "1G",
              ByteFormat.quota(3 * 1_073_741_824 / 2) == "1.5G" else {
            fail("quota caps must use a short G suffix")
        }
        guard ByteFormat.compact(nil) == "—", ByteFormat.compact(0) == "0" else {
            fail("upload and download must distinguish missing from zero, and neither is ∞")
        }

        let dated = makeClient(percent: 1, online: false, expiryTime: millis)
        guard dated.expiryLabel(timeZone: zone) == "2026/11/14" else {
            fail("expiry must be a date, got \(dated.expiryLabel(timeZone: zone))")
        }
        guard makeClient(percent: 1, online: false, expiryTime: nil).expiryLabel() == "—",
              makeClient(percent: 1, online: false, expiryTime: 0).expiryLabel() == "—" else {
            fail("a missing expiry must be a dash")
        }
        let delayed = makeClient(percent: 1, online: false, expiryTime: -30 * 86_400_000)
        guard delayed.expiryLabel() == "首用后 30 天" else {
            fail("a first-use expiry must stay a short phrase, got \(delayed.expiryLabel())")
        }

        print("PASS quota thresholds are shared between client state and utilisation colour")
    }

    private static func makeClient(
        percent: Double?,
        online: Bool,
        enable: Bool = true,
        expiryTime: Int? = nil,
        lastOnline: Int? = nil,
        total: Int? = 100
    ) -> Client {
        Client(
            email: "probe@example.com",
            comment: nil,
            inbound: nil,
            protocol: nil,
            used: 1,
            up: nil,
            down: nil,
            total: total,
            percent: percent,
            expiryTime: expiryTime,
            lastOnline: lastOnline,
            online: online,
            enable: enable
        )
    }

    private static func fail(_ message: String) -> Never {
        print("FAIL \(message)")
        exit(1)
    }
}
