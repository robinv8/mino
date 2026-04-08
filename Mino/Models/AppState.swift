import SwiftUI
import UserNotifications

struct SessionStats {
    var totalCost: Double = 0
    var totalDurationMs: Int = 0
    var lastUpdated: Date = Date()
}

struct EnvironmentInfo {
    var model: String = ""
    var tools: [String] = []
    var mcpServers: [String] = []
    var plugins: [String] = []
}

/// Incrementally maintained dashboard statistics per agent.
struct TaskData {
    var taskItems: [TaskItem] = []
    /// Tool usage counts: [toolName: [status: count]]
    private var toolCounts: [String: [ToolCallStatus: Int]] = [:]
    var completedCount: Int = 0
    var failedCount: Int = 0
    var runningCount: Int = 0
    var userMessageCount: Int = 0
    var agentMessageCount: Int = 0

    var successRate: Double? {
        let finished = completedCount + failedCount
        return finished > 0 ? Double(completedCount) / Double(finished) : nil
    }

    var toolUsageData: [ToolUsageEntry] {
        var entries: [ToolUsageEntry] = []
        for (name, statusMap) in toolCounts.sorted(by: { $0.key < $1.key }) {
            for (status, count) in statusMap {
                entries.append(ToolUsageEntry(toolName: name, status: status, count: count))
            }
        }
        return entries
    }

    /// Add a new tool call (status = .running)
    mutating func addToolCall(_ item: TaskItem, info: ToolCallInfo) {
        taskItems.append(item)
        toolCounts[info.toolName, default: [:]][info.status, default: 0] += 1
        if info.status == .running { runningCount += 1 }
        if info.status == .completed { completedCount += 1 }
        if info.status == .failed { failedCount += 1 }
    }

    /// Update a tool call's status (e.g., running → completed)
    mutating func updateToolCall(id: String, newInfo: ToolCallInfo) {
        guard let idx = taskItems.firstIndex(where: { $0.id == id }) else { return }
        let oldInfo = taskItems[idx].toolCallInfo
        taskItems[idx] = TaskItem(
            id: id, kind: .toolCall, toolCallInfo: newInfo,
            thinkingContent: nil, timestamp: taskItems[idx].timestamp
        )
        // Adjust counts: decrement old status, increment new
        if let old = oldInfo {
            toolCounts[old.toolName, default: [:]][old.status, default: 1] -= 1
            switch old.status {
            case .running: runningCount -= 1
            case .completed: completedCount -= 1
            case .failed: failedCount -= 1
            }
        }
        toolCounts[newInfo.toolName, default: [:]][newInfo.status, default: 0] += 1
        switch newInfo.status {
        case .running: runningCount += 1
        case .completed: completedCount += 1
        case .failed: failedCount += 1
        }
    }
}

@MainActor
@Observable
class AppState {
    var agents: [Agent] = []
    var activeAgentId: String?
    /// Conversation storage — streaming content flows to views via @Observable.
    var conversations: [String: [ConversationSegment]] = [:]
    /// Structural version counter; only bumped when messages are added/removed/completed.
    /// Views use `task(id: cacheKey)` with this to avoid recomputing grouped message
    /// lists on every streaming text delta (which fires every 30ms).
    private(set) var conversationVersion: Int = 0

    /// Bump version to signal views that the conversation structure changed.
    /// Call after: appendMessage, tool call end, lifecycle end, history load.
    /// Do NOT call for streaming text content updates.
    private func bumpConversationVersion() {
        conversationVersion &+= 1
    }

    /// Start a new conversation for the active agent.
    /// Creates an empty segment with no claudeSessionId, so the next message won't resume.
    func startNewConversation() {
        guard let agentId = activeAgentId else { return }
        let segment = ConversationSegment(
            id: UUID().uuidString,
            agentId: agentId,
            startDate: Date(),
            messages: []
        )
        conversations[agentId, default: []].append(segment)
        bumpConversationVersion()
    }
    var generatingAgentIds: Set<String> = []
    var isGenerating: Bool { !generatingAgentIds.isEmpty }
    var unreadCounts: [String: Int] = [:]
    var totalUnreadCount: Int {
        unreadCounts.values.reduce(0, +)
    }
    var menuBarIconName: String {
        if totalUnreadCount > 0 {
            return "bubble.left.fill"
        } else if !generatingAgentIds.isEmpty {
            return "bubble.left.and.text.bubble.right"
        } else {
            return "bubble.left"
        }
    }
    var resources: [String: [ResourceItem]] = [:]
    var isTaskPanelVisible: Bool = false
    var selectedToolCallId: String?
    var sessionStats: [String: SessionStats] = [:]
    var environmentInfo: [String: EnvironmentInfo] = [:]
    /// Incrementally maintained task data per agent — TaskPanel reads directly.
    var taskData: [String: TaskData] = [:]
    /// Last error to display as toast
    var lastError: AppError?

    private var acpClients: [String: ACPClient] = [:]
    private var ccClients: [String: ClaudeCodeClient] = [:]
    let persistence = PersistenceService()
    private var streamTasks: [String: Task<Void, Never>] = [:]
    private var connectionTasks: [String: Task<Void, Never>] = [:]
    private var pendingMessage: String?
    private var contentSpecInjected: Set<String> = []
    /// Tracks which agents have already loaded Claude Code history
    private var claudeHistoryLoaded: Set<String> = []
    /// Remaining older sessions available for on-demand loading, keyed by agentId.
    /// Older Claude Code sessions not yet fully loaded — exposed for session card display.
    var pendingClaudeSessions: [String: [ClaudeSessionSummary]] = [:]
    /// Skipped (earlier) message count per session file, keyed by "agentId:sessionId".
    private var skippedMessageCounts: [String: Int] = [:]
    /// File paths per session, keyed by "agentId:sessionId".
    private var sessionFilePaths: [String: URL] = [:]
    var isLoadingMoreHistory: Bool = false
    // Throttle streaming text updates to avoid overwhelming SwiftUI
    private var pendingTextBuffer: [UUID: String] = [:]
    private var flushTasks: [String: Task<Void, Never>] = [:]
    private let flushInterval: UInt64 = 30_000_000 // 30ms

