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

    struct LoadResult: Sendable, Equatable {
        var credentials: StoredCredentials?
        var warning: String?
    }

    static func load() -> LoadResult {
        guard isActualApp else { return LoadResult() }
        guard ensureHelperInstalled() else {
            return LoadResult(
                warning: "凭据辅助程序未能安装。请把 Bandwagon 放在「应用程序」文件夹后重新打开；设置文件不会被删除。"
            )
        }
        guard let result = CredentialBridgeClient.perform(
                "load", at: helperURL, expectedSHA256: helperSHA256, timeoutSeconds: 20
              ) else {
            return LoadResult(
                warning: "无法读取钥匙串凭据（辅助程序未通过校验）。若刚更新应用，请重新打开一次；不要删除 ~/Library/Application Support/Bandwagon/。"
            )
        }
        if result.status == "ok", let data = result.credentials,
           let credentials = try? JSONDecoder().decode(StoredCredentials.self, from: data) {
            return LoadResult(credentials: credentials)
        }
        if result.status == "denied" {
            return LoadResult(warning: "钥匙串拒绝了凭据访问。已保存的数据未被清除，请在系统提示中选择允许后重试。")
        }
        if result.status == "error" {
            return LoadResult(warning: "读取钥匙串凭据时出错。已保留 settings.json 中的非敏感设置。")
        }
        // An ordinary read never consults the old item. Request migration only
        // once, on first launch after the window exists; denial is not retried.
        guard result.status == "missing",
              !UserDefaults.standard.bool(forKey: migrationFlag) else {
            return LoadResult()
        }
        UserDefaults.standard.set(true, forKey: migrationFlag)
        guard let migrated = CredentialBridgeClient.perform(
            "migrate", at: helperURL, expectedSHA256: helperSHA256, timeoutSeconds: 180
        ), migrated.status == "ok", let data = migrated.credentials,
              let credentials = try? JSONDecoder().decode(StoredCredentials.self, from: data) else {
            let warning = UserDefaults.standard.bool(forKey: migrationFlag)
                ? "未能从旧钥匙串条目迁移凭据。"
                : nil
            return LoadResult(warning: warning)
        }
        return LoadResult(credentials: credentials)
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
        return true
    }
}

