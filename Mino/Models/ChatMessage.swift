import Foundation

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: MessageRole
    var content: String
    var thinkingContent: String
    var type: MessageType
    let timestamp: Date
    var toolCallInfo: ToolCallInfo?
    var permissionRequest: PermissionRequest?
    var isStreaming: Bool
    var imageURL: String?
    var contentBlocks: [ContentBlock]?

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        thinkingContent: String = "",
        type: MessageType,
        timestamp: Date = Date(),
        toolCallInfo: ToolCallInfo? = nil,
        permissionRequest: PermissionRequest? = nil,
        isStreaming: Bool = false,
        imageURL: String? = nil,
        contentBlocks: [ContentBlock]? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.thinkingContent = thinkingContent
        self.type = type
        self.timestamp = timestamp
        self.toolCallInfo = toolCallInfo
        self.permissionRequest = permissionRequest
        self.isStreaming = isStreaming
        self.imageURL = imageURL
        self.contentBlocks = contentBlocks
    }

    enum CodingKeys: String, CodingKey {
        case id, role, content, thinkingContent, type, timestamp
        case toolCallInfo, permissionRequest, isStreaming, imageURL, contentBlocks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(MessageRole.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        thinkingContent = try container.decodeIfPresent(String.self, forKey: .thinkingContent) ?? ""
        type = try container.decode(MessageType.self, forKey: .type)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        toolCallInfo = try container.decodeIfPresent(ToolCallInfo.self, forKey: .toolCallInfo)
        permissionRequest = try container.decodeIfPresent(PermissionRequest.self, forKey: .permissionRequest)
        isStreaming = try container.decode(Bool.self, forKey: .isStreaming)
        imageURL = try container.decodeIfPresent(String.self, forKey: .imageURL)
        contentBlocks = try container.decodeIfPresent([ContentBlock].self, forKey: .contentBlocks)
    }
}

enum MessageRole: String, Codable {
    case user
    case agent
}

enum MessageType: String, Codable {
    case text
    case streaming
    case toolCall
    case confirmation
    case error
    case image
}
