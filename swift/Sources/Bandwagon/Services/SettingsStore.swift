import Foundation

struct AppSettings: Equatable, Sendable {
    /// Automatic refresh interval in seconds; 0 disables polling.
    var refreshSeconds = AppSettings.defaultRefreshSeconds

    var bwhVeid = ""
    var bwhApiKey = ""
    var bwhApiBase = "https://api.64clouds.com/v1"
    var xuiBaseUrl = ""
    var xuiApiToken = ""
    var xuiUsername = ""
    var xuiPassword = ""
    var xuiTwoFactor = ""

    static let defaultRefreshSeconds = 300
    /// 0 means "only refresh when I ask". Anything above re-reads the panel on a timer.
    static let refreshChoices = [0, 60, 300, 900, 1800]

    var bwhReady: Bool { !bwhVeid.isEmpty && !bwhApiKey.isEmpty }
    var xuiReady: Bool { !xuiBaseUrl.isEmpty && (!xuiApiToken.isEmpty || (!xuiUsername.isEmpty && !xuiPassword.isEmpty)) }
}

enum SettingsStore {
    private static let secretKeys = [
        "BWH_API_KEY",
        "XUI_API_TOKEN",
        "XUI_USERNAME",
        "XUI_PASSWORD",
        "XUI_TWO_FACTOR",
        "XUI_VERIFY_SSL",
    ]

    private static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/WagongDeck/settings.json")
    }

    static func load() -> AppSettings {
        var settings = AppSettings()
        let object = loadObject()

        settings.bwhVeid = JSONValue.string(object["BWH_VEID"])
        let bwhBase = JSONValue.string(object["BWH_API_BASE"])
        if !bwhBase.isEmpty { settings.bwhApiBase = bwhBase }
        settings.xuiBaseUrl = JSONValue.string(object["XUI_BASE_URL"])

        // A stored 0 means "polling off", so presence of the key is what matters —
        // reading it as a plain Int would silently restore the default interval.
        if let stored = object["REFRESH_SECONDS"] {
            settings.refreshSeconds = max(0, JSONValue.int(stored))
        }

        if let credentials = KeychainCredentialStore.load() {
            credentials.apply(to: &settings)
        } else {
            settings.bwhApiKey = JSONValue.string(object["BWH_API_KEY"])
            settings.xuiApiToken = JSONValue.string(object["XUI_API_TOKEN"])
            settings.xuiUsername = JSONValue.string(object["XUI_USERNAME"])
            settings.xuiPassword = JSONValue.string(object["XUI_PASSWORD"])

            let hasLegacyCredentials = !settings.bwhApiKey.isEmpty ||
                !settings.xuiApiToken.isEmpty ||
                !settings.xuiUsername.isEmpty ||
                !settings.xuiPassword.isEmpty
            if hasLegacyCredentials, KeychainCredentialStore.save(settings) {
                _ = writeObject(nonSecretObject(for: settings, merging: object))
            }
        }

        return settings
    }

    @discardableResult
    static func save(_ settings: AppSettings) -> Bool {
        guard KeychainCredentialStore.save(settings) else { return false }
        return writeObject(nonSecretObject(for: settings, merging: loadObject()))
    }

    private static func loadObject() -> [String: Any] {
        guard let data = try? Data(contentsOf: fileURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object
    }

    private static func nonSecretObject(
        for settings: AppSettings,
        merging existing: [String: Any]
    ) -> [String: Any] {
        var object = existing
        object["BWH_VEID"] = settings.bwhVeid
        object["BWH_API_BASE"] = settings.bwhApiBase
        object["XUI_BASE_URL"] = settings.xuiBaseUrl
        object["REFRESH_SECONDS"] = settings.refreshSeconds
        for key in secretKeys {
            object.removeValue(forKey: key)
        }
        return object
    }

    private static func writeObject(_ object: [String: Any]) -> Bool {
        let directory = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let data = try JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys]
            )
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
