import CryptoKit
import Darwin
import Foundation
import Security

/// One process and one bounded request per credential operation. The helper is
/// outside the replaceable .app; its release digest is pinned by the caller.
enum CredentialBridgeClient {
    struct Reply: Decodable {
        let version: Int
        let status: String
        let credentials: Data?
    }

    private struct Request: Encodable {
        let version = 1
        let operation: String
        let credentials: Data?
    }

    private static let requirementText = #"identifier "com.kun.bandwagon.credential-bridge" and certificate root = H"53b7c0537a374c6d02c9dd462b9f67a784aad7f1""#
    private static let maxFrameBytes = 16_384

    static func perform(
        _ operation: String,
        credentials: Data? = nil,
        at url: URL,
        expectedSHA256: String,
        timeoutSeconds: TimeInterval
    ) -> Reply? {
        guard let expectedCodeHash = verifiedFile(at: url, expectedSHA256: expectedSHA256),
              let body = try? JSONEncoder().encode(Request(operation: operation, credentials: credentials)),
              body.count <= maxFrameBytes else { return nil }

        let process = Process()
        process.executableURL = url
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        defer {
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
        }

        // Do not send credentials or read a response before checking the
        // identity of the *running* child, not just the earlier file path.
        guard runningChild(process.processIdentifier, matches: expectedCodeHash) else { return nil }
        var length = UInt32(body.count).bigEndian
        let header = withUnsafeBytes(of: &length) { Data($0) }
        do {
            try input.fileHandleForWriting.write(contentsOf: header + body)
            try input.fileHandleForWriting.close()
        } catch { return nil }

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        let fd = output.fileHandleForReading.fileDescriptor
        guard let responseHeader = readExactly(4, fd: fd, before: deadline) else { return nil }
        let responseLength = responseHeader.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard responseLength > 0, responseLength <= maxFrameBytes,
              let responseBody = readExactly(Int(responseLength), fd: fd, before: deadline),
              readEOF(fd: fd, before: deadline),
              let reply = try? JSONDecoder().decode(Reply.self, from: responseBody),
              reply.version == 1,
              ["ok", "missing", "denied", "error"].contains(reply.status),
              (reply.status == "ok" || reply.credentials == nil) else { return nil }
        return reply
    }

    private static func verifiedFile(at url: URL, expectedSHA256: String) -> Data? {
        guard url.isFileURL, !url.path.contains("/../"),
              expectedSHA256.count == 64,
              securePath(url.deletingLastPathComponent(), directory: true),
              securePath(url, directory: false),
              let bytes = try? Data(contentsOf: url),
              SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == expectedSHA256.lowercased(),
              let requirement = requirement() else { return nil }

        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(), &code) == errSecSuccess,
              let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), requirement) == errSecSuccess else {
            return nil
        }
        return uniqueCodeHash(code)
    }

    private static func securePath(_ url: URL, directory: Bool) -> Bool {
        var info = stat()
        guard url.path.withCString({ lstat($0, &info) }) == 0,
              info.st_uid == getuid(),
              (info.st_mode & mode_t(S_IFMT)) == mode_t(directory ? S_IFDIR : S_IFREG),
              info.st_mode & 0o022 == 0 else { return false }
        return !directory || info.st_mode & 0o777 == 0o700
    }

    private static func requirement() -> SecRequirement? {
        var rule: SecRequirement?
        guard SecRequirementCreateWithString(requirementText as CFString, SecCSFlags(), &rule) == errSecSuccess else {
            return nil
        }
        return rule
    }

    private static func uniqueCodeHash(_ code: SecStaticCode) -> Data? {
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let values = info as? [String: Any] else { return nil }
        return values[kSecCodeInfoUnique as String] as? Data
    }

    private static func runningChild(_ pid: pid_t, matches expectedHash: Data) -> Bool {
        guard pid > 1, let rule = requirement() else { return false }
        let attributes = [kSecGuestAttributePid as String: NSNumber(value: pid)] as CFDictionary
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, SecCSFlags(), &code) == errSecSuccess,
              let code,
              SecCodeCheckValidity(code, SecCSFlags(), rule) == errSecSuccess else { return false }
        var runningStaticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, SecCSFlags(), &runningStaticCode) == errSecSuccess,
              let runningStaticCode,
              uniqueCodeHash(runningStaticCode) == expectedHash else { return false }
        return true
    }

    private static func pollReadable(_ fd: Int32, before deadline: Date) -> Bool {
        let milliseconds = deadline.timeIntervalSinceNow * 1_000
        guard milliseconds > 0 else { return false }
        var descriptor = pollfd(fd: fd, events: Int16(POLLIN | POLLHUP), revents: 0)
        while true {
            let ready = Darwin.poll(&descriptor, 1, Int32(min(milliseconds, Double(Int32.max))))
            if ready > 0 { return true }
            if ready < 0 && errno == EINTR { continue }
            return false
        }
    }

    private static func readExactly(_ count: Int, fd: Int32, before deadline: Date) -> Data? {
        var result = Data()
        while result.count < count {
            guard pollReadable(fd, before: deadline) else { return nil }
            var chunk = [UInt8](repeating: 0, count: min(count - result.count, 4_096))
            let readCount = Darwin.read(fd, &chunk, chunk.count)
            if readCount < 0 && errno == EINTR { continue }
            guard readCount > 0 else { return nil }
            result.append(contentsOf: chunk.prefix(readCount))
        }
        return result
    }

    private static func readEOF(fd: Int32, before deadline: Date) -> Bool {
        guard pollReadable(fd, before: deadline) else { return false }
        var byte: UInt8 = 0
        return Darwin.read(fd, &byte, 1) == 0
    }
}
