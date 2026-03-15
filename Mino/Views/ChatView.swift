import SwiftUI

struct ChatView: View {
    @EnvironmentObject var appState: AppState
    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool

    // Cached grouped messages — only recomputed when conversations or active agent change
    @State private var cachedGroupedMessages: [MessageGroupItem] = []
    /// When loading history, store the ID of the previously-first visible message
    /// so we can restore scroll position after prepending older messages.
    @State private var anchorBeforeHistoryLoad: UUID?
    /// Agents that have been visited — first visit scrolls to bottom, subsequent visits preserve position.
    @State private var visitedAgentIds: Set<String> = []
    /// Current scroll position tracked by scrollPosition(id:).
    @State private var scrollPositionId: String?
    /// Saved scroll positions per agent — restored when switching back.
    @State private var savedScrollPositions: [String: String] = [:]

    /// Key that changes only when conversation structure changes (message added/removed).
    private var cacheKey: String {
        "\(appState.activeAgentId ?? "")-\(appState.conversationVersion)"
    }

    /// Lightweight last-message-ID for scroll tracking — avoids flatMap over all segments.
    private var lastMessageId: UUID? {
        guard let id = appState.activeAgentId else { return nil }
        return appState.conversations[id]?.last?.messages.last?.id
    }

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
                        if appState.isLoadingHistory || appState.isLoadingMoreHistory {
                            ProgressView("Loading history...")
                                .controlSize(.small)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                        } else if let agentId = appState.activeAgentId,
                                  appState.hasMoreHistory(agentId: agentId) {
                            // Scroll-to-top trigger: loads older sessions on appear.
                            // id changes after each load so SwiftUI recreates the view,
                            // re-firing onAppear for continuous scroll-back loading.
                            Color.clear
                                .frame(height: 1)
                                .id("load-more-\(appState.pendingHistoryCount(agentId: agentId))")
                                .onAppear {
                                    // Remember the first message so we can restore scroll position
                                    anchorBeforeHistoryLoad = cachedGroupedMessages.first(where: {
                                        if case .single = $0 { return true }
                                        if case .toolCallGroup = $0 { return true }
                                        return false
                                    })?.firstMessageId
                                    appState.loadMoreHistory(agentId: agentId)
                                }
                        }

                        if cachedGroupedMessages.isEmpty && !appState.isLoadingHistory {
                            emptyState
                        }

