import SwiftUI
import UserNotifications
import Sparkle

/// Delegate that ensures notifications are displayed even when the app is in the foreground.
/// macOS silently drops notifications for active apps unless this delegate is set.
class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }
}

@main
struct MinoApp: App {
    @State private var appState = AppState()
    @StateObject private var updaterViewModel = CheckForUpdatesViewModel()
    private let notificationDelegate = NotificationDelegate()

    init() {
        UNUserNotificationCenter.current().delegate = notificationDelegate
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .frame(minWidth: 900, minHeight: 600)
                .task {
                    await appState.loadData()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    if let id = appState.activeAgentId {
                        appState.unreadCounts[id] = 0
                    }
                    appState.updateDockBadge()
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    updaterViewModel.checkForUpdates()
                }
                .disabled(!updaterViewModel.canCheckForUpdates)
            }
            #if DEBUG
            CommandMenu("Debug") {
                Button("Load Preview Bot") {
                    appState.loadMockAgent()
                }
                .keyboardShortcut("P", modifiers: [.command, .shift])
            }
            #endif
        }

        Settings {
            SettingsView(updaterViewModel: updaterViewModel)
        }

        MenuBarExtra {
            MenuBarView()
                .environment(appState)
        } label: {
            Image(systemName: appState.menuBarIconName)
        }
    }
}
