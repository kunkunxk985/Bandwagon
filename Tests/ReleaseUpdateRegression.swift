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

        guard ReleaseUpdateError.privateRepoNeedsToken.errorDescription ==
                "私有仓库需在设置中填写 GitHub 令牌。" else {
            fail("privateRepoNeedsToken message must guide settings token field")
        }
        guard ReleaseUpdateClient.authFailure(token: "") == .privateRepoNeedsToken else {
            fail("empty token auth failure must be privateRepoNeedsToken")
        }
        guard case .downloadFailed = ReleaseUpdateClient.authFailure(token: "x") else {
            fail("non-empty token auth failure must describe invalid token")
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
