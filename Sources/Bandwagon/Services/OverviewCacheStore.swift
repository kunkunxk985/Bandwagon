import Foundation

/// Persists the last successful overview snapshot (no secrets) so the first paint
/// after launch can show stale numbers while a refresh runs.
enum OverviewCacheStore {
    private static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/\(SettingsStore.applicationSupportBandwagon)/\(SettingsStore.overviewCacheFileName)"
            )
    }

    static func load() -> OverviewResponse? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(OverviewResponse.self, from: data)
    }

    @discardableResult
    static func save(_ overview: OverviewResponse) -> Bool {
        let directory = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let data = try JSONEncoder().encode(overview)
            try data.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
            return true
        } catch {
            return false
        }
    }
}
