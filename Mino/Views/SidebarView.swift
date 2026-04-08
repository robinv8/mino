import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) var appState
    @State private var showAddAgent = false
    @State private var editingAgent: Agent?
    @State private var isAddHovered = false

    var body: some View {
        @Bindable var bindableState = appState
        VStack(alignment: .leading, spacing: 0) {
            List(appState.agents, selection: $bindableState.activeAgentId) { agent in
                AgentRow(
                    agent: agent,
                    lastMessage: lastMessage(for: agent.id),
                    unreadCount: appState.unreadCounts[agent.id] ?? 0,
                    isWorking: appState.generatingAgentIds.contains(agent.id)
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
                    .foregroundStyle(isAddHovered ? .primary : .tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .onHover { isAddHovered = $0 }
        }
        .background(.ultraThinMaterial)
        .sheet(isPresented: $showAddAgent) {
            AddAgentView()
                .environment(appState)
        }
        .sheet(item: $editingAgent) { agent in
            AddAgentView(editingAgent: agent)
                .environment(appState)
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
    let isWorking: Bool

    var body: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(agent.type == .claudeCode
                              ? Color.secondary.opacity(0.3)
                              : MinoTheme.avatarColor(for: agent.name).opacity(0.3))
                        .frame(width: 32, height: 32)
                    if agent.type == .claudeCode {
                        Image(systemName: "terminal")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(String(agent.name.prefix(1)))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                    }
                }

                // Working indicator
                if isWorking {
                    ProgressView()
                        .controlSize(.mini)
                        .background(
                            Circle()
                                .fill(Color(.windowBackgroundColor))
                                .frame(width: 14, height: 14)
                        )
                        .offset(x: 3, y: 3)
                } else if lastMessage != nil {
                    Circle()
                        .fill(.green)
                        .frame(width: 6, height: 6)
                        .background(
                            Circle()
                                .fill(Color(.windowBackgroundColor))
                                .frame(width: 10, height: 10)
                        )
                        .offset(x: 2, y: 2)
                }
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
                            .background(Color.primary)
                            .clipShape(Capsule())
                    }
                }

                if isWorking {
                    Text("Working...")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                } else if let preview = lastMessage {
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
        .padding(.vertical, 2)
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
