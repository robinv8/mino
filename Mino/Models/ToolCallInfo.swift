import Foundation

struct ToolCallInfo: Identifiable, Codable {
    let id: String
    var toolName: String
    var arguments: String
    var result: String?
    var status: ToolCallStatus
}

enum ToolCallStatus: String, Codable {
    case running
    case completed
    case failed
}

struct PermissionRequest: Identifiable, Codable {
    let id: String
    let description: String
    var response: Bool?
}
