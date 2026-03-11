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
            updateMessage(id: streamingId, agentId: agentId) { msg in
                msg.content += text
            }

        case .textComplete(let text):
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
    [Client Context — Mino Content Spec v0.1]
    This client supports structured content rendering. You can use <mino-block /> tags in your response for richer display:

    Available components:
    - <mino-block type="image" url="path_or_url" caption="..." />
    - <mino-block type="code" language="swift" filename="Example.swift" content="..." />
    - <mino-block type="link" url="..." title="..." description="..." />
    - <mino-block type="file" path="..." name="..." size="1024" mimeType="..." />
    - <mino-block type="table" headers='["A","B"]' rows='[["1","2"]]' caption="..." />
    - <mino-block type="action" prompt="..." actions='[{"id":"ok","label":"OK","style":"primary"}]' />
    - <mino-block type="radio" label="Pick one:" options='[{"id":"a","label":"A"}]' />
    - <mino-block type="checkbox" label="Select:" options='[{"id":"a","label":"A"}]' />
    - <mino-block type="dropdown" label="Choose:" options='[{"id":"a","label":"A"}]' placeholder="..." />

    Use these tags only when structured display genuinely improves the response. Plain text/Markdown is always fine.
    [End Client Context]

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