    /// View mode: chat (default single-agent) or command grid.
    enum ViewMode: String { case chat, command }
    var viewMode: ViewMode = .chat

    var activeAgent: Agent? {
        agents.first { $0.id == activeAgentId }
    }

    /// Derive activity status for an agent from existing data.
    func activityStatus(for agentId: String) -> AgentActivityStatus {
        if generatingAgentIds.contains(agentId) {
            let running = taskData[agentId]?.runningCount ?? 0
            if running > 0 {
                return .coding(filesChanged: filesChanged(for: agentId))
            }
            return .thinking
        }
        // Check if the latest message is an error
        if let segments = conversations[agentId],
           let lastMsg = segments.last?.messages.last,
           lastMsg.type == .error {
            return .error(String(lastMsg.content.prefix(60)))
        }
        return .idle
    }

    /// Count distinct file paths from tool calls for an agent.
    func filesChanged(for agentId: String) -> Int {
        guard let segments = conversations[agentId] else { return 0 }
        var files = Set<String>()
        for segment in segments {
            for msg in segment.messages where msg.type == .toolCall {
                guard let info = msg.toolCallInfo else { continue }
                let writableTools: Set<String> = ["Edit", "Write", "NotebookEdit"]
                guard writableTools.contains(info.toolName) else { continue }
                // Extract file_path from JSON arguments
                if let data = info.arguments.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let path = json["file_path"] as? String {
                    files.insert(path)
                }
            }
        }
        return files.count
    }


    // MARK: - Lifecycle

    func loadData() async {
        do {
            let loaded = try await persistence.loadAgents()
            agents = loaded.map { var a = $0; a.status = .disconnected; return a }
            for agent in agents {
                let segments = try await persistence.loadConversations(agentId: agent.id)
                if !segments.isEmpty {
                    conversations[agent.id] = segments
                }
            }
            bumpConversationVersion()
            // Build initial dashboard data from persisted conversations
            for agent in agents {
                rebuildTaskData(agentId: agent.id)
            }
        } catch {
            #if DEBUG
            print("[Mino] Failed to load data: \(error)")
            #endif
        }
        // Load Claude Code history
        for agent in agents where agent.type == .claudeCode {
            loadClaudeCodeHistory(agentId: agent.id)
        }

        // Auto-select first agent
        if activeAgentId == nil, let first = agents.first {
            activeAgentId = first.id
        }

        // Request notification permission
        requestNotificationPermission()
    }

    // MARK: - Mock Agent (for debugging UI)

