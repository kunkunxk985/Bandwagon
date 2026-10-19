import SwiftUI

/// The Bandwagon refresh-failure banner, shared by Overview and VPS.
///
/// Both pages show the same failure the same way. They used to carry a byte-identical
/// private copy each, which is how two pages end up disagreeing about the same problem
/// the moment one of them is touched.
struct BandwagonFailureBanner: View {
    let error: String
    @Binding var selectedTab: ContentView.Tab
    @Environment(AppModel.self) private var model

    var body: some View {
        let failure = ServiceFailure(
            service: "Bandwagon",
            error: error,
            needsSettings: model.bwhNeedsSettings
        )
        StatusBanner(
            title: failure.staleTitle,
            message: failure.message,
            icon: failure.icon,
            tint: Theme.warning,
            actionTitle: failure.actionTitle,
            action: {
                failure.resolve(
                    goToSettings: { selectedTab = .settings },
                    retry: { await model.load() }
                )
            }
        )
    }
}
