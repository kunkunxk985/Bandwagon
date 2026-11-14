import AppKit
import SwiftUI

/// Thin wrapper over `NSVisualEffectView` for the sidebar's material backdrop.
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode = .withinWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

/// Reaches up to the hosting window once it exists and switches it to a transparent
/// titlebar with a full-size content view, so the sidebar can run to the top edge.
struct WindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            // Each page draws its own large title, so the toolbar keeps only the
            // freshness label and refresh. The title still names the window in
            // the Window menu and Mission Control.
            window.titleVisibility = .hidden
            if !window.styleMask.contains(.fullSizeContentView) {
                window.styleMask.insert(.fullSizeContentView)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension AppearanceMode {
    /// `nil` means "do not override". SwiftUI then follows the system color
    /// scheme, including a later change in System Settings.
    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }

    /// `nil` clears `NSApp.appearance` so AppKit keeps tracking the OS.
    /// Resolving the current effective appearance here would freeze it.
    var nsAppearance: NSAppearance? {
        switch self {
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        case .system: return nil
        }
    }
}

/// Pushes the saved appearance onto the process and every window. A system
/// choice installs no appearance, and a system-theme notification installs it
/// again so a concrete value cannot get stuck on the window.
struct WindowAppearance: NSViewRepresentable {
    var mode: AppearanceMode

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        WindowAppearance.apply(mode, deferIfNoWindow: true)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        WindowAppearance.apply(mode, deferIfNoWindow: nsView.window == nil)
    }

    private static var isApplying = false
    private static var generation = 0
    private static var applied: AppearanceMode?

    static func apply(_ mode: AppearanceMode, deferIfNoWindow: Bool, refreshWindows: Bool = false) {
        AppearanceBridge.shared.follow(mode)
        guard ProcessInfo.processInfo.environment["BANDWAGON_SNAPSHOT_APPEARANCE"] == nil else { return }
        // Setting the appearance can deliver the theme notification inline.
        guard !isApplying else { return }
        isApplying = true
        defer { isApplying = false }
        let modeChanged = applied != mode
        guard modeChanged || refreshWindows || deferIfNoWindow else { return }
        if modeChanged || refreshWindows {
            applied = mode
            generation &+= 1
            let appearance = mode.nsAppearance
            NSApp.appearance = appearance
            assignWindows(appearance)
        }
        guard deferIfNoWindow else { return }
        let ticket = generation
        Task { @MainActor in
            guard WindowAppearance.generation == ticket else { return }
            guard ProcessInfo.processInfo.environment["BANDWAGON_SNAPSHOT_APPEARANCE"] == nil else { return }
            WindowAppearance.assignWindows(mode.nsAppearance)
        }
    }

    private static func assignWindows(_ appearance: NSAppearance?) {
        let token = appearance?.name
        for window in NSApp.windows where window.appearance?.name != token {
            window.appearance = appearance
        }
    }
}

@MainActor
private final class AppearanceBridge: NSObject {
    static let shared = AppearanceBridge()
    var mode: AppearanceMode = .system
    private var observing = false

    func follow(_ mode: AppearanceMode) {
        self.mode = mode
        guard !observing else { return }
        observing = true
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(systemThemeChanged(_:)),
            name: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )
    }

    /// Posted off the main thread. Hop before touching AppKit.
    @objc nonisolated private func systemThemeChanged(_ notification: Notification) {
        Task { @MainActor in
            WindowAppearance.apply(
                AppearanceBridge.shared.mode,
                deferIfNoWindow: false,
                refreshWindows: true
            )
        }
    }
}
