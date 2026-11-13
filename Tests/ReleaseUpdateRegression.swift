import Foundation

@main
struct ReleaseUpdateRegression {
    static func main() {
        guard SemverVersion.compare("3.0.1", "3.0.0") == .orderedDescending else {
            fail("patch bump must count as newer")
        }
        guard SemverVersion.compare("3.1.0", "3.0.9") == .orderedDescending else {
            fail("minor bump must count as newer")
        }
        guard SemverVersion.compare("4.0.0", "3.9.9") == .orderedDescending else {
            fail("major bump must count as newer")
        }
        guard SemverVersion.compare("3.0.0", "3.0.0") == .orderedSame else {
            fail("identical versions must compare equal")
        }
        guard SemverVersion.compare("3.0", "3.0.0") == .orderedSame else {
            fail("missing patch segment must compare as zero")
        }
        guard SemverVersion.normalizeTag("v3.2.1") == "3.2.1",
              SemverVersion.normalizeTag("V1.0.0-beta") == "1.0.0" else {
            fail("tag normalization must strip v prefix and pre-release suffix")
        }
        guard SemverVersion.isVersion("3.0.1", newerThan: "3.0.0"),
              !SemverVersion.isVersion("2.9.9", newerThan: "3.0.0") else {
            fail("isVersion must mirror compare")
        }
        pass("release-update semver")
    }

    private static func pass(_ name: String) {
        print("PASS \(name)")
    }

    private static func fail(_ message: String) -> Never {
        fputs("FAIL \(message)\n", stderr)
        exit(1)
    }
}