    func loadMockAgent() {
        let mockId = "mock-preview"

        // Remove existing mock if present
        agents.removeAll { $0.id == mockId }
        conversations.removeValue(forKey: mockId)

        let agent = Agent(id: mockId, name: "Preview Bot", url: "mock://local", status: .connected)
        agents.append(agent)
        activeAgentId = mockId

        let messages: [ChatMessage] = [
            ChatMessage(role: .user, content: "Show me all the components", type: .text),

            // Text with markdown
            ChatMessage(role: .agent, content: "", type: .text, contentBlocks: [
                .text(TextBlock(content: "Here's a quick overview of what I can render:")),
            ]),

            // Code block
            ChatMessage(role: .agent, content: "", type: .text, contentBlocks: [
                .text(TextBlock(content: "A code snippet:")),
                .code(CodeBlock(
                    content: "struct Agent {\n    let id: String\n    var name: String\n    var status: ConnectionStatus\n}",
                    language: "swift",
                    filename: "Agent.swift"
                )),
            ]),

            // Multiple images (grid)
            ChatMessage(role: .agent, content: "", type: .text, contentBlocks: [
                .text(TextBlock(content: "Multiple images as a grid:")),
                .image(ImageBlock(url: "https://picsum.photos/seed/a/400/300", caption: "Mountain")),
                .image(ImageBlock(url: "https://picsum.photos/seed/b/400/300", caption: "Ocean")),
                .image(ImageBlock(url: "https://picsum.photos/seed/c/400/300", caption: "Forest")),
                .image(ImageBlock(url: "https://picsum.photos/seed/d/400/300", caption: "Desert")),
            ]),

            // Link card
            ChatMessage(role: .agent, content: "", type: .text, contentBlocks: [
                .link(LinkBlock(
                    url: "https://github.com/nicepkg/mino",
                    title: "Mino on GitHub",
                    description: "An open-source universal agent interaction client."
                )),
            ]),

            // Table
            ChatMessage(role: .agent, content: "", type: .text, contentBlocks: [
                .table(TableBlock(
                    headers: ["Component", "Status", "Type"],
                    rows: [
                        ["text", "Ready", "Display"],
                        ["image", "Ready", "Media"],
                        ["code", "Ready", "Display"],
                        ["table", "Ready", "Data"],
                        ["action", "Ready", "Interactive"],
                    ],
                    caption: "Component Status"
                )),
            ]),

            // Action buttons
            ChatMessage(role: .agent, content: "", type: .text, contentBlocks: [
                .action(ActionBlock(
                    prompt: "Would you like to continue?",
                    actions: [
                        ActionItem(id: "yes", label: "Continue", style: "primary"),
                        ActionItem(id: "no", label: "Cancel", style: "danger"),
                        ActionItem(id: "later", label: "Later", style: nil),
                    ]
                )),
            ]),

            // Radio + Checkbox + Dropdown
            ChatMessage(role: .agent, content: "", type: .text, contentBlocks: [
                .radio(RadioBlock(
                    label: "Pick a theme:",
                    options: [
                        SelectionOption(id: "light", label: "Light", description: "Clean and bright"),
                        SelectionOption(id: "dark", label: "Dark", description: "Easy on the eyes"),
                        SelectionOption(id: "auto", label: "Auto", description: "Follow system"),
                    ],
                    defaultValue: "dark"
                )),
                .checkbox(CheckboxBlock(
                    label: "Enable features:",
                    options: [
                        SelectionOption(id: "sync", label: "Cloud Sync"),
                        SelectionOption(id: "notify", label: "Notifications"),
                        SelectionOption(id: "analytics", label: "Analytics"),
                    ],
                    defaultValues: ["sync"]
                )),
                .dropdown(DropdownBlock(
                    label: "Language:",
                    placeholder: "Select...",
                    options: [
                        SelectionOption(id: "en", label: "English"),
                        SelectionOption(id: "zh", label: "Chinese"),
                        SelectionOption(id: "ja", label: "Japanese"),
                    ]
                )),
            ]),

            // File block
            ChatMessage(role: .agent, content: "", type: .text, contentBlocks: [
                .file(FileBlock(
                    path: "/tmp/report.pdf",
                    name: "report.pdf",
                    size: 2_048_576,
                    mimeType: "application/pdf"
                )),
            ]),

            // Audio
            ChatMessage(role: .agent, content: "", type: .text, contentBlocks: [
                .text(TextBlock(content: "Here's the recording:")),
                .audio(AudioBlock(
                    url: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3",
                    title: "Meeting Recording",
                    duration: 372
                )),
            ]),

            // Video
            ChatMessage(role: .agent, content: "", type: .text, contentBlocks: [
                .video(VideoBlock(
                    url: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4",
                    caption: "Big Buck Bunny — sample video"
                )),
            ]),

            // Callout variants
            ChatMessage(role: .agent, content: "", type: .text, contentBlocks: [
                .callout(CalloutBlock(style: "info", title: "Note", content: "This is an informational callout for general tips.")),
                .callout(CalloutBlock(style: "success", title: "Done", content: "The operation completed successfully.")),
                .callout(CalloutBlock(style: "warning", title: "Caution", content: "This action cannot be undone easily.")),
                .callout(CalloutBlock(style: "error", title: "Error", content: "Failed to connect to the remote server.")),
            ]),

            // Tool call
            ChatMessage(
                role: .agent, content: "", type: .toolCall,
                toolCallInfo: ToolCallInfo(
                    id: "tc-1", toolName: "Read",
                    arguments: "{ \"file_path\": \"/Users/robin/Projects/im/Mino/README.md\" }",
                    result: "File contents loaded (128 lines)",
                    status: .completed
                )
            ),
        ]

        // Create multiple segments to test session card UI
        let now = Date()
        let historySegment1 = ConversationSegment(
            id: "mock-session-1",
            agentId: mockId,
            startDate: now.addingTimeInterval(-7200), // 2 hours ago
            messages: [
                ChatMessage(role: .user, content: "重构 TaskPanel dashboard 布局", type: .text,
                            timestamp: now.addingTimeInterval(-7200)),
                ChatMessage(role: .agent, content: "好的，我来重构 TaskPanel。", type: .text,
                            timestamp: now.addingTimeInterval(-7190)),
                ChatMessage(role: .agent, content: "", type: .toolCall,
                            timestamp: now.addingTimeInterval(-7100),
                            toolCallInfo: ToolCallInfo(id: "h1-tc1", toolName: "Read",
                                arguments: "{\"file_path\":\"/src/Views/TaskPanel.swift\"}",
                                result: "ok", status: .completed)),
                ChatMessage(role: .agent, content: "", type: .toolCall,
                            timestamp: now.addingTimeInterval(-7000),
                            toolCallInfo: ToolCallInfo(id: "h1-tc2", toolName: "Edit",
                                arguments: "{\"file_path\":\"/src/Views/TaskPanel.swift\"}",
                                result: "ok", status: .completed)),
                ChatMessage(role: .agent, content: "", type: .toolCall,
                            timestamp: now.addingTimeInterval(-6900),
                            toolCallInfo: ToolCallInfo(id: "h1-tc3", toolName: "Edit",
                                arguments: "{\"file_path\":\"/src/Views/ContentView.swift\"}",
                                result: "ok", status: .completed)),
                ChatMessage(role: .agent, content: "重构完成！", type: .text,
                            timestamp: now.addingTimeInterval(-6600)),
            ],
            claudeSessionId: "claude-sess-abc123"
        )

        let historySegment2 = ConversationSegment(
            id: "mock-session-2",
            agentId: mockId,
            startDate: now.addingTimeInterval(-3600), // 1 hour ago
            messages: [
                ChatMessage(role: .user, content: "修复滚动位置丢失的 bug", type: .text,
                            timestamp: now.addingTimeInterval(-3600)),
                ChatMessage(role: .agent, content: "我来看看滚动逻辑。", type: .text,
                            timestamp: now.addingTimeInterval(-3590)),
                ChatMessage(role: .agent, content: "", type: .toolCall,
                            timestamp: now.addingTimeInterval(-3500),
                            toolCallInfo: ToolCallInfo(id: "h2-tc1", toolName: "Read",
                                arguments: "{\"file_path\":\"/src/Views/ChatView.swift\"}",
                                result: "ok", status: .completed)),
                ChatMessage(role: .agent, content: "", type: .toolCall,
                            timestamp: now.addingTimeInterval(-3400),
                            toolCallInfo: ToolCallInfo(id: "h2-tc2", toolName: "Edit",
                                arguments: "{\"file_path\":\"/src/Views/ChatView.swift\"}",
                                result: "ok", status: .completed)),
                ChatMessage(role: .agent, content: "已修复，滚动位置现在会正确保存和恢复。", type: .text,
                            timestamp: now.addingTimeInterval(-3100)),
            ],
            claudeSessionId: "claude-sess-def456"
        )

        let currentSegment = ConversationSegment(
            id: "mock-session-current",
            agentId: mockId,
            startDate: now.addingTimeInterval(-60),
            messages: messages
        )

        conversations[mockId] = [historySegment1, historySegment2, currentSegment]
        bumpConversationVersion()
    }

