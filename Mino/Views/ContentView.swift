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

                if appState.isResourcePanelVisible {
                    Divider()
                    ResourcePanel()
                        .frame(width: 260)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            appState.isResourcePanelVisible.toggle()
                        }
                    } label: {
                        Image(systemName: "sidebar.right")
                            .foregroundStyle(appState.isResourcePanelVisible ? MinoTheme.accent : .secondary)
                    }
                    .help("Toggle Resources Panel")
                }
            }
        }
    }
}
