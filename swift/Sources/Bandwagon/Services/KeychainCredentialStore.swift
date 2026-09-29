import Foundation
import LocalAuthentication
import Security

struct StoredCredentials: Codable, Equatable {
    var bwhApiKey: String
    var xuiApiToken: String
    var xuiUsername: String
    var xuiPassword: String

    init(settings: AppSettings) {
        bwhApiKey = settings.bwhApiKey
        xuiApiToken = settings.xuiApiToken
        xuiUsername = settings.xuiUsername
        xuiPassword = settings.xuiPassword
    }

    func apply(to settings: inout AppSettings) {
        settings.bwhApiKey = bwhApiKey
        settings.xuiApiToken = xuiApiToken
        settings.xuiUsername = xuiUsername
        settings.xuiPassword = xuiPassword
    }
}

enum KeychainCredentialStore {
    // This digest pins the separately installed, unchanged helper release. It
    // must be replaced with its verified signed binary digest before packaging.
    private static let helperSHA256 = "c2837967ec2a78df545eedc470cc91c25c7b402ac202de815ad2127cb6784724"
    private static let migrationFlag = "BandwagonCredentialBridgeV3MigrationAttempted"
    private static let helperURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Bandwagon/BandwagonCredentialBridge")

    private static var isActualApp: Bool {
        Bundle.main.bundleIdentifier == "com.kun.bandwagon" &&
        Bundle.main.bundleURL.pathExtension == "app"
    }

    static func load() -> StoredCredentials? {
        guard isActualApp,
              let result = CredentialBridgeClient.perform(
                "load", at: helperURL, expectedSHA256: helperSHA256, timeoutSeconds: 20
              ) else { return nil }
        if result.status == "ok", let data = result.credentials {
            return try? JSONDecoder().decode(StoredCredentials.self, from: data)
        }
        // An ordinary read never consults the old item. Request migration only
        // once, on first launch after the window exists; denial is not retried.
        guard result.status == "missing",
              !UserDefaults.standard.bool(forKey: migrationFlag) else { return nil }
        UserDefaults.standard.set(true, forKey: migrationFlag)
        guard let migrated = CredentialBridgeClient.perform(
            "migrate", at: helperURL, expectedSHA256: helperSHA256, timeoutSeconds: 180
        ), migrated.status == "ok", let data = migrated.credentials else { return nil }
        return try? JSONDecoder().decode(StoredCredentials.self, from: data)
    }

    @discardableResult
    static func save(_ settings: AppSettings) -> Bool {
        guard isActualApp,
              let data = try? JSONEncoder().encode(StoredCredentials(settings: settings)) else {
            return false
        }
        return CredentialBridgeClient.perform(
            "save", credentials: data, at: helperURL,
            expectedSHA256: helperSHA256, timeoutSeconds: 20
        )?.status == "ok"
    }
}

