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

    private static func sha256Digest(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func sha256Digest(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    @discardableResult
    private static func installHelper(data helperData: Data) -> Bool {
        let fm = FileManager.default
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

    /// Installs or upgrades the Application Support helper when the embedded
    /// release matches `helperSHA256`. Replacing the .app must not strand an older
    /// on-disk helper that no longer matches the app's pinned digest.
    @discardableResult
    private static func ensureHelperInstalled() -> Bool {
        guard let bundleHelper = Bundle.main.url(forResource: "BandwagonCredentialBridge", withExtension: nil),
              let helperData = try? Data(contentsOf: bundleHelper) else {
            return false
        }
        let bundleDigest = sha256Digest(of: helperData)
        guard bundleDigest == helperSHA256 else { return false }

        let fm = FileManager.default
        if fm.isExecutableFile(atPath: helperURL.path),
           let installedDigest = sha256Digest(of: helperURL),
           installedDigest == helperSHA256 {
            return true
        }
        return installHelper(data: helperData)
    }

    private static var lastLoadWarning: String?

    static func consumeLoadWarning() -> String? {
        defer { lastLoadWarning = nil }
        return lastLoadWarning
    }

    static func load() -> StoredCredentials? {
        lastLoadWarning = nil
        guard isActualApp else { return nil }
        guard ensureHelperInstalled() else {
            lastLoadWarning =
                "凭据辅助程序未能安装。请把 Bandwagon 放在「应用程序」文件夹后重新打开；设置文件不会被删除。"
            return nil
        }
        guard let result = CredentialBridgeClient.perform(
                "load", at: helperURL, expectedSHA256: helperSHA256, timeoutSeconds: 20
              ) else {
            lastLoadWarning =
                "无法读取钥匙串凭据（辅助程序未通过校验）。若刚更新应用，请重新打开一次；不要删除 ~/Library/Application Support/Bandwagon/。"
            return nil
        }
        if result.status == "ok", let data = result.credentials {
            return try? JSONDecoder().decode(StoredCredentials.self, from: data)
        }
        if result.status == "denied" {
            lastLoadWarning = "钥匙串拒绝了凭据访问。已保存的数据未被清除，请在系统提示中选择允许后重试。"
            return nil
        }
        if result.status == "error" {
            lastLoadWarning = "读取钥匙串凭据时出错。已保留 settings.json 中的非敏感设置。"
            return nil
        }
        // An ordinary read never consults the old item. Request migration only
        // once, on first launch after the window exists; denial is not retried.
        guard result.status == "missing",
              !UserDefaults.standard.bool(forKey: migrationFlag) else {
            if result.status == "missing" {
                lastLoadWarning = nil
            }
            return nil
        }
        UserDefaults.standard.set(true, forKey: migrationFlag)
        guard let migrated = CredentialBridgeClient.perform(
            "migrate", at: helperURL, expectedSHA256: helperSHA256, timeoutSeconds: 180
        ), migrated.status == "ok", let data = migrated.credentials else {
            if UserDefaults.standard.bool(forKey: migrationFlag) {
                lastLoadWarning = "未能从旧钥匙串条目迁移凭据。"
            }
            return nil
        }
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

