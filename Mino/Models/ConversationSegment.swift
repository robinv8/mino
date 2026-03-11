import Foundation

struct ConversationSegment: Identifiable, Codable {
    let id: String  // maps to ACP sessionId
    let agentId: String
    let startDate: Date
    var messages: [ChatMessage]
}
