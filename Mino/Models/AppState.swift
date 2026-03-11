import SwiftUI

@MainActor
class AppState: ObservableObject {
    @Published var agents: [Agent] = []
    @Published var activeAgentId: String?
    @Published var conversations: [String: [ConversationSegment]] = [:]
    @Published var isGenerating: Bool = false
    @Published var unreadCounts: [String: Int] = [:]
    @Published var resources: [String: [ResourceItem]] = [:]
    @Published var isResourcePanelVisible: Bool = false

    private var acpClients: [String: ACPClient] = [:]
    let persistence = PersistenceService()
    private var streamTask: Task<Void, Never>?
    private var connectionTasks: [String: Task<Void, Never>] = [:]
    private var pendingMessage: String?
    private var contentSpecInjected: Set<String> = []

    // Throttle streaming text updates to avoid overwhelming SwiftUI
    private var pendingTextBuffer: [UUID: String] = [:]
    private var flushTask: Task<Void, Never>?
    private let flushInterval: UInt64 = 30_000_000 // 30ms

    var activeAgent: Agent? {
        agents.first { $0.id == activeAgentId }
    }

    var activeMessages: [ChatMessage] {
        guard let id = activeAgentId else { return [] }
        return conversations[id]?.flatMap(\.messages) ?? []
    }

    // MARK: - Lifecycle

