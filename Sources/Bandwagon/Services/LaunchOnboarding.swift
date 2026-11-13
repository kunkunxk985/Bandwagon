import Foundation

/// Whether the one-time full-screen connection wizard has finished (v1 onboarding).
enum LaunchOnboarding {
    static let userDefaultsKey = "BandwagonHasLaunchedBefore"

    static var hasLaunchedBefore: Bool {
        UserDefaults.standard.bool(forKey: userDefaultsKey)
    }

    static func markCompleted() {
        UserDefaults.standard.set(true, forKey: userDefaultsKey)
    }

    /// Show the wizard only on a genuinely fresh install with no prior Bandwagon connection.
    static func shouldShowWizard(settings: AppSettings) -> Bool {
        guard !hasLaunchedBefore else { return false }
        if settings.bwhReady { return false }
        if SettingsStore.hasPersistedConnectionHints() { return false }
        return true
    }

    /// Upgraders who already configured the app should not see the wizard once.
    static func completeForExistingInstallIfNeeded(settings: AppSettings) {
        guard !hasLaunchedBefore else { return }
        if settings.bwhReady || SettingsStore.hasPersistedConnectionHints() {
            markCompleted()
        }
    }
}
