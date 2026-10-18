import Foundation

@main
struct CredentialHelperRegression {
    static func main() {
        let helper = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Bandwagon/BandwagonCredentialBridge")
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            fail("credential helper is not installed")
        }

        let process = Process()
        process.executableURL = helper
        process.arguments = ["load"]
        process.standardInput = FileHandle.nullDevice
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            fail("credential helper could not start")
        }
        guard process.terminationStatus == 77,
              output.fileHandleForReading.readDataToEndOfFile().isEmpty else {
            fail("a non-Bandwagon caller must not receive Keychain data")
        }
        print("PASS credential helper rejects callers without Bandwagon's signed app identity")
    }

    private static func fail(_ message: String) -> Never {
        print("FAIL \(message)")
        exit(1)
    }
}
