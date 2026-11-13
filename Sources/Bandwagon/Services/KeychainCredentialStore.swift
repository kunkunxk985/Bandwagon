import Foundation
import CryptoKit
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

private enum GithubUpdateTokenStore {
    private static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Bandwagon/.github-update-token", isDirectory: false)
    }

    static func load() -> String {
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    static func save(_ token: String) -> Bool {
        let directory = fileURL.deletingLastPathComponent()
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            if trimmed.isEmpty {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    try FileManager.default.removeItem(at: fileURL)
                }
                return true
            }
            try Data(trimmed.utf8).write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            return true
        } catch {
            return false
        }
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

    @discardableResult
    private static func ensureHelperInstalled() -> Bool {
        let fm = FileManager.default
        if fm.isExecutableFile(atPath: helperURL.path) {
            return true
        }
        guard let bundleHelper = Bundle.main.url(forResource: "BandwagonCredentialBridge", withExtension: nil),
              let helperData = try? Data(contentsOf: bundleHelper) else {
            return false
        }
        let digest = SHA256.hash(data: helperData).map { String(format: "%02x", $0) }.joined()
        guard digest == helperSHA256 else { return false }

        let dir = helperURL.deletingLastPathComponent()
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let tempURL = dir.appendingPathComponent(".BandwagonCredentialBridge.new.\(UUID().uuidString)")
            try helperData.write(to: tempURL, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: tempURL.path)
            _ = try? fm.removeItem(at: helperURL)
            try fm.moveItem(at: tempURL, to: helperURL)
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helperURL.path)
            return true
        } catch {
            return false
        }
    }

    static func load() -> StoredCredentials? {
        guard isActualApp else { return nil }
        ensureHelperInstalled()
        guard let result = CredentialBridgeClient.perform(
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

    static func loadGithubUpdateToken() -> String {
        guard isActualApp else { return "" }
        return GithubUpdateTokenStore.load()
    }

    @discardableResult
    static func save(_ settings: AppSettings) -> Bool {
        guard isActualApp,
              let data = try? JSONEncoder().encode(StoredCredentials(settings: settings)) else {
            return false
        }
        ensureHelperInstalled()
        guard CredentialBridgeClient.perform(
            "save", credentials: data, at: helperURL,
            expectedSHA256: helperSHA256, timeoutSeconds: 20
        )?.status == "ok" else { return false }
        return GithubUpdateTokenStore.save(settings.githubUpdateToken)
    }
}

