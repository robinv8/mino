import Foundation

struct OpenClawCredentials {
    var deviceId: String?
    var publicKeyPem: String?
    var privateKeyPem: String?
    var token: String?
    var role: String?
    var scopes: [String]?
    var password: String?
}

actor ACPClient {
    private let transport = ACPTransport()
    private let reconnectionManager = ReconnectionManager()
    let serverURL: URL
    let credentials: OpenClawCredentials
    private(set) var sessionKey: String
    private var updateContinuation: AsyncStream<SessionUpdate>.Continuation?
    private var eventTask: Task<Void, Never>?
    private var transportMonitorTask: Task<Void, Never>?
    private var connectionStatusContinuation: AsyncStream<ConnectionStatus>.Continuation?

    init(url: URL, credentials: OpenClawCredentials, sessionKey: String = "agent:main:main") {
        self.serverURL = url
        self.credentials = credentials
        self.sessionKey = sessionKey
    }

    var connectionStatus: AsyncStream<ConnectionStatus> {
        AsyncStream { continuation in
            self.connectionStatusContinuation = continuation
        }
    }

    var isConnected: Bool {
        get async { await transport.isConnected }
    }

    // MARK: - Connection

    func connect() async throws {
        print("[ACP] Connecting to \(serverURL)...")
        connectionStatusContinuation?.yield(.connecting)
        try await transport.connect(to: serverURL)
        print("[ACP] WebSocket connected, waiting for challenge...")

        // Start listening for events
        eventTask = Task { [weak self] in
            guard let self else { return }
            for await event in await transport.events {
                await self.handleEvent(event)
            }
        }

        // Monitor transport state for disconnections
        transportMonitorTask = Task { [weak self] in
            guard let self else { return }
            for await state in await transport.connectionState {
                switch state {
                case .disconnected:
                    await self.handleTransportDisconnect()
                case .connected, .connecting:
                    break
                }
            }
        }

        try await waitForChallenge()
        connectionStatusContinuation?.yield(.connected)
        print("[ACP] Handshake complete!")
    }

    func disconnect() async {
        await reconnectionManager.cancel()
        transportMonitorTask?.cancel()
        transportMonitorTask = nil
        eventTask?.cancel()
        eventTask = nil
        updateContinuation?.finish()
        updateContinuation = nil
        connectionStatusContinuation?.yield(.disconnected)
        connectionStatusContinuation?.finish()
        connectionStatusContinuation = nil
        await transport.disconnect()
    }

    func startReconnection() {
        Task {
            await reconnectionManager.start(
                reconnect: { [weak self] in
                    guard let self else { throw ACPClientError.noActiveSession }
                    try await self.reconnectInternal()
                },
                onAttempt: { [weak self] attempt in
                    Task { @MainActor in
                        // Notify via connection status
                    }
                    Task {
                        await self?.connectionStatusContinuation?.yield(.reconnecting(attempt: attempt))
                    }
                },
                onSuccess: { [weak self] in
                    Task {
                        await self?.connectionStatusContinuation?.yield(.connected)
                    }
                },
                onFailure: { [weak self] in
                    Task {
                        await self?.connectionStatusContinuation?.yield(.disconnected)
                    }
                }
            )
        }
    }

    private func reconnectInternal() async throws {
        eventTask?.cancel()
        transportMonitorTask?.cancel()
        try await transport.connect(to: serverURL)
        eventTask = Task { [weak self] in
            guard let self else { return }
            for await event in await transport.events {
                await self.handleEvent(event)
            }
        }
        transportMonitorTask = Task { [weak self] in
            guard let self else { return }
            for await state in await transport.connectionState {
                if case .disconnected = state {
                    await self.handleTransportDisconnect()
                }
            }
        }
        try await waitForChallenge()
    }

    private func handleTransportDisconnect() {
        connectionStatusContinuation?.yield(.disconnected)
    }

    // MARK: - Chat

    func sendMessage(_ text: String) async throws {
        let _ = try await transport.sendRequest(
            method: "chat.send",
            params: [
                "message": text,
                "sessionKey": sessionKey,
                "idempotencyKey": UUID().uuidString
            ]
        )
    }

    func streamUpdates() -> AsyncStream<SessionUpdate> {
        AsyncStream { continuation in
            self.updateContinuation = continuation
        }
    }

    func cancelChat() async throws {
        let _ = try await transport.sendRequest(
            method: "chat.abort",
            params: ["sessionKey": sessionKey]
        )
    }

    // MARK: - Private: Challenge-Response Handshake

    private var challengeContinuation: CheckedContinuation<Void, Error>?

    private func waitForChallenge() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.challengeContinuation = cont

            // Timeout after 10 seconds
            Task {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if let cont = self.challengeContinuation {
                    self.challengeContinuation = nil
                    cont.resume(throwing: ACPClientError.connectionTimeout)
                }
            }
        }
    }

    private func handleChallenge() async {
        print("[ACP] Challenge received, sending connect request...")

        // 构建 auth 参数：优先密码，fallback token
        var authParams: [String: Any]
        if let password = credentials.password {
            authParams = ["password": password]
            print("[ACP] Using password auth")
        } else if let token = credentials.token {
            authParams = ["token": token]
            print("[ACP] Using token auth")
        } else {
            authParams = [:]
            print("[ACP] Warning: no credentials available")
        }

        let role = credentials.role ?? "operator"
        let scopes = credentials.scopes ?? ["operator.admin"]

        do {
            let response = try await transport.sendRequest(
                method: "connect",
                params: [
                    "minProtocol": 3,
                    "maxProtocol": 3,
                    "client": [
                        "id": "gateway-client",
                        "displayName": "Mino",
                        "version": "0.1.0",
                        "platform": "darwin",
                        "mode": "backend"
                    ] as [String: Any],
                    "caps": ["tool-events"],
                    "auth": authParams,
                    "role": role,
                    "scopes": scopes
                ] as [String: Any]
            )
            if response.ok == true {
                challengeContinuation?.resume()
            } else {
                challengeContinuation?.resume(throwing: ACPClientError.authFailed)
            }
            challengeContinuation = nil
        } catch {
            challengeContinuation?.resume(throwing: error)
            challengeContinuation = nil
        }
    }

    // MARK: - Private: Event Handling

    private func handleEvent(_ event: GatewayEvent) async {
        switch event.event {
        case "connect.challenge":
            await handleChallenge()

        case "agent":
            print("[ACP] agent event: stream=\(event.payload?["stream"]?.stringValue ?? "nil")")
            if let data = event.payload?["data"]?.dictValue {
                let keys = data.keys.joined(separator: ",")
                let phase = data["phase"] as? String
                let delta = data["delta"] as? String
                print("[ACP]   data keys=[\(keys)] phase=\(phase ?? "nil") delta=\(delta?.prefix(50).description ?? "nil")")
            }
            handleAgentEvent(event)

        case "chat":
            print("[ACP] chat event: \(event.payload?.mapValues { $0.stringValue ?? "?" } ?? [:])")
            handleChatEvent(event)

        default:
            if event.event != "tick" && event.event != "health" && event.event != "heartbeat" {
                print("[ACP] event: \(event.event)")
            }
        }
    }

    private func handleAgentEvent(_ event: GatewayEvent) {
        guard let payload = event.payload,
              let stream = payload["stream"]?.stringValue else { return }

        let data = payload["data"]?.dictValue ?? [:]

        switch stream {
        case "text", "assistant":
            if let delta = data["delta"] as? String {
                updateContinuation?.yield(.textDelta(delta))
            }

        case "lifecycle":
            let phase = data["phase"] as? String ?? ""
            switch phase {
            case "start":
                updateContinuation?.yield(.lifecycleStart)
            case "end", "done":
                updateContinuation?.yield(.lifecycleEnd)
            default:
                break
            }

        case "thinking", "thought":
            if let delta = data["delta"] as? String {
                updateContinuation?.yield(.thought(delta))
            }

        case "tool":
            let name = data["name"] as? String ?? "unknown"
            let toolId = data["toolCallId"] as? String ?? data["id"] as? String ?? UUID().uuidString
            let phase = data["phase"] as? String ?? data["status"] as? String ?? ""
            let isError = data["isError"] as? Bool ?? false

            // Format args: try string first, then serialize dict
            let argsString: String
            if let input = data["input"] as? String {
                argsString = input
            } else if let args = data["args"] as? [String: Any],
                      let jsonData = try? JSONSerialization.data(withJSONObject: args, options: .prettyPrinted),
                      let str = String(data: jsonData, encoding: .utf8) {
                argsString = str
            } else {
                argsString = ""
            }

            let meta = data["meta"] as? String

            print("[ACP] tool event: name=\(name) id=\(toolId) phase=\(phase) isError=\(isError)")

            if phase == "start" {
                updateContinuation?.yield(.toolCallStart(ToolCallInfo(
                    id: toolId, toolName: name,
                    arguments: argsString,
                    result: nil, status: .running
                )))
            } else if phase == "result" || phase == "end" || phase == "done" {
                let toolStatus: ToolCallStatus = isError ? .failed : .completed
                updateContinuation?.yield(.toolCallEnd(ToolCallInfo(
                    id: toolId, toolName: name,
                    arguments: argsString,
                    result: meta ?? data["output"] as? String ?? data["result"] as? String,
                    status: toolStatus
                )))
            }

        case "content":
            // Content Spec: structured blocks
            if let blocks = ContentBlockParser.parseJSON(data) {
                updateContinuation?.yield(.contentBlocks(blocks))
            }

        case "image":
            if let url = data["url"] as? String {
                let caption = data["caption"] as? String ?? data["alt"] as? String
                updateContinuation?.yield(.image(url: url, caption: caption))
            } else if let base64 = data["base64"] as? String {
                // Support base64 inline images as data URL
                let mimeType = data["mimeType"] as? String ?? "image/png"
                let dataURL = "data:\(mimeType);base64,\(base64)"
                let caption = data["caption"] as? String ?? data["alt"] as? String
                updateContinuation?.yield(.image(url: dataURL, caption: caption))
            }

        default:
            print("[ACP] unhandled agent stream: \(stream) dataKeys=\(data.keys.sorted()) data=\(data)")
        }
    }

    private func handleChatEvent(_ event: GatewayEvent) {
        guard let payload = event.payload else { return }
        let state = payload["state"]?.stringValue ?? ""

        if state == "final" {
            updateContinuation?.yield(.lifecycleEnd)
        }
    }
}

enum ACPClientError: Error, LocalizedError {
    case noActiveSession
    case authFailed
    case connectionTimeout

    var errorDescription: String? {
        switch self {
        case .noActiveSession: "No active session"
        case .authFailed: "Authentication failed"
        case .connectionTimeout: "Connection timed out"
        }
    }
}