                        ForEach(cachedGroupedMessages) { item in
                            switch item {
                            case .sessionDivider(let sid, let date):
                                sessionDivider(sessionId: sid, date: date)
                            case .single(let message):
                                // For streaming messages, read live content from conversations
                                // to avoid stale cached copies between version bumps
                                let liveMessage = message.isStreaming
                                    ? (lookupMessage(id: message.id) ?? message)
                                    : message
                                MessageBubble(message: liveMessage) { granted in
                                    appState.respondToPermission(
                                        messageId: message.id,
                                        agentId: appState.activeAgentId ?? "",
                                        granted: granted
                                    )
                                }
                                .id(message.id)
                            case .toolCallGroup(let messages):
                                ToolCallGroupBubble(messages: messages)
                                    .id(messages.first?.id ?? UUID())
                            }
                        }
                    }
                    .padding(20)
                }
                .scrollPosition(id: $scrollPositionId, anchor: .top)
                .onChange(of: appState.activeAgentId) { oldId, newId in
                    // Save scroll position for the agent we're leaving
                    if let oldId, let pos = scrollPositionId {
                        savedScrollPositions[oldId] = pos
                    }
                }
                .onChange(of: lastMessageId) {
                    // Only auto-scroll when Mino is actively generating a response.
                    // Watcher-pushed external messages should NOT pull user to bottom.
                    if let agentId = appState.activeAgentId,
                       appState.generatingAgentIds.contains(agentId) {
                        scrollToBottom(proxy)
                    }
                }
                .onChange(of: appState.isGenerating) { _, generating in
                    if generating { scrollToBottom(proxy) }
                }
                .task(id: cacheKey) {
                    cachedGroupedMessages = Self.computeGroupedMessages(
                        segments: appState.conversations[appState.activeAgentId ?? ""]
                    )

                    if let anchor = anchorBeforeHistoryLoad {
                        // History load: restore scroll to the message that was at the top.
                        anchorBeforeHistoryLoad = nil
                        DispatchQueue.main.async {
                            proxy.scrollTo(anchor, anchor: .top)
                        }
                    } else if let agentId = appState.activeAgentId,
                              !visitedAgentIds.contains(agentId) {
                        // First visit to this agent: scroll to bottom.
                        visitedAgentIds.insert(agentId)
                        scrollToBottom(proxy)
                    } else if let agentId = appState.activeAgentId,
                              let savedPos = savedScrollPositions[agentId] {
                        // Returning to a visited agent: restore saved scroll position.
                        DispatchQueue.main.async {
                            scrollPositionId = savedPos
                        }
                    }
                    // Otherwise (watcher messages, etc.): don't scroll.
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
            case .cliActive:
                ProgressView().controlSize(.mini)
                Text("CLI Working...")
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
                    .disabled(appState.activeAgent == nil || appState.activeAgent?.status == .cliActive)
                    .onKeyPress(.return, phases: .down) { keyPress in
                        if keyPress.modifiers.contains(.shift) {
                            return .ignored
                        }
                        send()
                        return .handled
                    }

                if inputText.isEmpty {
                    Text(appState.activeAgent?.status == .cliActive ? "CLI is working..." : "Message...")
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

    // MARK: - Message Grouping

    private static func computeGroupedMessages(segments: [ConversationSegment]?) -> [MessageGroupItem] {
        guard let segments else { return [] }
        var result: [MessageGroupItem] = []

        for (index, segment) in segments.enumerated() {
            if index > 0 {
                let sessionId = segment.claudeSessionId ?? segment.id
                result.append(.sessionDivider(sessionId, segment.startDate))
            }

            var toolCallBuffer: [ChatMessage] = []
            for msg in segment.messages {
                if msg.type == .toolCall {
                    toolCallBuffer.append(msg)
                } else {
                    if !toolCallBuffer.isEmpty {
                        result.append(.toolCallGroup(toolCallBuffer))
                        toolCallBuffer = []
                    }
                    result.append(.single(msg))
                }
            }
            if !toolCallBuffer.isEmpty {
                result.append(.toolCallGroup(toolCallBuffer))
            }
        }
        return result
    }

    private func sessionDivider(sessionId: String, date: Date) -> some View {
        HStack(spacing: 8) {
            dividerLine
            VStack(spacing: 2) {
                Text(formatSessionDate(date))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
                Text(String(sessionId.prefix(8)))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.quaternary)
            }
            .lineLimit(1)
            .fixedSize()
            dividerLine
        }
        .padding(.vertical, 12)
    }

    private var dividerLine: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.06))
            .frame(height: 0.5)
    }

    private func formatSessionDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
            return "Today \(formatter.string(from: date))"
        } else if calendar.isDateInYesterday(date) {
            formatter.dateFormat = "HH:mm"
            return "Yesterday \(formatter.string(from: date))"
        } else {
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            return formatter.string(from: date)
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let lastId = lastMessageId else { return }
        // Defer to next run loop to avoid publishing changes during view updates
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo(lastId, anchor: .bottom)
            }
        }
    }

    /// Look up the latest version of a message from live conversations (for streaming).
    private func lookupMessage(id: UUID) -> ChatMessage? {
        guard let agentId = appState.activeAgentId,
              let segments = appState.conversations[agentId] else { return nil }
        // Search from end since streaming message is always the last
        for segment in segments.reversed() {
            if let msg = segment.messages.last(where: { $0.id == id }) {
                return msg
            }
        }
        return nil
    }

    private var canSend: Bool {
        guard let agent = appState.activeAgent else { return false }
        if agent.status == .cliActive { return false }
        return !inputText.trimmingCharacters(in: .whitespaces).isEmpty
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

// MARK: - Message Group Item

enum MessageGroupItem: Identifiable {
    case single(ChatMessage)
    case toolCallGroup([ChatMessage])
    case sessionDivider(String, Date) // (sessionId, date)

    var id: String {
        switch self {
        case .single(let msg):
            return msg.id.uuidString
        case .toolCallGroup(let msgs):
            return msgs.first?.id.uuidString ?? "empty-group"
        case .sessionDivider(let sessionId, _):
            return "divider-\(sessionId)"
        }
    }

    /// The UUID of the first message in this item (nil for dividers).
    var firstMessageId: UUID? {
        switch self {
        case .single(let msg): return msg.id
        case .toolCallGroup(let msgs): return msgs.first?.id
        case .sessionDivider: return nil
        }
    }
}

// MARK: - Tool Call Group Bubble

struct ToolCallGroupBubble: View {
    let messages: [ChatMessage]
    @EnvironmentObject var appState: AppState
    @State private var isExpanded = false

    private var hasRunning: Bool {
        messages.contains { $0.toolCallInfo?.status == .running }
    }

    private var completedCount: Int {
        messages.filter { $0.toolCallInfo?.status == .completed }.count
    }

    private var summaryText: String {
        if hasRunning {
            let current = messages.last { $0.toolCallInfo?.status == .running }
            let formatted = current.flatMap { msg in
                msg.toolCallInfo.map { ToolCallFormatter.summary(toolName: $0.toolName, arguments: $0.arguments) }
            }
            return formatted?.text ?? "Working..."
        }
        let failed = messages.filter { $0.toolCallInfo?.status == .failed }.count
        if failed > 0 {
            return "\(completedCount) completed, \(failed) failed"
        }
        return "\(messages.count) tasks completed"
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                // Summary header
                HStack(spacing: 6) {
                    if hasRunning {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                    Text(summaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Text("\(messages.count)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(Capsule())
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.quaternary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isExpanded.toggle()
                    }
                }

                // Expanded list
                if isExpanded {
                    Divider()
                        .padding(.horizontal, 10)
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(messages) { msg in
                            if let info = msg.toolCallInfo {
                                let formatted = ToolCallFormatter.summary(toolName: info.toolName, arguments: info.arguments)
                                let isSelected = appState.selectedToolCallId == msg.id.uuidString
                                HStack(spacing: 6) {
                                    ToolCallStatusIcon(status: info.status, size: 10)
                                    Image(systemName: formatted.icon)
                                        .foregroundStyle(.secondary)
                                        .font(.system(size: 10))
                                    Text(formatted.text)
                                        .font(.system(size: 11))
                                        .lineLimit(1)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(isSelected ? MinoTheme.accentSoft : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    appState.selectedToolCallId = msg.id.uuidString
                                    if !appState.isTaskPanelVisible {
                                        appState.isTaskPanelVisible = true
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 6)
                }
            }
            .background(MinoTheme.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: MinoTheme.cornerRadiusSmall, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MinoTheme.cornerRadiusSmall, style: .continuous)
                    .stroke(MinoTheme.border, lineWidth: 0.5)
            )

            Spacer(minLength: 60)
        }
    }

}

// MARK: - Suggestion Pill

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
