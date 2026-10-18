import Darwin
import Foundation
import Security

private let appRequirement = "identifier \"com.kun.bandwagon\" and certificate root = H\"53b7c0537a374c6d02c9dd462b9f67a784aad7f1\""
private let parentPID = getppid()

private func authorizedParent(_ pid: pid_t) -> Bool {
    guard pid > 1 else { return false }
    let attributes: [String: Any] = [kSecGuestAttributePid as String: NSNumber(value: pid)]
    var parentCode: SecCode?
    guard SecCodeCopyGuestWithAttributes(nil, attributes as CFDictionary, SecCSFlags(), &parentCode) == errSecSuccess,
          let parentCode else { return false }
    var requirement: SecRequirement?
    guard SecRequirementCreateWithString(appRequirement as CFString, SecCSFlags(), &requirement) == errSecSuccess,
          let requirement else { return false }
    return SecCodeCheckValidity(parentCode, SecCSFlags(), requirement) == errSecSuccess
}

private struct Request: Decodable {
    let version: Int
    let operation: String
    let credentials: Data?
}

private struct Response: Encodable {
    let version = 1
    let status: String
    let credentials: Data?
}

private let maxFrameBytes = 16_384

private func readExactly(_ count: Int, from handle: FileHandle) -> Data? {
    var result = Data()
    while result.count < count {
        let chunk = handle.readData(ofLength: count - result.count)
        guard !chunk.isEmpty else { return nil }
        result.append(chunk)
    }
    return result
}

private func readRequest() -> Request? {
    let input = FileHandle.standardInput
    guard let header = readExactly(4, from: input) else { return nil }
    let count = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    guard count > 0, count <= maxFrameBytes,
          let body = readExactly(Int(count), from: input),
          input.readData(ofLength: 1).isEmpty,
          let request = try? JSONDecoder().decode(Request.self, from: body),
          request.version == 1 else { return nil }
    return request
}

private func send(_ status: String, credentials: Data? = nil) {
    guard getppid() == parentPID,
          let body = try? JSONEncoder().encode(Response(status: status, credentials: credentials)),
          body.count <= maxFrameBytes else { exit(70) }
    var length = UInt32(body.count).bigEndian
    let header = withUnsafeBytes(of: &length) { Data($0) }
    FileHandle.standardOutput.write(header + body)
}

#if BRIDGE_FIXTURE
private let service = ProcessInfo.processInfo.environment["BANDWAGON_BRIDGE_TEST_SERVICE"] ?? ""
private let legacyService = service + ".legacy"
private let account = "fixture"
#else
private let service = "com.kun.bandwagon.credentials.v3"
private let legacyService = "com.kun.bandwagon.credentials.v2"
private let account = "default"
#endif

private func loginKeychain() -> SecKeychain? {
    let path = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Keychains/login.keychain-db").path
    var keychain: SecKeychain?
    let status = path.withCString { SecKeychainOpen($0, &keychain) }
    return status == errSecSuccess ? keychain : nil
}

private func loadData(from keychain: SecKeychain, service: String) -> (OSStatus, Data?) {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
        kSecMatchSearchList as String: [keychain],
        kSecAttrSynchronizable as String: false,
        kSecUseDataProtectionKeychain as String: false,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    return (status, item as? Data)
}

private func validCredentialJSON(_ data: Data) -> Bool {
    guard let values = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          Set(values.keys) == Set(["bwhApiKey", "xuiApiToken", "xuiUsername", "xuiPassword"]) else {
        return false
    }
    return values.values.allSatisfy { $0 is String }
}

private func saveData(_ data: Data, to keychain: SecKeychain, service target: String) -> Bool {
    guard validCredentialJSON(data) else { return false }
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: target,
        kSecAttrAccount as String: account,
        kSecMatchSearchList as String: [keychain],
        kSecAttrSynchronizable as String: false,
        kSecUseDataProtectionKeychain as String: false,
    ]
    let update = [kSecValueData as String: data]
    let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
    if updateStatus == errSecSuccess { return true }
    guard updateStatus == errSecItemNotFound else { return false }

    var addition = query
    addition.removeValue(forKey: kSecMatchSearchList as String)
    addition[kSecUseKeychain as String] = keychain
    addition[kSecValueData as String] = data
    return SecItemAdd(addition as CFDictionary, nil) == errSecSuccess
}

private func readStatus(_ status: OSStatus) -> String {
    switch status {
    case errSecItemNotFound: "missing"
    case errSecAuthFailed, errSecInteractionNotAllowed, errSecUserCanceled: "denied"
    default: "error"
    }
}

guard authorizedParent(parentPID), getppid() == parentPID else { exit(77) }
#if BRIDGE_FIXTURE
guard service.hasPrefix("com.kun.bandwagon.credentials.bridge-fixture.") else { exit(65) }
#endif
guard let request = readRequest(), getppid() == parentPID,
      let keychain = loginKeychain() else { exit(65) }
switch request.operation {
case "load" where request.credentials == nil:
    let (status, data) = loadData(from: keychain, service: service)
    if status == errSecSuccess, let data, validCredentialJSON(data) {
        send("ok", credentials: data)
    } else {
        send(status == errSecSuccess ? "error" : readStatus(status))
    }
case "save" where request.credentials != nil:
    send(saveData(request.credentials!, to: keychain, service: service) ? "ok" : "error")
case "migrate" where request.credentials == nil:
    let (currentStatus, currentData) = loadData(from: keychain, service: service)
    if currentStatus == errSecSuccess, let currentData, validCredentialJSON(currentData) {
        send("ok", credentials: currentData)
    } else if currentStatus == errSecItemNotFound {
        let (oldStatus, oldData) = loadData(from: keychain, service: legacyService)
        if oldStatus == errSecSuccess, let oldData, validCredentialJSON(oldData),
           saveData(oldData, to: keychain, service: service) {
            send("ok", credentials: oldData)
        } else {
            send(oldStatus == errSecSuccess ? "error" : readStatus(oldStatus))
        }
    } else {
        send(currentStatus == errSecSuccess ? "error" : readStatus(currentStatus))
    }
#if BRIDGE_FIXTURE
case "seedLegacy" where request.credentials != nil:
    send(saveData(request.credentials!, to: keychain, service: legacyService) ? "ok" : "error")
case "legacyExists" where request.credentials == nil:
    let (status, data) = loadData(from: keychain, service: legacyService)
    send(status == errSecSuccess && data != nil ? "ok" : "missing")
#endif
default:
    exit(65)
}
