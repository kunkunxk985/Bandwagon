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

    /// Automatically zeroes all 3X-UI clients' traffic at the exact Bandwagon
    /// server traffic reset timestamp (`bwh.resetAt`) and keeps 3X-UI built-in
    /// traffic reset set to "never".
    var syncClientResetWithServer = true
    /// Current cycle's Bandwagon `resetAt` (epoch seconds) awaiting automatic reset.
    var pendingServerResetAt = 0
    /// Last `resetAt` (epoch seconds) for which all 3X-UI clients were automatically reset.
    var lastExecutedServerResetAt = 0
    /// Epoch seconds when 3X-UI clients' built-in reset policy was last verified as "never".
    var normalizedXuiResetPolicyAt = 0

    static let defaultRefreshSeconds = 300
    /// 0 means "only refresh when I ask". Anything above re-reads the panel on a timer.
    static let refreshChoices = [0, 60, 300, 900, 1800]

    var bwhReady: Bool { !bwhVeid.isEmpty && !bwhApiKey.isEmpty }
    var xuiReady: Bool { !xuiBaseUrl.isEmpty && !xuiUsername.isEmpty && !xuiPassword.isEmpty }
}

struct SettingsLoadResult: Sendable, Equatable {
    var settings: AppSettings
    var credentialAccessWarning: String?
}

enum SettingsStore {
    static let applicationSupportBandwagon = "Bandwagon"
    static let settingsFileName = "settings.json"
    static let overviewCacheFileName = "cache.json"
    private static let secretKeys = [
        "BWH_API_KEY",
        "XUI_API_TOKEN",
        "XUI_USERNAME",
        "XUI_PASSWORD",
        "XUI_TWO_FACTOR",
        "XUI_VERIFY_SSL",
    ]

    /// Keys the old web build wrote and nothing reads any more. Merging writes
    /// keep every existing key, so without this they would ride along forever.
    static let retiredKeys = ["REFRESH_INTERVAL", "THEME"]

    private static let backupDefaultsKey = "BandwagonNonSecretSettingsBackup"

