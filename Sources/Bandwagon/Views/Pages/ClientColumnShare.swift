import Foundation

/// How the clients table divides one row.
///
/// Columns, in order: status, name, last online, usage line (bar + total +
/// upload + download), quota, copy.
///
/// `minimum` is the comfortable width. Spare room above that is shared by
/// `weight`, so a fullscreen window spreads every column instead of leaving an
/// empty band on the right. Below that, only `minimum - floor` is given up —
/// the last-online timestamp, the quota slot, and the copy slot do not shrink —
/// until the row is narrower than the floors.
enum ClientColumnShare {
    struct Column: Equatable {
        var floor: Double
        var minimum: Double
        var weight: Double
    }

    static let spacing: Double = 12
    static let inset: Double = 18
    /// Gap between the used total, the upload figure, and the download figure.
    /// Wide enough that `61.4 GB ↑ 12.9G ↓ 48.5G` does not read as one string,
    /// and fixed so a wider window does not stretch the figures apart.
    static let usageTokenGap: Double = 14
    /// Extra room after the download figure, on top of `spacing`, before the quota.
    static let usageQuotaPadding: Double = 6
    /// Gap between the bar and the used total. The bar is the only flexible part.
    static let usageBarGap: Double = 6
    /// Narrowest the bar may be before the usage column itself is below its floor.
    static let usageBarMin: Double = 28
    /// Fixed slots. `61.4 GB` and `525 MB`, `12.9G` and `525M`, `∞` and `100G`
    /// would otherwise start ↑, ↓, and ∞ at a different x on every row.
    /// Widths fit a 13pt figure through `9999 GB` / `↑ 9999G`.
    static let usedFigureWidth: Double = 72
    static let directionFigureWidth: Double = 68
    static let quotaFigureWidth: Double = 52
    /// Bar minimum plus the fixed figure slots. The 38pt above this is slack the
    /// bar gives up; the slots themselves do not change width with the string.
    static let usageContentFloor: Double =
        usageBarMin + usageBarGap + usedFigureWidth + directionFigureWidth * 2
        + usageTokenGap * 2 + usageQuotaPadding

    static let status = Column(floor: 52, minimum: 56, weight: 0.7)
    static let name = Column(floor: 72, minimum: 108, weight: 1.8)
    /// `yyyy/MM/dd HH:mm:ss` at 13pt medium. No slack: the timestamp stays whole.
    static let lastOnline = Column(floor: 160, minimum: 160, weight: 1.3)
    /// Floor fits the bar's minimum and the fixed used / upload / download slots.
    static let usage = Column(floor: usageContentFloor, minimum: usageContentFloor + 38, weight: 2.8)
    /// The quota glyph stays in a fixed slot. Spare width may still widen the
    /// column; the ∞ stays on the leading edge.
    static let quota = Column(floor: quotaFigureWidth, minimum: quotaFigureWidth, weight: 0.85)
    /// The copy control stays a fixed slot. It does not absorb spare width.
    static let copy = Column(floor: 24, minimum: 24, weight: 0)

    static let columns: [Column] = [status, name, lastOnline, usage, quota, copy]

    static var minimumRowWidth: Double {
        columns.reduce(0) { $0 + $1.minimum } + spacing * Double(columns.count - 1)
    }

    /// Width of each column for a row that is `available` points wide, including
    /// the gaps. The widths plus the gaps equal `available` whenever the row is
    /// at least as wide as the gaps.
    static func widths(available: Double) -> [Double] {
        let count = columns.count
        guard count > 0 else { return [] }
        let gapBudget = spacing * Double(count - 1)
        let content = max(0, available - gapBudget)
        let floors = columns.map(\.floor)
        let minimums = columns.map(\.minimum)
        let weights = columns.map(\.weight)
        let floorSum = floors.reduce(0, +)
        let minimumSum = minimums.reduce(0, +)
        let weightSum = weights.reduce(0, +)

        var result: [Double]
        if floorSum <= 0 || weightSum <= 0 {
            result = Array(repeating: content / Double(count), count: count)
        } else if content <= floorSum {
            let scale = content / floorSum
            result = floors.map { $0 * scale }
        } else if content < minimumSum {
            let deficit = minimumSum - content
            let slacks = zip(minimums, floors).map { max(0, $0 - $1) }
            let slackSum = slacks.reduce(0, +)
            if slackSum <= 0 {
                let scale = minimumSum > 0 ? content / minimumSum : 0
                result = minimums.map { $0 * scale }
            } else {
                result = zip(minimums, slacks).map { minimum, slack in
                    minimum - deficit * slack / slackSum
                }
            }
        } else {
            let extra = content - minimumSum
            result = zip(minimums, weights).map { minimum, weight in
                minimum + extra * weight / weightSum
            }
        }

        let drift = content - result.reduce(0, +)
        if let widest = result.indices.max(by: { result[$0] < result[$1] }) {
            result[widest] += drift
        }
        return result
    }
}