    // MARK: - Agent Management

    func addAgent(name: String, url: String) {
        let agent = Agent(id: UUID().uuidString, name: name, url: url, status: .disconnected, type: .acp)
        agents.append(agent)
        activeAgentId = agent.id
        saveAgents()
    }

    func addClaudeCodeAgent(name: String, workingDirectory: String) {
        let agent = Agent(
            id: UUID().uuidString,
            name: name,
            url: "",
            status: .disconnected,
            type: .claudeCode,
            workingDirectory: workingDirectory
        )
        agents.append(agent)
        activeAgentId = agent.id
        saveAgents()
    }

    func removeAgent(_ agent: Agent) {
        if let client = acpClients.removeValue(forKey: agent.id) {
            Task { await client.disconnect() }
        }
        if let client = ccClients.removeValue(forKey: agent.id) {
            client.stopTransport()
        }
        agents.removeAll { $0.id == agent.id }
        conversations.removeValue(forKey: agent.id)
        bumpConversationVersion()
        if activeAgentId == agent.id {
            activeAgentId = agents.first?.id
        }
        saveAgents()
    }

    func updateAgent(id: String, name: String, url: String) {
        guard let idx = agents.firstIndex(where: { $0.id == id }) else { return }
        agents[idx].name = name
        agents[idx].url = url
        saveAgents()
    }

    // MARK: - Messaging

    /// Send a message to the active agent. Delegates to `sendMessageToAgent`.
    func sendMessage(_ content: String, resumeSessionId: String? = nil) async {
        guard let agentId = activeAgentId else { return }
        await sendMessageToAgent(content, agentId: agentId, resumeSessionId: resumeSessionId)
    }

    /// Send a message to a specific agent by ID. Supports parallel multi-agent dispatch.
    func sendMessageToAgent(_ content: String, agentId: String, resumeSessionId: String? = nil) async {
        guard let agent = agents.first(where: { $0.id == agentId }) else { return }

        let userMessage = ChatMessage(role: .user, content: content, type: .text)
        appendMessage(userMessage, to: agentId)

        switch agent.type {
        case .acp:
            await sendViaACP(content, agentId: agentId)
        case .claudeCode:
            await sendViaClaudeCode(content, agentId: agentId, explicitResumeSessionId: resumeSessionId)
        }
    }

    private func sendViaACP(_ content: String, agentId: String) async {
        let streamingId = UUID()
        let placeholder = ChatMessage(
            id: streamingId, role: .agent, content: "", type: .streaming, isStreaming: true
        )
        appendMessage(placeholder, to: agentId)
        generatingAgentIds.insert(agentId)
        updateDockBadge()

        do {
            try await ensureConnected(agentId: agentId)
        } catch {
            updateMessage(id: streamingId, agentId: agentId) { msg in
                msg.content = "Connection failed: \(error.localizedDescription)"
                msg.type = .error
                msg.isStreaming = false
            }
            generatingAgentIds.remove(agentId)
            return
        }

        guard let client = acpClients[agentId] else { return }

        // Start stream consumer BEFORE sending message
        streamTasks[agentId] = Task {
            for await update in await client.streamUpdates() {
                guard !Task.isCancelled else { break }
                handleUpdate(update, streamingId: streamingId, agentId: agentId)
            }
        }

        // Auto-inject Content Spec context into the first message after each connection
        let needsInjection = !contentSpecInjected.contains(agentId)
        let actualContent = needsInjection ? contentSpecContext + content : content
        if needsInjection { contentSpecInjected.insert(agentId) }
        do {
            try await client.sendMessage(actualContent)
        } catch {
            updateMessage(id: streamingId, agentId: agentId) { msg in
                msg.content = "Failed to send: \(error.localizedDescription)"
                msg.type = .error
                msg.isStreaming = false
            }
            generatingAgentIds.remove(agentId)
        }
    }

    private func sendViaClaudeCode(_ content: String, agentId: String, explicitResumeSessionId: String? = nil) async {
        guard let agent = agents.first(where: { $0.id == agentId }) else { return }
        let cwd = agent.workingDirectory ?? FileManager.default.currentDirectoryPath

        // Get or create client
        let client: ClaudeCodeClient
        let isNewClient: Bool
        if let existing = ccClients[agentId] {
            client = existing
            isNewClient = false
        } else {
            client = ClaudeCodeClient(workingDirectory: cwd)
            ccClients[agentId] = client
            isNewClient = true
        }

        // Load local config on first connection
        if isNewClient {
            var info = environmentInfo[agentId] ?? EnvironmentInfo()
            info.mcpServers = ClaudeConfigReader.readMCPServers()
            info.plugins = ClaudeConfigReader.readPlugins()
            environmentInfo[agentId] = info
        }

        let streamingId = UUID()
        let placeholder = ChatMessage(
            id: streamingId, role: .agent, content: "", type: .streaming, isStreaming: true
        )
        appendMessage(placeholder, to: agentId)
        generatingAgentIds.insert(agentId)
        updateDockBadge()

        if let idx = agents.firstIndex(where: { $0.id == agentId }) {
            agents[idx].status = .connecting
        }

        // Use explicit resume ID if provided, otherwise fall back to latest segment
        let resumeSessionId = explicitResumeSessionId ?? conversations[agentId]?.last?.claudeSessionId

        do {
            let updateStream = try client.sendMessage(content, resumeSessionId: resumeSessionId)

            if let idx = agents.firstIndex(where: { $0.id == agentId }) {
                agents[idx].status = .connected
            }

            streamTasks[agentId] = Task {
                for await update in updateStream {
                    guard !Task.isCancelled else { break }
                    handleUpdate(update, streamingId: streamingId, agentId: agentId)
                }
                if let idx = agents.firstIndex(where: { $0.id == agentId }) {
                    agents[idx].status = .disconnected
                }
            }
        } catch {
            updateMessage(id: streamingId, agentId: agentId) { msg in
                msg.content = "Claude Code failed: \(error.localizedDescription)"
                msg.type = .error
                msg.isStreaming = false
            }
            generatingAgentIds.remove(agentId)
            lastError = .processStartFailed(error.localizedDescription)
            if let idx = agents.firstIndex(where: { $0.id == agentId }) {
                agents[idx].status = .disconnected
            }
        }
    }

