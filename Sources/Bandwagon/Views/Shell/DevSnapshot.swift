import AppKit
import SwiftUI

/// Development aid: renders every page of the window to PNG so UI changes can be
/// checked without Screen Recording permission (an app may always draw its own
/// views). Inert unless `BANDWAGON_SNAPSHOT_DIR` is set at launch:
///
///     open --env BANDWAGON_SNAPSHOT_DIR=/tmp/shots ~/Desktop/Bandwagon.app
///
/// Optionally `BANDWAGON_SNAPSHOT_APPEARANCE=dark` renders in dark mode.
@MainActor
enum DevSnapshot {
    static let directory: URL? = ProcessInfo.processInfo.environment["BANDWAGON_SNAPSHOT_DIR"]
        .map { URL(fileURLWithPath: $0, isDirectory: true) }

    static func run(model: AppModel, select: (ContentView.Tab) -> Void) async {
        guard let directory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if ProcessInfo.processInfo.environment["BANDWAGON_SNAPSHOT_APPEARANCE"] == "dark" {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        // Optional wide-window check: BANDWAGON_SNAPSHOT_WIDTH=1800 and so on.
        if let width = ProcessInfo.processInfo.environment["BANDWAGON_SNAPSHOT_WIDTH"].flatMap(Double.init),
           let window = mainWindow {
            window.setContentSize(NSSize(width: width, height: window.contentLayoutRect.height))
        }
        // Wait for the first refresh to settle so pages show data, not spinners.
        for _ in 0..<120 where model.overview.fetchedAt == nil && model.overview.bwh?.error == nil {
            try? await Task.sleep(for: .milliseconds(250))
        }
        while model.loading { try? await Task.sleep(for: .milliseconds(250)) }

        for tab in ContentView.Tab.allCases {
            select(tab)
            try? await Task.sleep(for: .milliseconds(900))
            capture(to: directory.appendingPathComponent("\(tab.rawValue).png"))
            // Long pages get a second shot scrolled to the end.
            if scrollToBottom() {
                try? await Task.sleep(for: .milliseconds(500))
                capture(to: directory.appendingPathComponent("\(tab.rawValue)-bottom.png"))
            }
        }
        // The menu bar panel is its own window that only exists while open, so
        // render the view directly.
        let dark = ProcessInfo.processInfo.environment["BANDWAGON_SNAPSHOT_APPEARANCE"] == "dark"
        let renderer = ImageRenderer(content: MenuBarPanel()
            .environment(model)
            .environment(\.colorScheme, dark ? .dark : .light))
        renderer.scale = 2
        if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff) {
            try? rep.representation(using: .png, properties: [:])?
                .write(to: directory.appendingPathComponent("menubar.png"))
        }

        // The detail sheet for the busiest client, once its subscription link has
        // had time to load.
        if let client = model.overview.xui?.clients?.first {
            select(.clients)
            model.inspectedClientID = client.id
            try? await Task.sleep(for: .seconds(4))
            if let sheet = NSApp.windows.first(where: { $0.isSheet && $0.isVisible }) {
                capture(window: sheet, to: directory.appendingPathComponent("client-sheet.png"))
            }
            model.inspectedClientID = nil
        }
        NSApp.terminate(nil)
    }

    /// The document window, skipping the menu bar item's status window and sheets.
    private static var mainWindow: NSWindow? {
        NSApp.windows.first { $0.isVisible && !$0.isSheet && $0.contentView != nil && $0.frame.width > 600 }
    }

    private static func scrollToBottom() -> Bool {
        guard let root = mainWindow?.contentView else { return false }
        var best: NSScrollView?
        var stack: [NSView] = [root]
        while let view = stack.popLast() {
            if let scroll = view as? NSScrollView, let document = scroll.documentView,
               document.frame.height > scroll.contentView.bounds.height + 1,
               document.frame.height > (best?.documentView?.frame.height ?? 0) {
                best = scroll
            }
            stack.append(contentsOf: view.subviews)
        }
        guard let scroll = best, let document = scroll.documentView else { return false }
        let maxY = document.isFlipped ? document.frame.height - scroll.contentView.bounds.height : 0
        scroll.contentView.scroll(to: NSPoint(x: 0, y: maxY))
        scroll.reflectScrolledClipView(scroll.contentView)
        return true
    }

    private static func capture(to url: URL) {
        guard let window = mainWindow else {
            NSLog("DevSnapshot: no window to capture (\(NSApp.windows.count) windows)")
            return
        }
        capture(window: window, to: url)
    }

    private static func capture(window: NSWindow, to url: URL) {
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            NSLog("DevSnapshot: no window to capture (\(NSApp.windows.count) windows)")
            return
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        do {
            try rep.representation(using: .png, properties: [:])?.write(to: url)
        } catch {
            NSLog("DevSnapshot: write failed: \(error)")
        }
    }
}
