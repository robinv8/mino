import Foundation

enum TransportState {
    case connected
    case disconnected
    case connecting
}

actor ACPTransport {
    private var webSocket: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .default)
    private var pendingRequests: [String: CheckedContinuation<GatewayResponse, Error>] = [:]
    private var eventContinuation: AsyncStream<GatewayEvent>.Continuation?
    private var receiveTask: Task<Void, Never>?
    private var stateContinuation: AsyncStream<TransportState>.Continuation?

    var connectionState: AsyncStream<TransportState> {
        AsyncStream { continuation in
            self.stateContinuation = continuation
        }
    }

    var events: AsyncStream<GatewayEvent> {
        AsyncStream { continuation in
            self.eventContinuation = continuation
        }
    }

    var isConnected: Bool {
        webSocket?.state == .running
    }

    func connect(to url: URL) async throws {
        disconnect()
        stateContinuation?.yield(.connecting)
        let ws = session.webSocketTask(with: url)
        ws.resume()
        webSocket = ws
        stateContinuation?.yield(.connected)
        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    func disconnect() {
        receiveTask?.cancel()
        receiveTask = nil
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        let pending = pendingRequests
        pendingRequests.removeAll()
        for (_, continuation) in pending {
            continuation.resume(throwing: ACPTransportError.disconnected)
        }
        eventContinuation?.finish()
        eventContinuation = nil
        stateContinuation?.yield(.disconnected)
    }

    func sendRequest(method: String, params: [String: Any]) async throws -> GatewayResponse {
        guard let ws = webSocket else {
            throw ACPTransportError.notConnected
        }

        let id = UUID().uuidString
        let frame: [String: Any] = [
            "type": "req",
            "id": id,
            "method": method,
            "params": params
        ]
        let data = try JSONSerialization.data(withJSONObject: frame)

        let response: GatewayResponse = try await withCheckedThrowingContinuation { continuation in
            pendingRequests[id] = continuation
            Task {
                do {
                    try await ws.send(.data(data))
                } catch {
                    if let cont = self.pendingRequests.removeValue(forKey: id) {
                        cont.resume(throwing: error)
                    }
                }
            }
        }

        if let error = response.error, response.ok != true {
            throw error
        }
        return response
    }

    // MARK: - Private

    private func receiveLoop() async {
        guard let ws = webSocket else { return }
        while !Task.isCancelled {
            do {
                let message = try await ws.receive()
                let data: Data
                switch message {
                case .data(let d): data = d
                case .string(let s): data = Data(s.utf8)
                @unknown default: continue
                }
                handleFrame(data)
            } catch {
                stateContinuation?.yield(.disconnected)
                break
            }
        }
    }

    private func handleFrame(_ data: Data) {
        let frame = GatewayFrame.parse(data)
        switch frame {
        case .response(let response):
            if let id = response.id, let continuation = pendingRequests.removeValue(forKey: id) {
                continuation.resume(returning: response)
            }
        case .event(let event):
            eventContinuation?.yield(event)
        case .unknown:
            break
        }
    }
}

enum ACPTransportError: Error, LocalizedError {
    case notConnected
    case disconnected
    case noResult

    var errorDescription: String? {
        switch self {
        case .notConnected: "Not connected to server"
        case .disconnected: "Disconnected from server"
        case .noResult: "No result in response"
        }
    }
}
