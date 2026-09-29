import Foundation

@main
struct CredentialBridgeFixtureRegression {
    private static let expectedHash = CommandLine.arguments.last ?? ""

    static func main() throws {
        guard CommandLine.arguments.count == 3 else { fail("helper path or pinned digest missing") }
        let helper = URL(fileURLWithPath: CommandLine.arguments[1])
        guard let result = try exchange(helper, operation: "load"),
              result.version == 1, result.status == "missing", result.credentials == nil else {
            fail("empty fixture Keychain must report missing without a credential")
        }
        print("PASS signed parent receives a bounded, credential-free missing response")

        let legacy = Data(#"{"bwhApiKey":"fixture-legacy-only","xuiApiToken":"","xuiUsername":"","xuiPassword":""}"#.utf8)
        guard let seeded = try exchange(helper, operation: "seedLegacy", credentials: legacy),
              seeded.status == "ok" else { fail("fixture legacy item could not be seeded") }
        guard let beforeMigration = try exchange(helper, operation: "load"),
              beforeMigration.status == "missing" else {
            fail("ordinary reads must never fall back to the old item")
        }
        guard let migrated = try exchange(helper, operation: "migrate"),
              migrated.status == "ok", migrated.credentials == legacy else {
            fail("explicit migration must copy the old credential")
        }
        guard let preserved = try exchange(helper, operation: "legacyExists"),
              preserved.status == "ok" else { fail("migration must preserve the old item") }
        print("PASS explicit one-time migration preserves legacy and keeps reads v3-only")

        let fixture = Data(#"{"bwhApiKey":"fixture-only","xuiApiToken":"","xuiUsername":"","xuiPassword":""}"#.utf8)
        guard let saved = try exchange(helper, operation: "save", credentials: fixture),
              saved.status == "ok", saved.credentials == nil else {
            fail("signed parent must be able to save a fixture credential")
        }
        guard let loaded = try exchange(helper, operation: "load"),
              loaded.status == "ok", loaded.credentials == fixture else {
            fail("helper must read its own fixture credential across invocations")
        }
        print("PASS fixture saved and read by the same signed helper")

        let incorrectDigest = String(repeating: "0", count: 64)
        guard CredentialBridgeClient.perform("load", at: helper,
                                             expectedSHA256: incorrectDigest,
                                             timeoutSeconds: 15) == nil else {
            fail("an altered helper digest must fail before any credential exchange")
        }
        print("PASS helper bytes are pinned before credential exchange")
    }

    private static func exchange(_ helper: URL, operation: String, credentials: Data? = nil) throws -> CredentialBridgeClient.Reply? {
        CredentialBridgeClient.perform(
            operation,
            credentials: credentials,
            at: helper,
            expectedSHA256: expectedHash,
            timeoutSeconds: 15
        )
    }

    private static func fail(_ message: String) -> Never {
        print("FAIL \(message)")
        exit(1)
    }
}
