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
        .preferredColorScheme(model.settings.appearance.colorScheme)
        // The window toolbar is AppKit. This is the SwiftUI signal for that bar.
        // It must stay unpaired with a toolbar background: a painted bar is a hard
        // seam across the top of the sidebar.
        .toolbarColorScheme(model.settings.appearance.colorScheme, for: .windowToolbar)
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
}
