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
///
/// The sidebar toggle and the refresh capsule are AppKit toolbar items. They
/// keep drawing light glass after `NSApp` and the window have the right
/// appearance, because each capsule has its own. Pinning that same appearance
/// onto the capsule views follows the page without painting a titlebar bar.
struct WindowAppearance: NSViewRepresentable {
    var mode: AppearanceMode

    func makeNSView(context: Context) -> NSView {
        let view = AppearanceAnchor()
        view.mode = mode
        WindowAppearance.apply(mode, deferIfNoWindow: true)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let anchor = nsView as? AppearanceAnchor
        anchor?.mode = mode
        WindowAppearance.apply(mode, deferIfNoWindow: nsView.window == nil)
        anchor?.push()
    }

    private static var isApplying = false
    private static var syncingChrome = false
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
        for window in NSApp.windows {
            if window.appearance?.name != token {
                window.appearance = appearance
            }
            syncChrome(AppearanceBridge.shared.mode, window: window)
        }
    }

    /// Toolbar capsules ignore the window appearance. Re-apply it to the item
    /// views and the glass around them, and leave the titlebar container alone
    /// so it does not become a strip across the sidebar.
    fileprivate static func syncChrome(_ mode: AppearanceMode, window: NSWindow) {
        guard ProcessInfo.processInfo.environment["BANDWAGON_SNAPSHOT_APPEARANCE"] == nil else { return }
        guard window.toolbar != nil else { return }
        guard !syncingChrome else { return }
        syncingChrome = true
        defer { syncingChrome = false }

        let appearance = capsuleAppearance(for: mode)
        let content = window.contentView
        let theme = content?.superview
        for item in window.toolbar?.items ?? [] {
            guard let itemView = item.view else { continue }
            pinItemChain(appearance, from: itemView, content: content, theme: theme)
        }
        if let theme, let content {
            pinToolbarViews(appearance, in: theme, window: window, skipping: content)
        }
    }

    fileprivate static func pinItemChain(_ mode: AppearanceMode, from start: NSView) {
        guard let window = start.window else { return }
        syncChrome(mode, window: window)
        let appearance = capsuleAppearance(for: mode)
        pinItemChain(
            appearance,
            from: start,
            content: window.contentView,
            theme: window.contentView?.superview
        )
    }

    /// `nil` from `nsAppearance` means follow the system, but a capsule with no
    /// appearance of its own stays on the light glass. Read the OS choice on
    /// every sync so a stored value cannot freeze it.
    private static func capsuleAppearance(for mode: AppearanceMode) -> NSAppearance? {
        if let pinned = mode.nsAppearance { return pinned }
        let dark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        return NSAppearance(named: dark ? .darkAqua : .aqua)
    }

    private static func pinItemChain(
        _ appearance: NSAppearance?,
        from start: NSView,
        content: NSView?,
        theme: NSView?
    ) {
        var current: NSView? = start
        var hops = 0
        while let view = current, hops < 5 {
            if view === content || view === theme { break }
            let name = String(describing: type(of: view))
            if name.contains("Titlebar") || name.contains("ThemeFrame") { break }
            // Stop at the full-width toolbar view. The capsule is the item
            // viewer below it; pinning the bar itself is the seam we removed.
            if name.contains("Toolbar") && !name.contains("Item") && !name.contains("Glass") && !name.contains("Button") {
                break
            }
            assign(appearance, to: view)
            current = view.superview
            hops += 1
        }
    }

    private static func pinToolbarViews(
        _ appearance: NSAppearance?,
        in view: NSView,
        window: NSWindow,
        skipping content: NSView
    ) {
        if view !== content, shouldPin(view, window: window) {
            assign(appearance, to: view)
            // The glass plate is often the button's parent, under a class name
            // that is neither Glass nor ToolbarItem. One level only: the toolbar
            // view above that is full width and must stay untouched.
            if let parent = view.superview, parent !== content, canPinParent(parent) {
                assign(appearance, to: parent)
            }
        }
        guard view !== content else { return }
        for subview in view.subviews where subview !== content {
            pinToolbarViews(appearance, in: subview, window: window, skipping: content)
        }
    }

    /// Glass and toolbar item views, plus toolbar buttons that are not the
    /// traffic lights. The titlebar container is skipped so the sidebar still
    /// runs under the window buttons.
    private static func shouldPin(_ view: NSView, window: NSWindow) -> Bool {
        let name = String(describing: type(of: view))
        if name.contains("Titlebar") || name.contains("ThemeFrame") { return false }
        if name.contains("Glass") || name.contains("ToolbarItem") { return true }
        guard name.contains("Button") else { return false }
        return !isStandardWindowButton(view, window: window)
    }

    private static func canPinParent(_ view: NSView) -> Bool {
        let name = String(describing: type(of: view))
        if name.contains("Titlebar") || name.contains("ThemeFrame") { return false }
        // `NSToolbarView` spans the window. Item viewers and glass plates do not.
        if name.contains("Toolbar") && !name.contains("Item") && !name.contains("Glass") {
            return false
        }
        return true
    }

    private static func isStandardWindowButton(_ view: NSView, window: NSWindow) -> Bool {
        let kinds: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        return kinds.contains { window.standardWindowButton($0) === view }
    }

    private static func assign(_ appearance: NSAppearance?, to view: NSView) {
        guard view.appearance?.name != appearance?.name else { return }
        view.appearance = appearance
    }
}

/// Sits inside the refresh toolbar item and pins the capsule around it. The
/// sidebar toggle is pinned from the same window walk.
struct ToolbarItemAppearance: NSViewRepresentable {
    var mode: AppearanceMode

    func makeNSView(context: Context) -> NSView {
        let view = AppearanceAnchor()
        view.pinsItemCapsule = true
        view.mode = mode
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let anchor = nsView as? AppearanceAnchor else { return }
        anchor.pinsItemCapsule = true
        anchor.mode = mode
        anchor.push()
    }
}

private final class AppearanceAnchor: NSView {
    var mode: AppearanceMode = .system
    var pinsItemCapsule = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        push()
        // The toolbar item viewer is installed after this view joins the window.
        DispatchQueue.main.async { [weak self] in self?.push() }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        pinsItemCapsule ? nil : super.hitTest(point)
    }

    fileprivate func push() {
        guard let window else { return }
        if pinsItemCapsule {
            WindowAppearance.pinItemChain(mode, from: self)
        } else {
            WindowAppearance.syncChrome(mode, window: window)
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
