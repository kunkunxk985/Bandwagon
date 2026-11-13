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
        .task {
            await model.restoreSettings()
            LaunchOnboarding.completeForExistingInstallIfNeeded(settings: model.settings)
            showOnboarding = LaunchOnboarding.shouldShowWizard(settings: model.settings)
            routingReady = true
        }
    }
}
