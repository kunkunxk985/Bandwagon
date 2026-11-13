import SwiftUI

@main
struct BandwagonApp: App {
    static let mainWindowID = "main"

    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(MenuBarPreference.key) private var showMenuBar = true

    var body: some Scene {
        WindowGroup(id: Self.mainWindowID) {
            AppRootView()
                .environment(model)
                .frame(minWidth: 1040, minHeight: 680)
                .background(WindowChrome())
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        // Returning to the window is exactly when stale numbers are
                        // most misleading, so top up if the snapshot has aged out.
                        Task { await model.refreshIfStale() }
                        model.startAutoRefresh()
                    case .background:
                        // The menu bar item keeps showing the numbers after the
                        // window is gone, so it keeps polling; without it, rest.
                        if !showMenuBar {
                            model.stopAutoRefresh()
                        }
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

        MenuBarExtra(isInserted: $showMenuBar) {
            MenuBarPanel()
                .environment(model)
        } label: {
            MenuBarLabel()
                .environment(model)
        }
        .menuBarExtraStyle(.window)
    }
}
