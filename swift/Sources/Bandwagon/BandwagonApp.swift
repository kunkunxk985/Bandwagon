import SwiftUI

@main
struct BandwagonApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .frame(minWidth: 1040, minHeight: 680)
                .background(WindowChrome())
                .task {
                    await model.restoreSettings()
                    await model.load()
                    model.startAutoRefresh()
                }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        // Returning to the window is exactly when stale numbers are
                        // most misleading, so top up if the snapshot has aged out.
                        Task { await model.refreshIfStale() }
                        model.startAutoRefresh()
                    case .background:
                        model.stopAutoRefresh()
                    default:
                        break
                    }
                }
        }
        .defaultSize(width: 1240, height: 800)
        .windowResizability(.contentMinSize)
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .toolbar) {
                Button("刷新") { Task { await model.load() } }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(model.loading)
            }
        }
    }
}
