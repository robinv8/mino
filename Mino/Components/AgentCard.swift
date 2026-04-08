import SwiftUI

struct AgentCard: View {
    @Environment(AppState.self) var appState
    let agent: Agent
    @State private var isHovered = false
    @State private var showRedirectPrompt = false
    @State private var redirectText = ""

    private var status: AgentActivityStatus {
        appState.activityStatus(for: agent.id)
    }

    private var lastMessage: String {
        guard let segments = appState.conversations[agent.id],
              let last = segments.last?.messages.last else { return "" }
        let text = last.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(text.prefix(80))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: avatar + name + status dot
            HStack(spacing: 8) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(MinoTheme.avatarColor(for: agent.name))
                        .frame(width: 28, height: 28)
                    Text(String(agent.name.prefix(1)).uppercased())
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    statusLabel
                }

                Spacer()

                statusDot
            }

            // Last message preview
            if !lastMessage.isEmpty {
                Text(lastMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }

            // Footer: file changes + stats
            HStack(spacing: 12) {
                let files = appState.filesChanged(for: agent.id)
                if files > 0 {
                    Label("\(files) files", systemImage: "doc.text")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                let tools = appState.taskData[agent.id]?.completedCount ?? 0
                if tools > 0 {
                    Label("\(tools) tasks", systemImage: "checkmark.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: MinoTheme.cornerRadius, style: .continuous)
                .fill(MinoTheme.surfaceRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MinoTheme.cornerRadius, style: .continuous)
                .stroke(
                    isHovered ? Color.accentColor.opacity(0.3) : MinoTheme.border,
                    lineWidth: isHovered ? 1 : 0.5
                )
        )
        .onHover { isHovered = $0 }
        .contentShape(Rectangle())
        .onTapGesture {
            appState.selectAgent(agent.id)
            appState.viewMode = .chat
        }
        .contextMenu {
            if appState.generatingAgentIds.contains(agent.id) {
                Button(role: .destructive) {
                    appState.cancelGeneration(agentId: agent.id)
                } label: {
                    Label("Stop", systemImage: "stop.circle")
                }

                Button {
                    showRedirectPrompt = true
                } label: {
                    Label("Redirect...", systemImage: "arrow.triangle.turn.up.right.circle")
                }
            }

            Button {
                appState.selectAgent(agent.id)
                appState.viewMode = .chat
            } label: {
                Label("Open Chat", systemImage: "bubble.left")
            }
        }
        .sheet(isPresented: $showRedirectPrompt) {
            redirectSheet
        }
    }

    private var redirectSheet: some View {
        VStack(spacing: 16) {
            Text("Redirect \(agent.name)")
                .font(.system(size: 14, weight: .semibold))

            TextField("New prompt...", text: $redirectText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)

            HStack {
                Button("Cancel") { showRedirectPrompt = false }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Redirect") {
                    let newPrompt = redirectText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !newPrompt.isEmpty else { return }
                    appState.cancelGeneration(agentId: agent.id)
                    showRedirectPrompt = false
                    redirectText = ""
                    Task {
                        await appState.sendMessageToAgent(newPrompt, agentId: agent.id)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(redirectText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch status {
        case .idle:
            Text("Idle")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        case .thinking:
            Text("Thinking...")
                .font(.system(size: 10))
                .foregroundStyle(.orange)
        case .coding(let files):
            Text("Coding (\(files) files)")
                .font(.system(size: 10))
                .foregroundStyle(.blue)
        case .error(let msg):
            Text(msg)
                .font(.system(size: 10))
                .foregroundStyle(.red)
                .lineLimit(1)
        case .done:
            Text("Done")
                .font(.system(size: 10))
                .foregroundStyle(.green)
        }
    }

    @ViewBuilder
    private var statusDot: some View {
        switch status {
        case .idle:
            Circle()
                .fill(Color.gray.opacity(0.4))
                .frame(width: 8, height: 8)
        case .thinking, .coding:
            PulsingDot(color: .orange)
        case .error:
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
        case .done:
            Circle()
                .fill(.green)
                .frame(width: 8, height: 8)
        }
    }
}

// MARK: - Pulsing Dot (shared)

struct PulsingDot: View {
    let color: Color
    var size: CGFloat = 8
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .opacity(isPulsing ? 1.0 : 0.3)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}
