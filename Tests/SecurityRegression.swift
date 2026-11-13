import Foundation
import CryptoKit

@main
struct SecurityRegression {
    static func main() throws {
        let client = try source("Sources/Bandwagon/Services/XUIClient.swift")
        let settings = try source("Sources/Bandwagon/Services/SettingsStore.swift")
        let settingsView = try source("Sources/Bandwagon/Views/Pages/SettingsView.swift")
        let appModel = try source("Sources/Bandwagon/Services/AppModel.swift")
        let app = try source("Sources/Bandwagon/BandwagonApp.swift")
        let packageScript = try source("scripts/package-app.sh")
        let keychain = try source("Sources/Bandwagon/Services/KeychainCredentialStore.swift")
        let helper = try source("Sources/BandwagonCredentialBridge/main.swift")
        let installer = (try? source("scripts/install-credential-bridge.sh")) ?? ""
        require(
            installer.contains("--replace-unused-stub") &&
            installer.contains("com.kun.bandwagon.credentials.v3") &&
            installer.contains("verify-credential-bridge.sh") &&
            !installer.contains("codesign --force"),
            "helper installation must be an explicit one-time verified release, never a rebuild"
        )
        require(
            helper.contains("let parentPID = getppid()") &&
            helper.contains("getppid() == parentPID"),
            "credential helper must reject requests after its authenticated parent exits"
        )

        require(
            !client.contains("InsecureSessionDelegate") &&
            !client.contains(".useCredential") &&
            !client.contains("verifySSL:") &&
            !settings.contains("xuiVerifySsl") &&
            !settingsView.contains("校验 SSL"),
            "TLS certificate verification must not be optional or bypassed"
        )

        require(
            !packageScript.contains("NSAllowsArbitraryLoads"),
            "Packaged app must not opt out of App Transport Security"
        )

        require(
            !settings.contains("GITHUB_UPDATE_TOKEN") &&
            !settings.contains("githubUpdateToken"),
            "in-app updates use the public GitHub API; no PAT field in settings"
        )

        require(
            settings.contains("KeychainCredentialStore.save") &&
            !settings.contains("current[\"BWH_API_KEY\"] =") &&
            !settings.contains("current[\"XUI_API_TOKEN\"] =") &&
            !settings.contains("current[\"XUI_USERNAME\"] =") &&
            !settings.contains("current[\"XUI_PASSWORD\"] ="),
            "long-lived credentials must be written to Keychain rather than plaintext JSON"
        )
        require(
            helper.contains("com.kun.bandwagon.credentials.v3") &&
            helper.contains("com.kun.bandwagon.credentials.v2") &&
            !helper.contains("SecItemDelete") &&
            keychain.contains("CredentialBridgeClient.perform") &&
            keychain.contains("Bundle.main.bundleIdentifier == \"com.kun.bandwagon\"") &&
            keychain.contains("Bundle.main.bundleURL.pathExtension == \"app\"") &&
            !keychain.contains("SecItemCopyMatching") &&
            !keychain.contains("SecItemAdd") &&
            !keychain.contains("SecItemUpdate"),
            "only the signed helper may touch Keychain; old items must be preserved"
        )
        require(
            packageScript.contains("Bandwagon Local Code Signing") &&
            !packageScript.contains("--sign - ") &&
            packageScript.contains("verify-credential-bridge.sh"),
            "packaging must verify the unchanged helper and never fall back to ad-hoc signing"
        )
        let pinnedDigest = (try? source("scripts/credential-bridge.sha256"))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let releaseBytes = try? Data(contentsOf: URL(fileURLWithPath: "ReleaseAssets/BandwagonCredentialBridge-v1"))
        let actualDigest = releaseBytes.map {
            SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined()
        } ?? ""
        require(
            pinnedDigest.count == 64 &&
            pinnedDigest == actualDigest &&
            keychain.contains("helperSHA256 = \"\(pinnedDigest)\""),
            "the shipped helper bytes and app's pinned digest must match"
        )

        require(
            !settings.contains("settings.xuiTwoFactor =") &&
            !settings.contains("current[\"XUI_TWO_FACTOR\"] =") &&
            settings.contains("\"XUI_TWO_FACTOR\",") &&
            settings.contains("for key in secretKeys") &&
            appModel.contains("settings.xuiTwoFactor = \"\""),
            "one-time 2FA codes must not be persisted or reused after a refresh attempt"
        )

        require(
            appModel.contains("let persistence = Task.detached(priority: .userInitiated) { SettingsStore.save(newValue) }") &&
            appModel.contains("guard await persistence.value else {") &&
            appModel.contains("async -> Bool") &&
            settingsView.contains("let didSave = await model.saveSettings(draft)") &&
            settingsView.contains("if didSave"),
            "Settings UI must not report success when secure persistence fails"
        )

        require(
            appModel.contains("var settings = AppSettings()") &&
            appModel.contains("func restoreSettings() async") &&
            appModel.contains("Task.detached") &&
            app.contains(".task { await model.start() }") &&
            !app.contains("await model.restoreSettings()") &&
            appModel.contains("func start() async") &&
            (appModel.range(of: "await restoreSettings()")?.lowerBound ?? appModel.endIndex) <
            (appModel.range(of: "        await load()\n        startAutoRefresh()")?.lowerBound ?? appModel.startIndex),
            "Keychain migration must run off the main actor after the window appears"
        )

        // getServiceInfo does not return used disk or the live run state; both belong to
        // getLiveServiceInfo (KVM only). Reading them from the wrong response silently
        // produced a blank disk bar and a hardcoded "running" pill.
        let bwh = try source("Sources/Bandwagon/Services/BWHClient.swift")
        require(
            bwh.contains("optionalData(\"getLiveServiceInfo\"") &&
            bwh.contains("diskUsed(live)") &&
            !bwh.contains("info[\"ve_used_disk_space_b\"]"),
            "disk usage and run state must be read from getLiveServiceInfo, not getServiceInfo"
        )

        print("PASS transport, Keychain persistence, TLS verification, ephemeral 2FA policies, and KiwiVM endpoint selection")
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
}
