import Foundation

@main
struct ForecastRegression {
    static func main() {
        let gb = 1_073_741_824
        let day = 86_400
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let resetAt = Int(now.timeIntervalSince1970) + 10 * day

        // Seven days of 10 GB/day (5 GB in + 5 GB out), the newest landing on `now`.
        let points: [HistoryPoint] = (0..<7).map { offset in
            HistoryPoint(
                t: Int(now.timeIntervalSince1970) - (6 - offset) * day,
                inbound: 5 * gb,
                out: 5 * gb,
                cpu: 0
            )
        }

        func forecast(used: Int) -> TrafficForecast? {
            TrafficForecast.make(
                points: points,
                usedBytes: used,
                quotaBytes: 1000 * gb,
                resetAt: resetAt,
                now: now,
                calendar: utc
            )
        }

        // 1000 GB quota, 10 GB/day, 10 days to reset: 100 GB remaining lands exactly
        // on the reset, so it must read as tight rather than safe or over.
        guard let tight = forecast(used: 900 * gb) else {
            fail("a complete dataset must produce a forecast")
        }
        guard tight.dailyAverageBytes == 10 * gb,
              tight.daysLeft == 10,
              tight.daysUntilExhausted == 10,
              tight.verdict == .tight else {
            fail("a burn rate that lands exactly on the reset must read as tight")
        }

        // Comfortable headroom, and the boundary where "tight" becomes "safe".
        guard forecast(used: 500 * gb)?.verdict == .safe else {
            fail("plenty of remaining quota must read as safe")
        }
        guard forecast(used: 885 * gb)?.verdict == .safe,
              forecast(used: 890 * gb)?.verdict == .tight else {
            fail("the safe/tight boundary must sit at 15% headroom, not on a guess")
        }

        // Running out well before the reset is the case this whole feature exists for.
        guard let over = forecast(used: 990 * gb), over.verdict == .over else {
            fail("a burn rate that outlives the quota must read as over")
        }
        guard over.headline.contains("用尽") else {
            fail("the over verdict must say so in words, not only in colour")
        }

        guard let exhausted = forecast(used: 1000 * gb),
              exhausted.verdict == .over,
              exhausted.headline == "套餐流量已用尽" else {
            fail("an exhausted quota must not be described as a future projection")
        }

        // Anything the panel cannot answer honestly must come back as no forecast.
        guard TrafficForecast.make(points: points, usedBytes: 100 * gb, quotaBytes: nil,
                                   resetAt: resetAt, now: now, calendar: utc) == nil,
              TrafficForecast.make(points: points, usedBytes: 100 * gb, quotaBytes: 1000 * gb,
                                   resetAt: nil, now: now, calendar: utc) == nil,
              TrafficForecast.make(points: points, usedBytes: 100 * gb, quotaBytes: 1000 * gb,
                                   resetAt: Int(now.timeIntervalSince1970) - day, now: now,
                                   calendar: utc) == nil,
              TrafficForecast.make(points: [], usedBytes: 100 * gb, quotaBytes: 1000 * gb,
                                   resetAt: resetAt, now: now, calendar: utc) == nil,
              forecast(used: 0) == nil else {
            fail("a forecast must be withheld when quota, reset date, or history is missing")
        }

        print("PASS quota forecast verdicts, boundaries, wording, and withheld cases")
    }

    private static func fail(_ message: String) -> Never {
        print("FAIL \(message)")
        exit(1)
    }
}
