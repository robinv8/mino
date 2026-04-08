import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ForEach(appState.agents) { agent in
            Button {
                appState.selectAgent(agent.id)
                activateApp()
            } label: {
                HStack {
                    statusDot(for: agent)
                    Text(agent.name)
                    Spacer()
                    let count = appState.unreadCounts[agent.id] ?? 0
                    if count > 0 {
                        Text("\(count)")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.red)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }
            }
        }

        if !appState.agents.isEmpty {
            Divider()
        }

        Button("Open Mino") {
            activateApp()
        }
        .keyboardShortcut("o")

        Divider()

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func statusDot(for agent: Agent) -> some View {
        let isGenerating = appState.generatingAgentIds.contains(agent.id)
        let color: Color = switch agent.status {
        case .connected:
            isGenerating ? .orange : .green
        case .connecting, .reconnecting:
            .yellow
        case .disconnected:
            .gray
        }
        return Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }

    private func activateApp() {
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
