import SwiftUI

struct ChatView: View {
    @Environment(AppState.self) var appState
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
    /// Whether the scroll view is near the bottom — used to suppress auto-scroll when user scrolls up.
    @State private var isNearBottom: Bool = true
    /// ID of the selected session. Empty string = latest (current) session.
    @State private var selectedSessionId: String = ""
    /// Search
    @State private var isSearching = false
    @State private var searchText = ""
    @State private var searchResults: [(segmentId: String, messageId: UUID, preview: String)] = []
    @State private var searchResultIndex = 0

    /// Effective session ID — resolves empty to the latest segment's ID.
    private var effectiveSessionId: String {
        if !selectedSessionId.isEmpty { return selectedSessionId }
        guard let agentId = appState.activeAgentId,
              let segments = appState.conversations[agentId],
              let last = segments.last else { return "" }
        return last.id
    }

    /// The segment currently being viewed.
    private var activeSegment: ConversationSegment? {
        guard let agentId = appState.activeAgentId,
              let segments = appState.conversations[agentId],
              !segments.isEmpty else { return nil }
        let target = effectiveSessionId
        if !target.isEmpty,
           let match = segments.first(where: { $0.id == target }) {
            return match
        }
        return segments.last
    }

    /// Whether we're viewing a historical (non-current) session.
    private var isViewingHistory: Bool {
        guard let agentId = appState.activeAgentId,
              let segments = appState.conversations[agentId],
              !segments.isEmpty else { return false }
        let target = effectiveSessionId
        if target.isEmpty { return false }
        return segments.last?.id != target
    }

    /// Whether the session picker should be shown.
    private var hasMultipleSessions: Bool {
        guard let agentId = appState.activeAgentId else { return false }
        let segmentCount = appState.conversations[agentId]?.count ?? 0
        let pendingCount = appState.pendingClaudeSessions[agentId]?.count ?? 0
        return segmentCount + pendingCount > 1
    }

    /// Key that changes only when conversation structure changes (message added/removed).
    private var cacheKey: String {
        let agentId = appState.activeAgentId ?? ""
        let segId = activeSegment?.id ?? ""
        return "\(agentId)-\(appState.conversationVersion)-\(segId)"
    }

