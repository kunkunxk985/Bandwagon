import Foundation

enum ReleaseUpdateError: LocalizedError {
    case githubUnavailable
    case invalidResponse
    case noDmgAsset
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .githubUnavailable:
            return "无法连接 GitHub，请浏览器打开 Releases"
        case .invalidResponse:
            return "GitHub 返回了无法识别的发布信息。"
        case .noDmgAsset:
            return "最新发布中没有找到 macOS 安装包。"
        case .downloadFailed(let detail):
            return detail
        }
    }
}

struct ReleaseUpdateInfo: Equatable {
    let version: String
    let dmgDownloadURL: URL
}

enum ReleaseUpdateClient {
    static let repoOwner = "kunkunxk985"
    static let repoName = "Bandwagon"
    static let latestReleaseAPI = URL(string: "https://api.github.com/repos/kunkunxk985/Bandwagon/releases/latest")!
    static let latestReleasePage = URL(string: "https://github.com/kunkunxk985/Bandwagon/releases/latest")!

    enum CheckOutcome: Equatable {
        case upToDate
        case updateAvailable(ReleaseUpdateInfo)
    }

    static var installedVersion: String {
        let raw = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "0" : trimmed
    }

    static func checkForUpdate(session: URLSession = .shared) async throws -> CheckOutcome {
        let release = try await fetchLatestRelease(session: session)
        let version = SemverVersion.normalizeTag(release.tagName)
        guard SemverVersion.isVersion(version, newerThan: installedVersion) else {
            return .upToDate
        }
        guard let asset = selectDmgAsset(from: release.assets),
              let url = URL(string: asset.browserDownloadURL) else {
            throw ReleaseUpdateError.noDmgAsset
        }
        return .updateAvailable(ReleaseUpdateInfo(version: version, dmgDownloadURL: url))
    }

    static func downloadRelease(dmgURL: URL, version: String, session: URLSession = .shared) async throws -> URL {
        let destination = downloadsDirectory()
            .appendingPathComponent("Bandwagon-\(version)-macOS.dmg", isDirectory: false)

        var request = URLRequest(url: dmgURL)
        request.setValue("Bandwagon", forHTTPHeaderField: "User-Agent")

        let (temporaryURL, response) = try await session.download(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ReleaseUpdateError.downloadFailed("下载失败：服务器未返回有效响应。")
        }
        guard (200 ... 299).contains(http.statusCode) else {
            throw ReleaseUpdateError.downloadFailed("下载失败（HTTP \(http.statusCode)）。")
        }

        let manager = FileManager.default
        if manager.fileExists(atPath: destination.path) {
            try manager.removeItem(at: destination)
        }
        try manager.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    private struct GitHubRelease: Decodable {
        let tagName: String
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case assets
        }

        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: String

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }
    }

    private static func fetchLatestRelease(session: URLSession) async throws -> GitHubRelease {
        var request = URLRequest(url: latestReleaseAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Bandwagon", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            let code = (error as NSError).code
            if code == NSURLErrorTimedOut {
                throw ReleaseUpdateError.downloadFailed("连接 GitHub 超时，请检查网络。")
            }
            throw ReleaseUpdateError.githubUnavailable
        }

        guard let http = response as? HTTPURLResponse else {
            throw ReleaseUpdateError.invalidResponse
        }
        if http.statusCode == 401 || http.statusCode == 403 || http.statusCode == 404 {
            throw ReleaseUpdateError.githubUnavailable
        }
        guard (200 ... 299).contains(http.statusCode) else {
            throw ReleaseUpdateError.githubUnavailable
        }
        guard let release = try? JSONDecoder().decode(GitHubRelease.self, from: data) else {
            throw ReleaseUpdateError.invalidResponse
        }
        return release
    }

    private static func selectDmgAsset(from assets: [GitHubRelease.Asset]) -> GitHubRelease.Asset? {
        assets.first { asset in
            asset.name.hasPrefix("Bandwagon-") && asset.name.hasSuffix("-macOS.dmg")
        }
    }

    private static func downloadsDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
    }
}

enum SemverVersion {
    static func normalizeTag(_ tag: String) -> String {
        var value = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("v") || value.hasPrefix("V") {
            value.removeFirst()
        }
        if let dash = value.firstIndex(of: "-") {
            value = String(value[..<dash])
        }
        return value
    }

    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = segments(lhs)
        let right = segments(rhs)
        let count = max(left.count, right.count)
        for index in 0 ..< count {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b {
                return a > b ? .orderedDescending : .orderedAscending
            }
        }
        return .orderedSame
    }

    static func isVersion(_ candidate: String, newerThan installed: String) -> Bool {
        compare(candidate, installed) == .orderedDescending
    }

    private static func segments(_ version: String) -> [Int] {
        normalizeTag(version)
            .split(separator: ".", omittingEmptySubsequences: false)
            .map { Int($0) ?? 0 }
    }
}
