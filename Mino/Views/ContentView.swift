import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            HStack(spacing: 0) {
                ChatView()
                    .frame(maxWidth: .infinity)

                if appState.isTaskPanelVisible {
                    Divider()
                    TaskPanel()
                        .frame(width: 320)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            appState.isTaskPanelVisible.toggle()
                        }
                    } label: {
                        Image(systemName: "checklist")
                            .foregroundStyle(appState.isTaskPanelVisible ? MinoTheme.accent : .secondary)
                    }
                    .help("Toggle Tasks Panel")
                }
            }
        }
    }
}