    /// Lightweight last-message-ID for scroll tracking — avoids flatMap over all segments.
    private var lastMessageId: UUID? {
        activeSegment?.messages.last?.id
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            if let agent = appState.activeAgent {
                chatHeader(agent)
                if isSearching {
                    searchBar
                }
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
                        // Sentinel to detect whether user is near bottom
                        Color.clear
                            .frame(height: 1)
                            .id("bottom-sentinel")
                            .onAppear { isNearBottom = true }
                            .onDisappear { isNearBottom = false }
                    }
                    .padding(20)
                }
                .scrollPosition(id: $scrollPositionId, anchor: .top)
                .onChange(of: appState.activeAgentId) { oldId, newId in
                    // Save scroll position for the agent we're leaving
                    if let oldId, let pos = scrollPositionId {
                        savedScrollPositions[oldId] = pos
                    }
                    // Reset to current session on agent switch
                    selectedSessionId = ""
                }
                .onChange(of: lastMessageId) {
                    let ctx = makeScrollContext()
                    if ScrollPolicy.onNewMessage(context: ctx) == .scrollToBottom {
                        scrollToBottom(proxy)
                    }
                }
                .onChange(of: appState.isGenerating) { _, generating in
                    if ScrollPolicy.onGeneratingChanged(isGenerating: generating) == .scrollToBottom {
                        scrollToBottom(proxy)
                    }
                }
                .task(id: cacheKey) {
                    cachedGroupedMessages = Self.computeGroupedMessages(
                        segment: activeSegment
                    )

                    let ctx = makeScrollContext()
                    switch ScrollPolicy.onCacheUpdated(context: ctx) {
                    case .restoreAnchor(let anchor):
                        anchorBeforeHistoryLoad = nil
                        DispatchQueue.main.async {
                            proxy.scrollTo(anchor, anchor: .top)
                        }
                    case .scrollToBottom:
                        if let agentId = appState.activeAgentId {
                            visitedAgentIds.insert(agentId)
                        }
                        scrollToBottom(proxy)
                    case .restoreSaved(let pos):
                        DispatchQueue.main.async {
                            scrollPositionId = pos
                        }
                    case .none:
                        break
                    }
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
            Text(agent.name)
                .font(.system(size: 13, weight: .medium))

            statusBadge(agent.status)

            Spacer()

            // New conversation button
            Button {
                appState.startNewConversation()
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("New conversation")
            .disabled(appState.isGenerating)

            // Search button
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isSearching.toggle()
                    if !isSearching {
                        searchText = ""
                        searchResults = []
                    }
                }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(isSearching ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help("Search messages")

            // Session picker — only show when there are multiple sessions
            if hasMultipleSessions {
                sessionPicker
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    // MARK: - Session Picker

    /// Build the list of session options for the picker (computed once per render, lightweight).
    private var pickerOptions: [SessionPickerOption] {
        guard let agentId = appState.activeAgentId else { return [] }
        var opts: [SessionPickerOption] = []

        // Loaded segments — newest first
        if let segments = appState.conversations[agentId] {
            for segment in segments.reversed() {
                let firstUser = segment.messages.first(where: { $0.role == .user })?.content ?? ""
                let preview = String(firstUser.prefix(30))
                let dateStr = formatSessionDate(segment.startDate)
                let isLatest = segment.id == segments.last?.id
                let label = isLatest ? "Current Session" : (preview.isEmpty ? dateStr : "\(dateStr)  \(preview)")
                opts.append(SessionPickerOption(id: segment.id, label: label, isLoaded: true))
            }
        }

        // Pending sessions — newest first, limit 20
        if let pending = appState.pendingClaudeSessions[agentId] {
            for summary in pending.prefix(20) {
                opts.append(SessionPickerOption(
                    id: summary.sessionId,
                    label: formatSessionDate(summary.modifiedDate),
                    isLoaded: false
                ))
            }
        }

        return opts
    }

    private var sessionPicker: some View {
        let binding = Binding<String>(
            get: { effectiveSessionId },
            set: { selectedSessionId = $0 }
        )
        return Picker("", selection: binding) {
            ForEach(pickerOptions) { opt in
                Text(opt.label).tag(opt.id)
            }
        }
        .pickerStyle(.menu)
        .fixedSize()
        .onChange(of: selectedSessionId) { _, newId in
            guard !newId.isEmpty, let agentId = appState.activeAgentId else { return }
            // If this is a pending session, trigger load
            if let pending = appState.pendingClaudeSessions[agentId],
               pending.contains(where: { $0.sessionId == newId }) {
                appState.loadPendingSession(agentId: agentId, sessionId: newId)
            }
        }
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            TextField("Search messages...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .onSubmit { performSearch() }
                .onChange(of: searchText) { _, newValue in
                    if newValue.isEmpty {
                        searchResults = []
                        searchResultIndex = 0
                    }
                }

            if !searchResults.isEmpty {
                Text("\(searchResultIndex + 1)/\(searchResults.count)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)

                Button {
                    if searchResultIndex > 0 { searchResultIndex -= 1 }
                    else { searchResultIndex = searchResults.count - 1 }
                    navigateToSearchResult()
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)

                Button {
                    if searchResultIndex < searchResults.count - 1 { searchResultIndex += 1 }
                    else { searchResultIndex = 0 }
                    navigateToSearchResult()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
            }

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isSearching = false
                    searchText = ""
                    searchResults = []
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
    }

    private func performSearch() {
        guard !searchText.isEmpty,
              let agentId = appState.activeAgentId,
              let segments = appState.conversations[agentId] else {
            searchResults = []
            return
        }

        let query = searchText.lowercased()
        var results: [(segmentId: String, messageId: UUID, preview: String)] = []

        for segment in segments {
            for msg in segment.messages where msg.type == .text {
                if msg.content.lowercased().contains(query) {
                    let preview = String(msg.content.prefix(60))
                    results.append((segmentId: segment.id, messageId: msg.id, preview: preview))
                }
            }
        }

        searchResults = results
        searchResultIndex = 0
        if !results.isEmpty {
            navigateToSearchResult()
        }
    }

    private func navigateToSearchResult() {
        guard searchResultIndex < searchResults.count else { return }
        let result = searchResults[searchResultIndex]
        // Switch to the segment containing the result
        selectedSessionId = result.segmentId
        // Scroll to the message
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            scrollPositionId = result.messageId.uuidString
        }
    }

    @ViewBuilder
    private func statusBadge(_ status: ConnectionStatus) -> some View {
        HStack(spacing: 4) {
            switch status {
            case .connected:
                Circle().fill(.green).frame(width: 4, height: 4)
                Text("Online")
            case .disconnected:
                Circle().fill(.gray).frame(width: 4, height: 4)
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
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            if let agent = appState.activeAgent {
                VStack(spacing: 6) {
                    Text(agent.name)
                        .font(.system(size: 16, weight: .medium))

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
                    Text(inputPlaceholder)
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
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
                        isInputFocused ? Color.accentColor.opacity(0.3) : MinoTheme.border,
                        lineWidth: isInputFocused ? 1 : 0.5
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
                        .foregroundStyle(canSend ? .secondary : Color.primary.opacity(0.12))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Message Grouping

    private static func computeGroupedMessages(
        segment: ConversationSegment?
    ) -> [MessageGroupItem] {
        guard let segment else { return [] }
        var result: [MessageGroupItem] = []
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

    private func makeScrollContext() -> ScrollContext {
        ScrollContext(
            activeAgentId: appState.activeAgentId,
            generatingAgentIds: appState.generatingAgentIds,
            isGenerating: appState.isGenerating,
            isNearBottom: isNearBottom,
            visitedAgentIds: visitedAgentIds,
            anchorBeforeHistoryLoad: anchorBeforeHistoryLoad,
            savedScrollPositions: savedScrollPositions
        )
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

    private var inputPlaceholder: String {
        if isViewingHistory {
            return "Continue this session..."
        }
        return "Message..."
    }

    private var canSend: Bool {
        guard appState.activeAgent != nil else { return false }
        return !inputText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func send() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        inputText = ""
        // When viewing a historical session, pass its claudeSessionId to resume
        let resumeId: String? = isViewingHistory ? activeSegment?.claudeSessionId : nil
        Task {
            await appState.sendMessage(trimmed, resumeSessionId: resumeId)
        }
    }
}

// MARK: - Session Picker Option

private struct SessionPickerOption: Identifiable {
    let id: String
    let label: String
    let isLoaded: Bool
}

// MARK: - Scroll Policy

/// Pure-value scroll decision — testable without SwiftUI.
enum ScrollAction: Equatable {
    /// Scroll to the very bottom of the conversation.
    case scrollToBottom
    /// Restore scroll to a specific message (e.g., after history prepend).
    case restoreAnchor(UUID)
    /// Restore a saved position for a returning agent.
    case restoreSaved(String)
    /// Do nothing — keep the current scroll position.
    case none
}

/// All inputs that influence scroll decisions, gathered into one struct.
struct ScrollContext {
    var activeAgentId: String?
    var generatingAgentIds: Set<String>
    var isGenerating: Bool
    var isNearBottom: Bool
    var visitedAgentIds: Set<String>
    var anchorBeforeHistoryLoad: UUID?
    var savedScrollPositions: [String: String]
}

enum ScrollPolicy {
    /// Decide what to do when `lastMessageId` changes (new message appended).
    static func onNewMessage(context: ScrollContext) -> ScrollAction {
        // Only auto-scroll when the active agent is generating and user is near bottom
        guard let agentId = context.activeAgentId,
              context.generatingAgentIds.contains(agentId),
              context.isNearBottom else {
            return .none
        }
        return .scrollToBottom
    }

    /// Decide what to do when `isGenerating` changes.
    static func onGeneratingChanged(isGenerating: Bool) -> ScrollAction {
        isGenerating ? .scrollToBottom : .none
    }

    /// Decide what to do after conversation cache is recomputed (cacheKey changed).
    static func onCacheUpdated(context: ScrollContext) -> ScrollAction {
        if let anchor = context.anchorBeforeHistoryLoad {
            return .restoreAnchor(anchor)
        }
        if let agentId = context.activeAgentId,
           !context.visitedAgentIds.contains(agentId) {
            return .scrollToBottom
        }
        if let agentId = context.activeAgentId,
           context.generatingAgentIds.contains(agentId) {
            return .scrollToBottom
        }
        if let agentId = context.activeAgentId,
           let savedPos = context.savedScrollPositions[agentId] {
            return .restoreSaved(savedPos)
        }
        return .none
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
    @Environment(AppState.self) var appState
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
        }
        .buttonStyle(.plain)
    }
}
