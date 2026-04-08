import Foundation

/// High-level client that wraps ClaudeCodeTransport and converts
/// Claude Code events (CCEvent) into the app's unified SessionUpdate stream.
/// Uses plain class + DispatchQueue to avoid actor reentrancy/deadlock issues.
final class ClaudeCodeClient: AgentTransport, @unchecked Sendable {
    let workingDirectory: String
    private(set) var lastSessionId: String?
    private let transport = ClaudeCodeTransport()
    private let queue = DispatchQueue(label: "com.mino.cc-client")
    private var updateContinuation: AsyncStream<SessionUpdate>.Continuation?
    private var consumeTask: Task<Void, Never>?
    private var pendingTools: [String: ToolCallInfo] = [:]

    init(workingDirectory: String) {
        self.workingDirectory = workingDirectory
    }

    /// Send a message to Claude Code and return a SessionUpdate stream.
    /// Each call spawns a new `claude -p` process.
    /// When `resumeSessionId` is provided, passes `--resume` to continue the previous session.
    func sendMessage(_ text: String, resumeSessionId: String? = nil) throws -> AsyncStream<SessionUpdate> {
        queue.sync {
            consumeTask?.cancel()
            updateContinuation?.finish()
            pendingTools.removeAll()
        }

        let (updateStream, continuation) = AsyncStream.makeStream(of: SessionUpdate.self)
        queue.sync { self.updateContinuation = continuation }

        let eventStream = try transport.start(message: text, cwd: workingDirectory, sessionId: resumeSessionId)

        let task = Task { [weak self] in
            for await event in eventStream {
                guard let self, !Task.isCancelled else { break }
                self.handleEvent(event)
            }
            self?.queue.sync {
                self?.updateContinuation?.yield(.lifecycleEnd)
                self?.updateContinuation?.finish()
                self?.updateContinuation = nil
            }
        }
        queue.sync {
            self.consumeTask = task
            self.updateContinuation?.yield(.lifecycleStart)
        }

        return updateStream
    }

    func stopTransport() {
        queue.sync {
            consumeTask?.cancel()
            consumeTask = nil
            updateContinuation?.finish()
            updateContinuation = nil
        }
        transport.stop()
    }

    // MARK: - AgentTransport conformance

    func disconnect() async {
        stopTransport()
    }

    var status: ConnectionStatus {
        get async {
            transport.isRunning ? .connected : .disconnected
        }
    }

    func send(_ message: String, resumeSessionId: String?) async throws -> AsyncStream<SessionUpdate> {
        try sendMessage(message, resumeSessionId: resumeSessionId)
    }

    // MARK: - Event Handling (called from consumeTask, synchronized via queue)

    private func handleEvent(_ event: CCEvent) {
        switch event {
        case .system(let systemEvent):
            if let sid = systemEvent.sessionId, !sid.isEmpty {
                queue.sync {
                    self.lastSessionId = sid
                    updateContinuation?.yield(.systemInfo(model: "", tools: [], sessionId: sid))
                }
            }
            if let model = systemEvent.model, let tools = systemEvent.tools {
                queue.sync {
                    updateContinuation?.yield(.systemInfo(model: model, tools: tools))
                }
            }
        case .assistant(let assistantEvent):
            handleAssistantEvent(assistantEvent)
        case .user(let userEvent):
            handleUserEvent(userEvent)
        case .result(let resultEvent):
            handleResultEvent(resultEvent)
        case .unknown:
            break
        }
    }

    private func handleAssistantEvent(_ event: CCAssistantEvent) {
        for block in event.contentBlocks {
            switch block {
            case .text(let text):
                queue.sync { updateContinuation?.yield(.textDelta(text)) }

            case .toolUse(let id, let name, let input):
                let argsString: String
                if let data = try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys]),
                   let str = String(data: data, encoding: .utf8) {
                    argsString = str
                } else {
                    argsString = ""
                }
                let info = ToolCallInfo(
                    id: id,
                    toolName: name,
                    arguments: argsString,
                    result: nil,
                    status: .running
                )
                queue.sync {
                    pendingTools[id] = info
                    updateContinuation?.yield(.toolCallStart(info))
                }
            }
        }
    }

    private func handleUserEvent(_ event: CCUserEvent) {
        queue.sync {
            for result in event.toolResults {
                if var info = pendingTools[result.toolUseId] {
                    info.result = result.content
                    info.status = result.isError ? .failed : .completed
                    pendingTools.removeValue(forKey: result.toolUseId)
                    updateContinuation?.yield(.toolCallEnd(info))
                } else {
                    let info = ToolCallInfo(
                        id: result.toolUseId,
                        toolName: "unknown",
                        arguments: "",
                        result: result.content,
                        status: result.isError ? .failed : .completed
                    )
                    updateContinuation?.yield(.toolCallEnd(info))
                }
            }
        }
    }

    private func handleResultEvent(_ event: CCResultEvent) {
        queue.sync {
            if event.isError {
                updateContinuation?.yield(.error(event.result))
            }
            if event.durationMs > 0 || event.totalCostUsd > 0 {
                updateContinuation?.yield(.sessionResult(durationMs: event.durationMs, costUsd: event.totalCostUsd))
            }
        }
    }
}