    func loadData() async {
        do {
            let loaded = try await persistence.loadAgents()
            if loaded.isEmpty {
                agents = [Agent(id: "1", name: "OpenClaw", url: "ws://localhost:18789", status: .disconnected)]
            } else {
                agents = loaded.map { var a = $0; a.status = .disconnected; return a }
            }
            for agent in agents {
                let segments = try await persistence.loadConversations(agentId: agent.id)
                if !segments.isEmpty {
                    conversations[agent.id] = segments
                }
            }
        } catch {
            print("[Mino] Failed to load data: \(error)")
            agents = [Agent(id: "1", name: "OpenClaw", url: "ws://localhost:18789", status: .disconnected)]
        }
        // Auto-select first agent
        if activeAgentId == nil, let first = agents.first {
            activeAgentId = first.id
        }
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
                    arguments: "{ \"path\": \"/Users/robin/Projects/im/Mino/README.md\" }",
                    result: "File contents loaded (128 lines)",
                    status: .completed
                )
            ),
        ]

        let segment = ConversationSegment(
            id: "mock-session",
            agentId: mockId,
            startDate: Date(),
            messages: messages
        )
        conversations[mockId] = [segment]
    }

    // MARK: - Agent Management

    func addAgent(name: String, url: String) {
        let agent = Agent(id: UUID().uuidString, name: name, url: url, status: .disconnected)
        agents.append(agent)
        activeAgentId = agent.id
        saveAgents()
    }

    func removeAgent(_ agent: Agent) {
        if let client = acpClients.removeValue(forKey: agent.id) {
            Task { await client.disconnect() }
        }
        agents.removeAll { $0.id == agent.id }
        conversations.removeValue(forKey: agent.id)
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

    func sendMessage(_ content: String) async {
        guard let agentId = activeAgentId else { return }

        let userMessage = ChatMessage(role: .user, content: content, type: .text)
        appendMessage(userMessage, to: agentId)

        do {
            try await ensureConnected(agentId: agentId)
        } catch {
            appendMessage(
                ChatMessage(role: .agent, content: "Connection failed: \(error.localizedDescription)", type: .error),
                to: agentId
            )
            return
        }

        guard let client = acpClients[agentId] else { return }

        let streamingId = UUID()
        let placeholder = ChatMessage(
            id: streamingId, role: .agent, content: "", type: .streaming, isStreaming: true
        )
        appendMessage(placeholder, to: agentId)
        isGenerating = true

        // Start stream consumer BEFORE sending message
        streamTask = Task {
            for await update in await client.streamUpdates() {
                guard !Task.isCancelled else { break }
                handleUpdate(update, streamingId: streamingId, agentId: agentId)
            }
        }

        // Auto-inject Content Spec context into the first message after each connection
        let needsInjection = !contentSpecInjected.contains(agentId)
        let actualContent = needsInjection ? contentSpecContext + content : content
        if needsInjection { contentSpecInjected.insert(agentId) }
        print("[Mino] Sending message: injected=\(needsInjection), contentLength=\(actualContent.count)")

        do {
            try await client.sendMessage(actualContent)
        } catch {
            updateMessage(id: streamingId, agentId: agentId) { msg in
                msg.content = "Failed to send: \(error.localizedDescription)"
                msg.type = .error
                msg.isStreaming = false
            }
            isGenerating = false
        }
    }

    func cancelGeneration() {
        guard let agentId = activeAgentId, let client = acpClients[agentId] else { return }
        streamTask?.cancel()
        streamTask = nil
        isGenerating = false
        Task { try? await client.cancelChat() }
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
            print("[Mino] Already connected to \(agentId)")
            return
        }

        guard let agentIdx = agents.firstIndex(where: { $0.id == agentId }) else {
            print("[Mino] Agent not found: \(agentId)")
            return
        }
        agents[agentIdx].status = .connecting
        print("[Mino] Connecting to \(agents[agentIdx].url)...")

        guard let url = URL(string: agents[agentIdx].url) else {
            agents[agentIdx].status = .disconnected
            throw ACPClientError.authFailed
        }

        let credentials = Self.loadOpenClawCredentials()
        print("[Mino] Credentials loaded: deviceId=\(credentials.deviceId != nil), token=\(credentials.token != nil)")

        let client = ACPClient(url: url, credentials: credentials)
        do {
            try await client.connect()
            print("[Mino] Connected successfully!")
        } catch {
            print("[Mino] Connection failed: \(error)")
            agents[agentIdx].status = .disconnected
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
        print("[Mino] Reading credentials from: \(home.path)")
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
            isGenerating = false
            saveConversations(agentId: agentId)

        case .toolCallStart(let info):
            appendMessage(
                ChatMessage(role: .agent, content: "", type: .toolCall, toolCallInfo: info),
                to: agentId
            )

        case .toolCallEnd(let info):
            if let segments = conversations[agentId] {
                for segment in segments {
                    if let msg = segment.messages.last(where: { $0.toolCallInfo?.id == info.id }) {
                        updateMessage(id: msg.id, agentId: agentId) { m in
                            m.toolCallInfo = info
                        }
                    }
                }
            }

        case .thought(let text):
            updateMessage(id: streamingId, agentId: agentId) { msg in
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
            isGenerating = false

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
            isGenerating = false
            saveConversations(agentId: agentId)
        }
    }

    func selectAgent(_ agentId: String) {
        activeAgentId = agentId
        unreadCounts[agentId] = 0
    }

    // MARK: - Private: Text Delta Throttling

    private func scheduleFlush(streamingId: UUID, agentId: String) {
        guard flushTask == nil else { return }
        flushTask = Task {
            try? await Task.sleep(nanoseconds: flushInterval)
            flushPendingText(streamingId: streamingId, agentId: agentId)
        }
    }

    private func flushPendingText(streamingId: UUID, agentId: String) {
        flushTask?.cancel()
        flushTask = nil
        guard let buffered = pendingTextBuffer.removeValue(forKey: streamingId), !buffered.isEmpty else { return }
        updateMessage(id: streamingId, agentId: agentId) { msg in
            msg.content += buffered
        }
    }

    // MARK: - Private: Message Helpers

    private func appendMessage(_ message: ChatMessage, to agentId: String) {
        // Track unread for non-active agents
        if message.role == .agent && agentId != activeAgentId {
            unreadCounts[agentId, default: 0] += 1
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

        // Extract resources
        let extracted = ResourceExtractor.extract(from: message)
        if !extracted.isEmpty {
            resources[agentId, default: []].append(contentsOf: extracted)
        }
    }

    private func updateMessage(id: UUID, agentId: String, transform: (inout ChatMessage) -> Void) {
        guard var segments = conversations[agentId] else { return }
        for i in segments.indices {
            if let j = segments[i].messages.firstIndex(where: { $0.id == id }) {
                transform(&segments[i].messages[j])
                conversations[agentId] = segments
                return
            }
        }
    }

    private func findMessage(id: UUID, agentId: String) -> ChatMessage? {
        conversations[agentId]?.flatMap(\.messages).first { $0.id == id }
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

    // MARK: - Private: Persistence

    private func saveAgents() {
        Task { try? await persistence.saveAgents(agents) }
    }

    private func saveConversations(agentId: String) {
        let segments = conversations[agentId] ?? []
        Task { try? await persistence.saveConversations(agentId: agentId, segments: segments) }
    }
}
