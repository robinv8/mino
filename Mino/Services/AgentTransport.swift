import Foundation

/// Unified transport protocol for agent communication.
/// Implementations: ACPClient (WebSocket) and ClaudeCodeClient (subprocess).
protocol AgentTransport: AnyObject, Sendable {
    /// Send a message and receive a stream of updates.
    /// For ACP: sends over WebSocket. For Claude Code: spawns a new process.
    func send(_ message: String, resumeSessionId: String?) async throws -> AsyncStream<SessionUpdate>

    /// Disconnect / stop the transport.
    func disconnect() async

    /// Current connection status.
    var status: ConnectionStatus { get async }
}

extension AgentTransport {
    func send(_ message: String) async throws -> AsyncStream<SessionUpdate> {
        try await send(message, resumeSessionId: nil)
    }
}