    /// Cancel generation for the active agent.
    func cancelGeneration() {
        guard let agentId = activeAgentId else { return }
        cancelGeneration(agentId: agentId)
    }

    /// Cancel generation for a specific agent.
    func cancelGeneration(agentId: String) {
        streamTasks[agentId]?.cancel()
        streamTasks.removeValue(forKey: agentId)
        flushTasks[agentId]?.cancel()
        flushTasks.removeValue(forKey: agentId)
        generatingAgentIds.remove(agentId)

        if let client = acpClients[agentId] {
            Task { try? await client.cancelChat() }
        }
        if let client = ccClients[agentId] {
            client.stopTransport()
        }

        if let segments = conversations[agentId] {
            for segment in segments {
                for msg in segment.messages where msg.isStreaming {
                    updateMessage(id: msg.id, agentId: agentId) { m in
                        m.isStreaming = false
                        m.type = .text
                    }
                }
            }
        }
    }

    func respondToPermission(messageId: UUID, agentId: String, granted: Bool) {
        updateMessage(id: messageId, agentId: agentId) { msg in
            msg.permissionRequest?.response = granted
        }
        // TODO: send permission response when OpenClaw supports it
    }

    // MARK: - Private: Connection

    private func ensureConnected(agentId: String) async throws {
        if let client = acpClients[agentId], await client.isConnected {
            return
        }

        guard let agentIdx = agents.firstIndex(where: { $0.id == agentId }) else {
            return
        }
        agents[agentIdx].status = .connecting

        guard let url = URL(string: agents[agentIdx].url) else {
            agents[agentIdx].status = .disconnected
            throw ACPClientError.authFailed
        }

        let credentials = Self.loadOpenClawCredentials()

        let client = ACPClient(url: url, credentials: credentials)
        do {
            try await client.connect()
        } catch {
            agents[agentIdx].status = .disconnected
            lastError = .connectionFailed(error.localizedDescription)
            throw error
        }

        acpClients[agentId] = client
        agents[agentIdx].status = .connected
        agents[agentIdx].currentSessionId = await client.sessionKey

        // Monitor connection status
        monitorConnection(agentId: agentId, client: client)
    }

    private func monitorConnection(agentId: String, client: ACPClient) {
        connectionTasks[agentId]?.cancel()
        connectionTasks[agentId] = Task {
            for await status in await client.connectionStatus {
                guard !Task.isCancelled else { break }
                guard let idx = agents.firstIndex(where: { $0.id == agentId }) else { break }
                agents[idx].status = status
                // Auto-reconnect on disconnect
                if case .disconnected = status {
                    await client.startReconnection()
                }
            }
        }
    }

    private static func loadOpenClawCredentials() -> OpenClawCredentials {
        // Sandboxed app's homeDirectory points to the container; use real home path instead
        let home: URL
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            home = URL(fileURLWithPath: String(cString: dir))
        } else {
            home = FileManager.default.homeDirectoryForCurrentUser
        }
        var creds = OpenClawCredentials()

        // Read device identity
        let devicePath = home.appendingPathComponent(".openclaw/identity/device.json")
        if let data = try? Data(contentsOf: devicePath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            creds.deviceId = json["deviceId"] as? String
            creds.publicKeyPem = json["publicKeyPem"] as? String
            creds.privateKeyPem = json["privateKeyPem"] as? String
        }

