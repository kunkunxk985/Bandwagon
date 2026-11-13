import AppKit
import Combine
import Foundation

/// Checks GitHub for updates and replaces the installed `Bandwagon.app` in place.
@MainActor
final class AppUpdateCenter: ObservableObject {
    static let shared = AppUpdateCenter()

    enum Phase: Equatable {
        case idle
        case checking
        case available(version: String, package: URL)
        case downloading
        case installing
        case upToDate
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var fallbackUpdate: ReleaseUpdateInfo?

    private var job: Task<Void, Never>?
    private var resetTask: Task<Void, Never>?

    var isBusy: Bool {
        switch phase {
        case .checking, .downloading, .installing:
            return true
        case .idle, .available, .upToDate, .failed:
            return false
        }
    }

    func checkOrInstall() {
        guard !isBusy else { return }
        resetTask?.cancel()
        if case .available(_, let package) = phase {
            job = Task { await performInstall(package: package) }
        } else {
            job = Task { await performCheck() }
        }
    }

    func resetTransientStatusIfNeeded() {
        resetTask?.cancel()
        switch phase {
        case .upToDate, .failed:
            phase = .idle
        case .idle, .checking, .available, .downloading, .installing:
            break
        }
    }

    private func scheduleAutoReset() {
        resetTask?.cancel()
        resetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            resetTransientStatusIfNeeded()
        }
    }

    private func performCheck() async {
        phase = .checking
        fallbackUpdate = nil
        do {
            let outcome = try await ReleaseUpdateClient.checkForUpdate()
            switch outcome {
            case .upToDate:
                phase = .upToDate
                scheduleAutoReset()
            case .updateAvailable(let info):
                fallbackUpdate = info
                phase = .available(version: info.version, package: info.dmgDownloadURL)
            }
        } catch let error as ReleaseUpdateError {
            phase = .failed(error.localizedDescription)
            scheduleAutoReset()
        } catch {
            phase = .failed("暂时连不上，稍后再试")
            scheduleAutoReset()
        }
    }

    private func performInstall(package: URL) async {
        phase = .downloading
        do {
            let installed = try await AppUpdateInstaller.prepare(package: package)
            phase = .installing
            try AppUpdateInstaller.swapInAfterQuit(preparedApp: installed.app, workDirectory: installed.work)
            NSApp.terminate(nil)
        } catch {
            phase = .failed(error.localizedDescription)
            scheduleAutoReset()
        }
    }
}

enum AppUpdateInstaller {
    static let appName = "Bandwagon.app"
    static let bundleIdentifier = "com.kun.bandwagon"
    static let applicationsPath = "/Applications"

    struct Prepared {
        let app: URL
        let work: URL
    }

    enum Failure: LocalizedError {
        case notInstalledApp
        case downloadFailed
        case unreadablePackage
        case wrongApp
        case cannotReplace

        var errorDescription: String? {
            switch self {
            case .notInstalledApp:
                return "请将 Bandwagon 安装在「应用程序」文件夹后再使用应用内更新"
            case .downloadFailed:
                return "下载没有完成，稍后再试"
            case .unreadablePackage:
                return "安装包无法打开"
            case .wrongApp:
                return "安装包不是 Bandwagon"
            case .cannotReplace:
                return "没有权限替换当前的应用"
            }
        }
    }

