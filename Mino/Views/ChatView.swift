import SwiftUI

struct ChatView: View {
    @EnvironmentObject var appState: AppState
    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            if let agent = appState.activeAgent {
                chatHeader(agent)
                Divider()
            }

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: MinoTheme.messageSpacing) {
                        if appState.activeMessages.isEmpty {
                            emptyState
                        }
                        ForEach(appState.activeMessages) { message in
                            MessageBubble(message: message) { granted in
                                appState.respondToPermission(
                                    messageId: message.id,
                                    agentId: appState.activeAgentId ?? "",
                                    granted: granted
                                )
                            }
                            .id(message.id)
                        }
                    }
                    .padding(20)
                }
                .onChange(of: appState.activeMessages.count) {
                    scrollToBottom(proxy)
                }
                .onChange(of: appState.activeMessages.last?.content) {
                    scrollToBottom(proxy)
                }
                .onChange(of: appState.activeMessages.last?.thinkingContent) {
                    scrollToBottom(proxy)
                }
            }

            Divider()

            // Input
            inputArea
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
    }

    private func chatHeader(_ agent: Agent) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(MinoTheme.avatarGradient(for: agent.name))
                    .frame(width: 28, height: 28)
                Text(String(agent.name.prefix(1)))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }

            Text(agent.name)
                .font(.system(size: 14, weight: .semibold))

            statusBadge(agent.status)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
    }

    @ViewBuilder
    private func statusBadge(_ status: ConnectionStatus) -> some View {
        HStack(spacing: 4) {
            switch status {
            case .connected:
                Circle().fill(.green).frame(width: 5, height: 5)
                Text("Online")
            case .disconnected:
                Circle().fill(.gray).frame(width: 5, height: 5)
                Text("Offline")
            case .connecting:
                ProgressView().controlSize(.mini)
                Text("Connecting...")
            case .reconnecting(let attempt):
                ProgressView().controlSize(.mini)
                Text("Reconnecting (\(attempt))...")
                    .foregroundStyle(.orange)
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Color.primary.opacity(0.04))
        .clipShape(Capsule())
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            if let agent = appState.activeAgent {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(MinoTheme.avatarGradient(for: agent.name))
                        .frame(width: 64, height: 64)
                        .shadow(color: MinoTheme.accent.opacity(0.2), radius: 16, y: 4)
                    Text(String(agent.name.prefix(1)))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }

                VStack(spacing: 6) {
                    Text(agent.name)
                        .font(.system(size: 18, weight: .semibold))

                    Text("Send a message to start a conversation")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 8) {
                    SuggestionPill(text: "Hello!") {
                        inputText = "Hello!"
                        send()
                    }
                    SuggestionPill(text: "What can you do?") {
                        inputText = "What can you do?"
                        send()
                    }
                }
                .padding(.top, 4)
            }
            Spacer()
        }
        .frame(maxHeight: .infinity)
    }

    private var inputArea: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $inputText)
                    .font(.system(size: 14))
                    .frame(minHeight: 36, maxHeight: 120)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .scrollContentBackground(.hidden)
                    .focused($isInputFocused)
                    .disabled(appState.activeAgent == nil)
                    .onKeyPress(.return, phases: .down) { keyPress in
                        if keyPress.modifiers.contains(.shift) {
                            return .ignored
                        }
                        send()
                        return .handled
                    }

                if inputText.isEmpty {
                    Text("Message...")
                        .font(.system(size: 14))
                        .foregroundStyle(.quaternary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: MinoTheme.cornerRadius, style: .continuous)
                    .fill(Color(.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: MinoTheme.cornerRadius, style: .continuous)
                    .stroke(
                        isInputFocused ? MinoTheme.accent.opacity(0.4) : MinoTheme.border,
                        lineWidth: isInputFocused ? 1.5 : 0.5
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: MinoTheme.cornerRadius, style: .continuous))

            if appState.isGenerating {
                Button {
                    appState.cancelGeneration()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.red.opacity(0.85))
                }
                .buttonStyle(.plain)
            } else {
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(canSend ? MinoTheme.accent : Color.primary.opacity(0.12))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if let last = appState.activeMessages.last {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private var canSend: Bool {
        appState.activeAgent != nil && !inputText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func send() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        inputText = ""
        Task {
            await appState.sendMessage(trimmed)
        }
    }
}

struct SuggestionPill: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.primary.opacity(0.04))
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }
}
