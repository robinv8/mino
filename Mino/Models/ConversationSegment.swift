import Foundation

struct ConversationSegment: Identifiable, Codable {
    let id: String  // maps to ACP sessionId
    let agentId: String
    let startDate: Date
    var messages: [ChatMessage]
    /// Claude Code session ID for `--resume`. Only set after receiving a system event from Claude CLI.
    var claudeSessionId: String?
}
