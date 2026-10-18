import Foundation

@main
struct SettingsMigrationRegression {
    static func main() throws {
        func require(_ condition: Bool, _ message: String) {
            if !condition { print("FAIL \(message)"); exit(1) }
        }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("bandwagon-migration-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        let legacy = root.appendingPathComponent("WagongDeck/settings.json")
        let current = root.appendingPathComponent("Bandwagon/settings.json")
        let payload = Data(#"{"BWH_VEID":"123","REFRESH_SECONDS":300}"#.utf8)

        // Nothing to move.
        require(!SettingsStore.migrateLegacyFile(from: legacy, to: current), "no legacy file means no migration")

        // Old file only: moved intact, private, and the old folder removed.
        try fm.createDirectory(at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try payload.write(to: legacy)
        require(SettingsStore.migrateLegacyFile(from: legacy, to: current), "the legacy file must be moved")
        require(try Data(contentsOf: current) == payload, "settings must arrive byte for byte")
        let mode = (try fm.attributesOfItem(atPath: current.path)[.posixPermissions] as? NSNumber)?.intValue
        require(mode == 0o600, "migrated settings must stay owner-only")
        require(!fm.fileExists(atPath: legacy.deletingLastPathComponent().path), "the emptied legacy folder must be removed")

        // Both present: the new file wins and neither is touched.
        try fm.createDirectory(at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("old".utf8).write(to: legacy)
        require(!SettingsStore.migrateLegacyFile(from: legacy, to: current), "an existing new file must never be overwritten")
        require(try Data(contentsOf: current) == payload && fm.fileExists(atPath: legacy.path),
                "a skipped migration must leave both files as they were")

        let source = try String(contentsOfFile: "Sources/Bandwagon/Services/SettingsStore.swift", encoding: .utf8)
        require(source.contains("migrateLegacyFile(from: legacyFileURL, to: fileURL)") &&
                source.contains("Bandwagon/settings.json"),
                "load() must migrate into the Bandwagon folder before reading")
        require(SettingsStore.retiredKeys == ["REFRESH_INTERVAL", "THEME"] &&
                source.contains("for key in secretKeys + retiredKeys") &&
                source.contains("for key in retiredKeys { object.removeValue(forKey: key) }"),
                "web-era keys must be dropped on load and on every save")

        print("PASS settings move from WagongDeck to Bandwagon once, intact and private, never overwriting; web-era keys dropped")
    }
}
