import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @State private var showAddAgent = false
    @State private var editingAgent: Agent?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Mino")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.primary.opacity(0.8))
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

            List(appState.agents, selection: $appState.activeAgentId) { agent in
                AgentRow(
                    agent: agent,
                    lastMessage: lastMessage(for: agent.id),
                    unreadCount: appState.unreadCounts[agent.id] ?? 0
                )
                .tag(agent.id)
                .contextMenu {
                    Button("Edit") {
                        editingAgent = agent
                    }
                    Divider()
                    Button("Delete", role: .destructive) {
                        appState.removeAgent(agent)
                    }
                }
            }
            .listStyle(.sidebar)
            .onChange(of: appState.activeAgentId) {
                if let id = appState.activeAgentId {
                    appState.selectAgent(id)
                }
            }

            Divider()

            Button {
                showAddAgent = true
            } label: {
                Label("Add Agent", systemImage: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showAddAgent) {
            AddAgentView()
                .environmentObject(appState)
        }
        .sheet(item: $editingAgent) { agent in
            AddAgentView(editingAgent: agent)
                .environmentObject(appState)
        }
    }

    private func lastMessage(for agentId: String) -> String? {
        guard let segments = appState.conversations[agentId],
              let lastMsg = segments.last?.messages.last(where: { $0.type == .text }) else {
            return nil
        }
        return lastMsg.content
    }
}

struct AgentRow: View {
    let agent: Agent
    let lastMessage: String?
    let unreadCount: Int

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(MinoTheme.avatarGradient(for: agent.name))
                    .frame(width: 36, height: 36)
                Text(String(agent.name.prefix(1)))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(agent.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Spacer()
                    if unreadCount > 0 {
                        Text("\(unreadCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(MinoTheme.accent)
                            .clipShape(Capsule())
                    }
                }

                if let preview = lastMessage {
                    Text(preview)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                } else {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 5, height: 5)
                        Text(statusText)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.vertical, 3)
    }

    private var statusColor: Color {
        switch agent.status {
        case .connected: .green
        case .disconnected: .gray
        case .connecting: .orange
        case .reconnecting: .orange
        }
    }

    private var statusText: String {
        switch agent.status {
        case .connected: "Connected"
        case .disconnected: "Disconnected"
        case .connecting: "Connecting..."
        case .reconnecting(let attempt): "Reconnecting (\(attempt))..."
        }
    }
}
