import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) var appState
    @State private var showingAddAgent = false

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            if appState.agents.isEmpty {
                WelcomeView(showingAddAgent: $showingAddAgent)
            } else {
                HStack(spacing: 0) {
                    ChatView()
                        .frame(maxWidth: .infinity)

                    if appState.isTaskPanelVisible {
                        Divider()
                    }
                    TaskPanel()
                        .frame(width: appState.isTaskPanelVisible ? 320 : 0)
                        .clipped()
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                appState.isTaskPanelVisible.toggle()
                            }
                        } label: {
                            Image(systemName: "checklist")
                                .foregroundStyle(appState.isTaskPanelVisible ? Color.accentColor : .secondary)
                        }
                        .help("Toggle Tasks Panel")
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddAgent) {
            AddAgentView()
                .environment(appState)
        }
        .overlay(alignment: .top) {
            if let error = appState.lastError {
                ErrorToast(error: error) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        appState.lastError = nil
                    }
                }
                .padding(.top, 8)
                .onAppear {
                    // Auto-dismiss after 5 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if appState.lastError == error {
                                appState.lastError = nil
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Welcome View

private struct WelcomeView: View {
    @Binding var showingAddAgent: Bool

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            VStack(spacing: 8) {
                Text("Welcome to Mino")
                    .font(.system(size: 20, weight: .medium))

                Text("Your AI Agent companion for macOS")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                Text("Get started by adding a Claude Code project.")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)

                Button {
                    showingAddAgent = true
                } label: {
                    Text("Add Claude Code Project")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
    }
}
