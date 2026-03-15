import SwiftUI

@main
struct MinoApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 600)
                .task {
                    await appState.loadData()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    appState.clearDockBadge()
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandMenu("Debug") {
                Button("Load Preview Bot") {
                    appState.loadMockAgent()
                }
                .keyboardShortcut("P", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
        }
    }
}