        // Read auth token
        let authPath = home.appendingPathComponent(".openclaw/identity/device-auth.json")
        if let data = try? Data(contentsOf: authPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let tokens = json["tokens"] as? [String: Any],
           let operator_ = tokens["operator"] as? [String: Any] {
            creds.token = operator_["token"] as? String
            creds.role = operator_["role"] as? String ?? "operator"
            creds.scopes = operator_["scopes"] as? [String] ?? ["operator.admin"]
        }

        // Read gateway password
        let configPath = home.appendingPathComponent(".openclaw/openclaw.json")
        if let data = try? Data(contentsOf: configPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let gateway = json["gateway"] as? [String: Any],
           let auth = gateway["auth"] as? [String: Any] {
            creds.password = auth["password"] as? String
        }

        return creds
    }

    // MARK: - Private: Stream Handling

    private func handleUpdate(_ update: SessionUpdate, streamingId: UUID, agentId: String) {
        switch update {
        case .textDelta(let text):
            // Buffer deltas and flush at intervals to reduce SwiftUI re-renders
            pendingTextBuffer[streamingId, default: ""] += text
            scheduleFlush(streamingId: streamingId, agentId: agentId)

        case .textComplete(let text):
            flushPendingText(streamingId: streamingId, agentId: agentId)
            updateMessage(id: streamingId, agentId: agentId) { msg in
                msg.content = text
                msg.type = .text
                msg.isStreaming = false
            }
            generatingAgentIds.remove(agentId)
            saveConversations(agentId: agentId)
            notifyAgentFinished(agentId: agentId, messageId: streamingId)

        case .toolCallStart(let info):
            let msg = ChatMessage(role: .agent, content: "", type: .toolCall, toolCallInfo: info)
            appendMessage(msg, to: agentId)
            // Incremental: add to dashboard
            let item = TaskItem(
                id: msg.id.uuidString, kind: .toolCall, toolCallInfo: info,
                thinkingContent: nil, timestamp: msg.timestamp
            )
            taskData[agentId, default: TaskData()].addToolCall(item, info: info)

        case .toolCallEnd(let info):
            if let segments = conversations[agentId] {
                for segment in segments {
                    if let msg = segment.messages.last(where: { $0.toolCallInfo?.id == info.id }) {
                        updateMessage(id: msg.id, agentId: agentId) { m in
                            m.toolCallInfo = info
                        }
                        // Incremental: update status in dashboard
                        taskData[agentId, default: TaskData()].updateToolCall(
                            id: msg.id.uuidString, newInfo: info
                        )
                    }
                }
            }

        case .thought(let text):
            updateMessage(id: streamingId, agentId: agentId, silent: true) { msg in
                msg.thinkingContent += text
            }

        case .permissionRequest(let request):
            appendMessage(
                ChatMessage(role: .agent, content: request.description, type: .confirmation, permissionRequest: request),
                to: agentId
            )

        case .image(let url, let caption):
            appendMessage(
                ChatMessage(role: .agent, content: caption ?? "", type: .image, imageURL: url),
                to: agentId
            )

        case .contentBlocks(let blocks):
            appendMessage(
                ChatMessage(role: .agent, content: "", type: .text, contentBlocks: blocks),
                to: agentId
            )

        case .error(let text):
            updateMessage(id: streamingId, agentId: agentId) { msg in
                msg.content = text
                msg.type = .error
                msg.isStreaming = false
            }
            generatingAgentIds.remove(agentId)

        case .sessionResult(let durationMs, let costUsd):
            var stats = sessionStats[agentId] ?? SessionStats()
            stats.totalCost += costUsd
            stats.totalDurationMs += durationMs
            stats.lastUpdated = Date()
            sessionStats[agentId] = stats

        case .systemInfo(let model, let tools, let sessionId):
            if !model.isEmpty || !tools.isEmpty {
                var info = environmentInfo[agentId] ?? EnvironmentInfo()
                if !model.isEmpty { info.model = model }
                if !tools.isEmpty { info.tools = tools }
                environmentInfo[agentId] = info
            }
            if let sessionId, !sessionId.isEmpty {
                updateCurrentSegmentId(agentId: agentId, sessionId: sessionId)
            }

        case .lifecycleStart:
            break  // already showing streaming bubble

        case .lifecycleEnd:
            flushPendingText(streamingId: streamingId, agentId: agentId)
            updateMessage(id: streamingId, agentId: agentId) { msg in
                if msg.isStreaming {
                    msg.type = .text
                    msg.isStreaming = false
                    // Parse mino-block tags from finalized text
                    if let blocks = ContentBlockParser.parseInlineBlocks(msg.content) {
                        msg.contentBlocks = blocks
                        msg.content = "" // blocks take over rendering
                    }
                }
            }
            // Extract resources from finalized message
            if let msg = findMessage(id: streamingId, agentId: agentId) {
                let extracted = ResourceExtractor.extract(from: msg)
                if !extracted.isEmpty {
                    resources[agentId, default: []].append(contentsOf: extracted)
                }
            }
            generatingAgentIds.remove(agentId)
            saveConversations(agentId: agentId)

            notifyAgentFinished(agentId: agentId, messageId: streamingId)
        }
    }

    func selectAgent(_ agentId: String) {
        activeAgentId = agentId
        unreadCounts[agentId] = 0
        updateDockBadge()
        // Lazily load Claude Code history on first switch
        loadClaudeCodeHistory(agentId: agentId)
    }

    // MARK: - Private: Text Delta Throttling

    private func scheduleFlush(streamingId: UUID, agentId: String) {
        guard flushTasks[agentId] == nil else { return }
        flushTasks[agentId] = Task {
            try? await Task.sleep(nanoseconds: flushInterval)
            flushPendingText(streamingId: streamingId, agentId: agentId)
        }
    }

    private func flushPendingText(streamingId: UUID, agentId: String) {
        flushTasks[agentId]?.cancel()
        flushTasks.removeValue(forKey: agentId)
        guard let buffered = pendingTextBuffer.removeValue(forKey: streamingId), !buffered.isEmpty else { return }
        // Silent: streaming text deltas should NOT bump conversationVersion
        updateMessage(id: streamingId, agentId: agentId, silent: true) { msg in
            msg.content += buffered
        }
    }

    // MARK: - Private: Message Helpers

    private func appendMessage(_ message: ChatMessage, to agentId: String) {
        // Track unread for non-active agents
        if message.role == .agent && agentId != activeAgentId {
            unreadCounts[agentId, default: 0] += 1
        }
        // Increment message stats
        switch message.role {
        case .user: taskData[agentId, default: TaskData()].userMessageCount += 1
        case .agent: taskData[agentId, default: TaskData()].agentMessageCount += 1
        }

        if conversations[agentId] == nil {
            conversations[agentId] = []
        }
        if conversations[agentId]!.isEmpty {
            let segment = ConversationSegment(
                id: agents.first(where: { $0.id == agentId })?.currentSessionId ?? UUID().uuidString,
                agentId: agentId,
                startDate: Date(),
                messages: [message]
            )
            conversations[agentId]!.append(segment)
        } else {
            conversations[agentId]![conversations[agentId]!.count - 1].messages.append(message)
        }
        bumpConversationVersion()

        // Extract resources
        let extracted = ResourceExtractor.extract(from: message)
        if !extracted.isEmpty {
            resources[agentId, default: []].append(contentsOf: extracted)
        }
    }

    /// Update a message in-place. Set `silent` to true for streaming content updates
    /// that should NOT trigger view recomputation (e.g., text delta flushes).
    private func updateMessage(id: UUID, agentId: String, silent: Bool = false, transform: (inout ChatMessage) -> Void) {
        guard var segments = conversations[agentId] else { return }
        for i in segments.indices {
            if let j = segments[i].messages.firstIndex(where: { $0.id == id }) {
                transform(&segments[i].messages[j])
                conversations[agentId] = segments
                if !silent {
                    bumpConversationVersion()
                }
                return
            }
        }
    }

    private func findMessage(id: UUID, agentId: String) -> ChatMessage? {
        guard let segments = conversations[agentId] else { return nil }
        for segment in segments.reversed() {
            if let msg = segment.messages.first(where: { $0.id == id }) { return msg }
        }
        return nil
    }

    // MARK: - Private: Content Spec Injection

    private let contentSpecContext = """
    [System — Rendering Format]
    This client renders <mino-block /> tags as native UI components. Treat them like Markdown — use them naturally without mentioning the tags themselves. Never explain that you are using these tags; just embed them inline.

    Format reference:
    <mino-block type="image" url="..." caption="..." />
    <mino-block type="code" language="..." filename="..." content="..." />
    <mino-block type="link" url="..." title="..." description="..." />
    <mino-block type="file" path="..." name="..." size="..." mimeType="..." />
    <mino-block type="table" headers='["A","B"]' rows='[["1","2"]]' caption="..." />
    <mino-block type="action" prompt="..." actions='[{"id":"ok","label":"OK","style":"primary"}]' />
    <mino-block type="radio" label="..." options='[{"id":"a","label":"A"}]' />
    <mino-block type="checkbox" label="..." options='[{"id":"a","label":"A"}]' />
    <mino-block type="dropdown" label="..." options='[{"id":"a","label":"A"}]' placeholder="..." />
    <mino-block type="audio" url="..." title="..." duration="120" />
    <mino-block type="video" url="..." caption="..." />
    <mino-block type="callout" style="info|warning|error|success" title="..." content="..." />

    Keep text brief and conversational. Let the components speak for themselves.
    [End System]

    """

    // MARK: - Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, error in
            _ = error
        }
    }

    /// Notify user when an agent finishes generating (notification + dock badge).
    /// Called from all stream-end paths.
    func notifyAgentFinished(agentId: String, messageId: UUID? = nil) {
        updateDockBadge()

        guard UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true else { return }
        // Skip notification if user is actively viewing this agent's chat
        let isViewingThisAgent = agentId == activeAgentId
            && (NSApplication.shared.mainWindow?.isKeyWindow ?? false)
        guard !isViewingThisAgent else { return }

        let agentName = agents.first(where: { $0.id == agentId })?.name ?? "Agent"
        var preview = "Task completed"
        if let mid = messageId, let msg = findMessage(id: mid, agentId: agentId) {
            let text = msg.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                preview = String(text.prefix(100))
            }
        }

        let content = UNMutableNotificationContent()
        content.title = agentName
        content.body = preview
        content.sound = .default
        content.userInfo = ["agentId": agentId]

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func updateDockBadge() {
        let unread = totalUnreadCount
        let generating = generatingAgentIds.count
        if unread > 0 {
            NSApplication.shared.dockTile.badgeLabel = "\(unread)"
        } else if generating > 0 {
            NSApplication.shared.dockTile.badgeLabel = "●"
        } else {
            NSApplication.shared.dockTile.badgeLabel = nil
        }
    }

    // MARK: - Claude Code History

    var isLoadingHistory: Bool = false

    /// Load the tail of the most recent Claude Code session for an agent.
    /// Only loads the last ~50 messages; older messages and sessions are loaded on scroll.
    func loadClaudeCodeHistory(agentId: String) {
        guard !claudeHistoryLoaded.contains(agentId) else { return }
        guard let agent = agents.first(where: { $0.id == agentId }),
              agent.type == .claudeCode,
              let cwd = agent.workingDirectory else { return }

        claudeHistoryLoaded.insert(agentId)
        let hasExistingConversation = !(conversations[agentId]?.isEmpty ?? true)

        if hasExistingConversation {
            // Watcher already populated current session — just discover older sessions
            Task {
                let sessions = await Task.detached(priority: .userInitiated) {
                    guard let projectDir = ClaudeSessionLoader.projectDir(for: cwd) else { return [ClaudeSessionSummary]() }
                    return ClaudeSessionLoader.listSessions(projectDir: projectDir)
                }.value

                // Exclude sessions that are already loaded as segments
                let loadedIds = Set(conversations[agentId]?.map(\.id) ?? [])
                let older = sessions.filter { !loadedIds.contains($0.sessionId) }
                if !older.isEmpty {
                    pendingClaudeSessions[agentId] = older
                    bumpConversationVersion() // trigger UI refresh
                }
            }
        } else {
            // No conversation yet — load the most recent session + discover older ones
            isLoadingHistory = true
            Task {
                let result = await Task.detached(priority: .userInitiated) {
                    ClaudeSessionLoader.loadMostRecentSession(for: cwd, agentId: agentId, tailCount: 50)
                }.value

                if let segment = result.segment {
                    conversations[agentId] = [segment]
                    bumpConversationVersion()
                    rebuildTaskData(agentId: agentId)

                    // Track skipped messages for this session
                    if result.skippedMessagesInSession > 0 {
                        let key = "\(agentId):\(segment.id)"
                        skippedMessageCounts[key] = result.skippedMessagesInSession
                        if let projectDir = ClaudeSessionLoader.projectDir(for: cwd) {
                            sessionFilePaths[key] = projectDir
                                .appendingPathComponent(segment.id)
                                .appendingPathExtension("jsonl")
                        }
                    }
                }
                if !result.olderSessions.isEmpty {
                    pendingClaudeSessions[agentId] = result.olderSessions
                }
                isLoadingHistory = false
            }
        }
    }

    /// Whether more history is available: either skipped messages in current session,
    /// or older sessions not yet loaded.
    func hasMoreHistory(agentId: String) -> Bool {
        // Check skipped messages in the first (oldest loaded) segment
        if let segments = conversations[agentId], let first = segments.first {
            let key = "\(agentId):\(first.id)"
            if (skippedMessageCounts[key] ?? 0) > 0 { return true }
        }
        // Check older sessions
        return !(pendingClaudeSessions[agentId]?.isEmpty ?? true)
    }

    /// Counter that changes on each load — used as SwiftUI view identity for scroll trigger.
    func pendingHistoryCount(agentId: String) -> Int {
        let sessionCount = pendingClaudeSessions[agentId]?.count ?? 0
        let skippedCount: Int
        if let segments = conversations[agentId], let first = segments.first {
            skippedCount = skippedMessageCounts["\(agentId):\(first.id)"] ?? 0
        } else {
            skippedCount = 0
        }
        return sessionCount * 10000 + skippedCount
    }

    /// Load more history for an agent (triggered by scroll-to-top).
    /// First loads skipped messages within the current session, then older sessions.
    func loadMoreHistory(agentId: String) {
        guard !isLoadingMoreHistory else { return }

        // Priority 1: Load earlier messages from the oldest loaded session
        if let segments = conversations[agentId], let first = segments.first {
            let key = "\(agentId):\(first.id)"
            if let skipped = skippedMessageCounts[key], skipped > 0,
               let filePath = sessionFilePaths[key] {
                isLoadingMoreHistory = true
                let currentSkipped = skipped
                Task {
                    let (messages, newSkipped) = await Task.detached(priority: .userInitiated) {
                        ClaudeSessionLoader.loadEarlierMessages(
                            from: filePath, currentSkipped: currentSkipped, count: 50
                        )
                    }.value

                    if !messages.isEmpty, var segs = conversations[agentId] {
                        segs[0].messages.insert(contentsOf: messages, at: 0)
                        conversations[agentId] = segs
                        bumpConversationVersion()
                    }
                    skippedMessageCounts[key] = newSkipped
                    isLoadingMoreHistory = false
                }
                return
            }
        }

        // Priority 2: Load the next older session
        guard var pending = pendingClaudeSessions[agentId], !pending.isEmpty else { return }
        let next = pending.removeFirst()
        pendingClaudeSessions[agentId] = pending
        isLoadingMoreHistory = true

        Task {
            let segment = await Task.detached(priority: .userInitiated) {
                ClaudeSessionLoader.loadSession(next, agentId: agentId)
            }.value

            if let segment {
                if conversations[agentId] != nil {
                    conversations[agentId]!.insert(segment, at: 0)
                } else {
                    conversations[agentId] = [segment]
                }
                bumpConversationVersion()
            }
            isLoadingMoreHistory = false
        }
    }

    /// Load a specific pending session by sessionId and insert it into conversations.
    /// Used when user taps a session card for a not-yet-loaded older session.
    func loadPendingSession(agentId: String, sessionId: String) {
        guard var pending = pendingClaudeSessions[agentId],
              let idx = pending.firstIndex(where: { $0.sessionId == sessionId }) else { return }
        let summary = pending.remove(at: idx)
        pendingClaudeSessions[agentId] = pending

        isLoadingMoreHistory = true
        Task {
            let segment = await Task.detached(priority: .userInitiated) {
                ClaudeSessionLoader.loadSession(summary, agentId: agentId)
            }.value

            if let segment {
                if var segs = conversations[agentId] {
                    // Insert in chronological order
                    let insertIdx = segs.firstIndex(where: { $0.startDate > segment.startDate }) ?? segs.endIndex
                    segs.insert(segment, at: insertIdx)
                    conversations[agentId] = segs
                } else {
                    conversations[agentId] = [segment]
                }
                bumpConversationVersion()
            }
            isLoadingMoreHistory = false
        }
    }

    // MARK: - Task Data

    /// Full rebuild of taskData for an agent from its conversations. Used after history load.
    func rebuildTaskData(agentId: String) {
        guard let segments = conversations[agentId] else {
            taskData.removeValue(forKey: agentId)
            return
        }
        var data = TaskData()
        for segment in segments {
            for msg in segment.messages {
                switch msg.role {
                case .user: data.userMessageCount += 1
                case .agent: data.agentMessageCount += 1
                }
                if msg.type == .toolCall, let info = msg.toolCallInfo {
                    let item = TaskItem(
                        id: msg.id.uuidString, kind: .toolCall, toolCallInfo: info,
                        thinkingContent: nil, timestamp: msg.timestamp
                    )
                    data.addToolCall(item, info: info)
                }
            }
        }
        taskData[agentId] = data
    }

    // MARK: - Private: Persistence

    private func saveAgents() {
        Task { try? await persistence.saveAgents(agents) }
    }

    private func updateCurrentSegmentId(agentId: String, sessionId: String) {
        guard var segments = conversations[agentId], !segments.isEmpty else { return }
        segments[segments.count - 1].claudeSessionId = sessionId
        conversations[agentId] = segments
    }

    private func saveConversations(agentId: String) {
        let segments = conversations[agentId] ?? []
        Task { try? await persistence.saveConversations(agentId: agentId, segments: segments) }
    }

}
