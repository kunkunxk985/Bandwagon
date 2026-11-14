import SwiftUI

/// Chooses between the one-time connection wizard and the main shell.
struct AppRootView: View {
    @Environment(AppModel.self) private var model
    @State private var showOnboarding = false
    @State private var routingReady = false

    var body: some View {
        Group {
            if !routingReady {
                Theme.canvas
                    .ignoresSafeArea()
            } else if showOnboarding {
                ConnectionOnboardingView {
                    showOnboarding = false
                }
            } else {
                ContentView()
                    .task { await model.start() }
            }
        }
        .preferredColorScheme(windowColorScheme)
        // The window toolbar is AppKit. This is the SwiftUI signal for that bar.
        // It must stay unpaired with a toolbar background: a painted bar is a hard
        // seam across the top of the sidebar.
        .toolbarColorScheme(windowColorScheme, for: .windowToolbar)
        .background {
            WindowAppearance(mode: model.settings.appearance)
        }
        .task {
            await model.restoreSettings()
            LaunchOnboarding.completeForExistingInstallIfNeeded(settings: model.settings)
            showOnboarding = LaunchOnboarding.shouldShowWizard(settings: model.settings)
            routingReady = true
        }
    }

    /// Light and dark force that scheme. 系统 passes the live OS scheme, and
    /// `generation` changes when the Mac's theme changes so the view re-reads
    /// it. `nil` is not used: after 深色, clearing the override leaves the
    /// window dark.
    private var windowColorScheme: ColorScheme? {
        model.settings.appearance.colorScheme(systemGeneration: SystemAppearance.shared.generation)
    }
}