    static func prepare(package: URL) async throws -> Prepared {
        let destination = runningAppBundleURL()
        try validateInstallLocation(destination)

        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("Bandwagon-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let archiveName = package.lastPathComponent.isEmpty ? "Bandwagon-macOS.dmg" : package.lastPathComponent
        let archive = work.appendingPathComponent(archiveName)
        let expanded = work.appendingPathComponent("expanded", isDirectory: true)
        try FileManager.default.createDirectory(at: expanded, withIntermediateDirectories: true)

        do {
            var request = URLRequest(url: package)
            ReleaseUpdateClient.applyGitHubAuth(to: &request, token: "")
            let (downloaded, response) = try await URLSession.shared.download(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200 ... 299).contains(code) else { throw Failure.downloadFailed }
            if FileManager.default.fileExists(atPath: archive.path) {
                try FileManager.default.removeItem(at: archive)
            }
            do {
                try FileManager.default.moveItem(at: downloaded, to: archive)
            } catch {
                try FileManager.default.copyItem(at: downloaded, to: archive)
            }
            let stagedApp = try expandReleaseArchive(at: archive, into: expanded, work: work)
            guard bundleIdentifier(of: stagedApp) == Self.bundleIdentifier else { throw Failure.wrongApp }
            try? run("/usr/bin/xattr", ["-cr", stagedApp.path])
            return Prepared(app: stagedApp, work: work)
        } catch let failure as Failure {
            try? FileManager.default.removeItem(at: work)
            throw failure
        } catch {
            try? FileManager.default.removeItem(at: work)
            throw Failure.downloadFailed
        }
    }

    static func swapInAfterQuit(preparedApp: URL, workDirectory: URL) throws {
        let destination = runningAppBundleURL()
        try validateInstallLocation(destination)
        let parent = destination.deletingLastPathComponent()
        let staging = parent.appendingPathComponent("Bandwagon.app.update-staging", isDirectory: true)
        let backup = parent.appendingPathComponent("Bandwagon.app.pre-update-backup", isDirectory: true)
        let script = workDirectory.appendingPathComponent("install.sh")
        let body = """
        #!/bin/bash
        set -euo pipefail
        DEST=\(shellQuote(destination.path))
        NEW=\(shellQuote(preparedApp.path))
        STAGING=\(shellQuote(staging.path))
        BACKUP=\(shellQuote(backup.path))
        WORK=\(shellQuote(workDirectory.path))

        restore_backup() {
          rm -rf "$DEST"
          if [[ -d "$BACKUP" ]]; then
            ditto "$BACKUP" "$DEST"
          fi
        }

        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do
          sleep 0.2
        done

        rm -rf "$STAGING"
        if ! ditto "$NEW" "$STAGING"; then
          exit 1
        fi
        xattr -cr "$STAGING" || true

        rm -rf "$BACKUP"
        if [[ -d "$DEST" ]]; then
          ditto "$DEST" "$BACKUP"
        fi

        rm -rf "$DEST"
        if ! mv "$STAGING" "$DEST"; then
          restore_backup
          exit 1
        fi

        open "$DEST" || true
        rm -rf "$BACKUP" "$WORK"
        """
        try body.write(to: script, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    static func isRunningFromApplications(_ bundleURL: URL) -> Bool {
        let destination = bundleURL.resolvingSymlinksInPath()
        guard destination.lastPathComponent == appName else { return false }
        return destination.deletingLastPathComponent().path == applicationsPath
    }

    static func shellQuote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func runningAppBundleURL() -> URL {
        Bundle.main.bundleURL.resolvingSymlinksInPath()
    }

    private static func validateInstallLocation(_ destination: URL) throws {
        guard destination.lastPathComponent == appName else { throw Failure.notInstalledApp }
        guard destination.deletingLastPathComponent().path == applicationsPath else {
            throw Failure.notInstalledApp
        }
        guard FileManager.default.isWritableFile(atPath: destination.deletingLastPathComponent().path) else {
            throw Failure.cannotReplace
        }
    }

    private static func expandReleaseArchive(at archive: URL, into expanded: URL, work: URL) throws -> URL {
        let ext = archive.pathExtension.lowercased()
        guard ext == "dmg" else { throw Failure.unreadablePackage }

        let mount = work.appendingPathComponent("mount", isDirectory: true)
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        try run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-mountpoint", mount.path, archive.path])
        defer {
            _ = try? run("/usr/bin/hdiutil", ["detach", mount.path, "-quiet"])
        }
        guard let mounted = findApp(in: mount) else { throw Failure.unreadablePackage }
        let staged = expanded.appendingPathComponent(appName, isDirectory: true)
        if FileManager.default.fileExists(atPath: staged.path) {
            try FileManager.default.removeItem(at: staged)
        }
        try run("/usr/bin/ditto", [mounted.path, staged.path])
        return staged
    }

    private static func findApp(in root: URL) -> URL? {
        let fileManager = FileManager.default
        let direct = root.appendingPathComponent(appName)
        if fileManager.fileExists(atPath: direct.path) { return direct }
        guard let children = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        ) else { return nil }
        for child in children {
            if child.lastPathComponent == appName { return child }
            let nested = child.appendingPathComponent(appName)
            if fileManager.fileExists(atPath: nested.path) { return nested }
        }
        return nil
    }

    private static func bundleIdentifier(of app: URL) -> String? {
        let info = app.appendingPathComponent("Contents/Info.plist")
        guard let dictionary = NSDictionary(contentsOf: info) else { return nil }
        return dictionary["CFBundleIdentifier"] as? String
    }

    private static func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure.unreadablePackage }
    }
}