    private static var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
    }

    /// Lives beside the credential helper, in the app's own folder.
    static var configDirectoryURL: URL {
        supportDirectory.appendingPathComponent(applicationSupportBandwagon, isDirectory: true)
    }

    private static var fileURL: URL {
        configDirectoryURL.appendingPathComponent(settingsFileName)
    }

    /// True when settings.json (or its backup) already names a connection, even if
    /// secrets are still empty — used to skip first-launch wizard for upgraders.
    static func hasPersistedConnectionHints() -> Bool {
        let object = loadObject()
        return !JSONValue.string(object["BWH_VEID"]).isEmpty ||
            !JSONValue.string(object["XUI_BASE_URL"]).isEmpty ||
            !JSONValue.string(object["BWH_API_KEY"]).isEmpty
    }

    static func load() -> SettingsLoadResult {
        var settings = AppSettings()
        var object = loadObject()
        // Drop retired keys once, touching nothing else in the file.
        if retiredKeys.contains(where: { object[$0] != nil }) {
            for key in retiredKeys { object.removeValue(forKey: key) }
            _ = writeObject(object)
        }

        settings.bwhVeid = JSONValue.string(object["BWH_VEID"])
        let bwhBase = JSONValue.string(object["BWH_API_BASE"])
        if !bwhBase.isEmpty { settings.bwhApiBase = bwhBase }
        settings.xuiBaseUrl = JSONValue.string(object["XUI_BASE_URL"])

        settings.bwhApiKey = JSONValue.string(object["BWH_API_KEY"])
        settings.xuiApiToken = JSONValue.string(object["XUI_API_TOKEN"])
        settings.xuiUsername = JSONValue.string(object["XUI_USERNAME"])
        settings.xuiPassword = JSONValue.string(object["XUI_PASSWORD"])

        var strippedEphemeralSecrets = false
        for key in secretKeys where key == "XUI_TWO_FACTOR" || key == "XUI_VERIFY_SSL" {
            if object.removeValue(forKey: key) != nil {
                strippedEphemeralSecrets = true
            }
        }

        // A stored 0 means "polling off", so presence of the key is what matters —
        // reading it as a plain Int would silently restore the default interval.
        if let stored = object["REFRESH_SECONDS"] {
            settings.refreshSeconds = max(0, JSONValue.int(stored))
        }
        if let storedSync = object["SYNC_CLIENT_RESET_WITH_SERVER"] {
            settings.syncClientResetWithServer = JSONValue.bool(storedSync, default: true)
        }
        if let storedPending = object["PENDING_SERVER_RESET_AT"] {
            settings.pendingServerResetAt = max(0, JSONValue.int(storedPending))
        }
        if let storedExecuted = object["LAST_EXECUTED_SERVER_RESET_AT"] {
            settings.lastExecutedServerResetAt = max(0, JSONValue.int(storedExecuted))
        }
        if let storedNormalized = object["NORMALIZED_XUI_RESET_POLICY_AT"] {
            settings.normalizedXuiResetPolicyAt = max(0, JSONValue.int(storedNormalized))
        }

        var credentialAccessWarning: String?
        let credentialLoad = KeychainCredentialStore.load()
        if jsonSecretsEmpty(settings), let credentials = credentialLoad.credentials {
            credentials.apply(to: &settings)
            _ = writeObject(persistenceObject(for: settings, merging: object))
        } else if jsonSecretsEmpty(settings),
                  let warning = credentialLoad.warning,
                  settingsLookPreviouslyConfigured(settings, object: object) {
            credentialAccessWarning = warning
        }

        if strippedEphemeralSecrets, !jsonSecretsEmpty(settings) {
            _ = writeObject(persistenceObject(for: settings, merging: object))
        } else if strippedEphemeralSecrets {
            _ = writeObject(object)
        }

        return SettingsLoadResult(settings: settings, credentialAccessWarning: credentialAccessWarning)
    }

    private static func jsonSecretsEmpty(_ settings: AppSettings) -> Bool {
        settings.bwhApiKey.isEmpty &&
            settings.xuiApiToken.isEmpty &&
            settings.xuiUsername.isEmpty &&
            settings.xuiPassword.isEmpty
    }

    private static func settingsLookPreviouslyConfigured(_ settings: AppSettings, object: [String: Any]) -> Bool {
        !settings.bwhVeid.isEmpty ||
            !settings.xuiBaseUrl.isEmpty ||
            !JSONValue.string(object["BWH_VEID"]).isEmpty ||
            !JSONValue.string(object["XUI_BASE_URL"]).isEmpty
    }

    @discardableResult
    static func save(_ settings: AppSettings) -> Bool {
        guard writeObject(persistenceObject(for: settings, merging: loadObject())) else { return false }
        _ = KeychainCredentialStore.save(settings)
        return true
    }

    @discardableResult
    static func savePreferences(_ settings: AppSettings) -> Bool {
        writeObject(persistenceObject(for: settings, merging: loadObject()))
    }

    private static func loadObject() -> [String: Any] {
        if let data = try? Data(contentsOf: fileURL),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           !object.isEmpty {
            UserDefaults.standard.set(object, forKey: backupDefaultsKey)
            return object
        }
        if let backup = UserDefaults.standard.dictionary(forKey: backupDefaultsKey), !backup.isEmpty {
            _ = writeObject(backup)
            return backup
        }
        return [:]
    }

    private static func persistenceObject(
        for settings: AppSettings,
        merging existing: [String: Any]
    ) -> [String: Any] {
        var object = existing
        object["BWH_VEID"] = settings.bwhVeid
        object["BWH_API_BASE"] = settings.bwhApiBase
        object["BWH_API_KEY"] = settings.bwhApiKey
        object["XUI_BASE_URL"] = settings.xuiBaseUrl
        object["XUI_API_TOKEN"] = settings.xuiApiToken
        object["XUI_USERNAME"] = settings.xuiUsername
        object["XUI_PASSWORD"] = settings.xuiPassword
        object["REFRESH_SECONDS"] = settings.refreshSeconds
        object["SYNC_CLIENT_RESET_WITH_SERVER"] = settings.syncClientResetWithServer
        object["PENDING_SERVER_RESET_AT"] = settings.pendingServerResetAt
        object["LAST_EXECUTED_SERVER_RESET_AT"] = settings.lastExecutedServerResetAt
        object["NORMALIZED_XUI_RESET_POLICY_AT"] = settings.normalizedXuiResetPolicyAt
        if !settings.xuiTwoFactor.isEmpty {
            object["XUI_TWO_FACTOR"] = settings.xuiTwoFactor
        } else {
            object.removeValue(forKey: "XUI_TWO_FACTOR")
        }
        for key in retiredKeys + ["XUI_VERIFY_SSL"] {
            object.removeValue(forKey: key)
        }
        return object
    }

    private static func writeObject(_ object: [String: Any]) -> Bool {
        UserDefaults.standard.set(object, forKey: backupDefaultsKey)
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
