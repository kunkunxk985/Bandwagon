import Foundation

@main
struct SettingsPersistenceRegression {
    static func main() throws {
        let keychain = try source("Sources/Bandwagon/Services/KeychainCredentialStore.swift")
        let settings = try source("Sources/Bandwagon/Services/SettingsStore.swift")
        let overview = try source("Sources/Bandwagon/Services/OverviewCacheStore.swift")
        let helper = try source("Sources/BandwagonCredentialBridge/main.swift")
        let package = try source("scripts/package-app.sh")

        require(
            settings.contains("static let applicationSupportBandwagon = \"Bandwagon\"") &&
            settings.contains("static let settingsFileName = \"settings.json\"") &&
            settings.contains("Library/Application Support/\\(applicationSupportBandwagon)/"),
            "user settings must stay under a stable Application Support path"
        )
        require(
            overview.contains("SettingsStore.applicationSupportBandwagon") &&
            overview.contains("SettingsStore.overviewCacheFileName"),
            "overview cache must share the same Application Support folder"
        )
        require(
            !settings.contains(".github-update-token") && !keychain.contains(".github-update-token"),
            "GitHub update token sidecar removed for public releases"
        )
        require(
            helper.contains("com.kun.bandwagon.credentials.v3") &&
            package.contains("com.kun.bandwagon"),
            "bundle id and keychain service names must stay stable across upgrades"
        )
        require(
            keychain.contains("installedDigest == helperSHA256") &&
            keychain.contains("installHelper(data:") &&
            !keychain.contains("if fm.isExecutableFile(atPath: helperURL.path) {\n            return true"),
            "ensureHelperInstalled must upgrade stale Application Support helpers when the app pin moves"
        )
        require(
            settings.contains("SettingsLoadResult") &&
            settings.contains("credentialAccessWarning") &&
            settings.contains("jsonSecretsEmpty") &&
            settings.contains("persistenceObject") &&
            settings.contains("object[\"BWH_API_KEY\"] = settings.bwhApiKey"),
            "settings load must prefer settings.json secrets and surface keychain gaps without blocking saves"
        )

        pass("settings persistence paths and helper upgrade policy")
    }

    private static func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            print("FAIL \(message)")
            exit(1)
        }
    }

    private static func pass(_ name: String) {
        print("PASS \(name)")
    }
}
