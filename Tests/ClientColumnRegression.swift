import Foundation

@main
struct ClientColumnRegression {
    static func main() {
        guard ClientColumnShare.columns.count == 7 else {
            fail("the clients table has status, name, last online, usage, quota, expiry, and copy")
        }
        guard ClientColumnShare.columns.map(\.minimum) == [
            ClientColumnShare.status.minimum,
            ClientColumnShare.name.minimum,
            ClientColumnShare.lastOnline.minimum,
            ClientColumnShare.usage.minimum,
            ClientColumnShare.quota.minimum,
            ClientColumnShare.expiry.minimum,
            ClientColumnShare.copy.minimum,
        ] else {
            fail("column order must stay status, name, last online, usage, quota, expiry, copy")
        }
        for column in ClientColumnShare.columns where column.floor > column.minimum || column.weight < 0 {
            fail("a column floor must sit at or below its minimum")
        }
        guard ClientColumnShare.copy.weight == 0, ClientColumnShare.lastOnline.floor == ClientColumnShare.lastOnline.minimum else {
            fail("the timestamp and the copy slot must not be the columns that give up width")
        }
        guard ClientColumnShare.usage.weight == ClientColumnShare.columns.map(\.weight).max() else {
            fail("the usage line must take the largest share of spare width")
        }

        let samples = [640.0, 716, ClientColumnShare.minimumRowWidth, 900, 1240, 1600, 2200]
        var previous = widths(samples[0])
        for available in samples.dropFirst() {
            let next = widths(available)
            for index in next.indices where next[index] + 0.001 < previous[index] {
                fail("widening the row to \(available) must not shrink column \(index)")
            }
            previous = next
        }

        let narrow = widths(716)
        guard abs(narrow[2] - ClientColumnShare.lastOnline.minimum) < 0.01 else {
            fail("a narrow window must keep the full last-online timestamp, got \(narrow[2])")
        }
        guard narrow[3] + 0.01 >= ClientColumnShare.usage.floor else {
            fail("the usage line must keep room for its figures, got \(narrow[3])")
        }
        let wide = widths(1800)
        for index in 0..<6 where wide[index] <= narrow[index] {
            fail("column \(index) must grow between a narrow window and a wide one")
        }
        guard abs(wide[6] - ClientColumnShare.copy.minimum) < 0.01 else {
            fail("the copy slot must stay at its minimum once the row has room, got \(wide[6])")
        }
        guard wide[3] > wide[1], wide[3] > wide[2], wide[3] > wide[5] else {
            fail("the usage column must be the widest text column on a wide row")
        }

        print("PASS client columns fill the row and spread as the window grows")
    }

    private static func widths(_ available: Double) -> [Double] {
        let widths = ClientColumnShare.widths(available: available)
        let gaps = ClientColumnShare.spacing * Double(widths.count - 1)
        let sum = widths.reduce(0, +) + gaps
        if abs(sum - available) > 0.01 {
            fail("columns plus gaps must fill \(available), got \(sum)")
        }
        if widths.contains(where: { $0 < 0 || $0.isNaN }) {
            fail("column widths must stay finite and non-negative at \(available)")
        }
        return widths
    }

    private static func fail(_ message: String) -> Never {
        print("FAIL \(message)")
        exit(1)
    }
}
