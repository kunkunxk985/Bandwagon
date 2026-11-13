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

        var request = URLRequest(url: URL(string: "https://api.github.com/test")!)
        ReleaseUpdateClient.applyGitHubAuth(to: &request, token: "")
        guard request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json",
              request.value(forHTTPHeaderField: "User-Agent") == "Bandwagon",
              request.value(forHTTPHeaderField: "Authorization") == nil else {
            fail("anonymous GitHub requests must set Accept and User-Agent only")
        }

        ReleaseUpdateClient.applyGitHubAuth(to: &request, token: "pat-fixture")
        guard request.value(forHTTPHeaderField: "Authorization") == "Bearer pat-fixture" else {
            fail("GitHub token must be sent as Authorization Bearer")
        }

        guard case .downloadFailed(let message) = ReleaseUpdateClient.httpAccessFailure(statusCode: 403),
              message.contains("403") else {
            fail("http access failure must describe status without mentioning settings token")
        }

        let quoted = AppUpdateInstaller.shellQuote("/tmp/foo'bar")
        guard quoted == "'/tmp/foo'\\''bar'" else {
            fail("shellQuote must escape single quotes")
        }

        let apps = URL(fileURLWithPath: "/Applications/Bandwagon.app")
        let desktop = URL(fileURLWithPath: "/Users/me/Desktop/Bandwagon.app")
        guard AppUpdateInstaller.isRunningFromApplications(apps),
              !AppUpdateInstaller.isRunningFromApplications(desktop) else {
            fail("in-app update must require /Applications/Bandwagon.app")
        }

        pass("release-update semver and GitHub auth helpers")
    }

    private static func pass(_ name: String) {
        print("PASS \(name)")
    }

    private static func fail(_ message: String) -> Never {
        fputs("FAIL \(message)\n", stderr)
        exit(1)
    }
}
