import Foundation

enum AgentType: String, Codable {
    case acp
    case claudeCode
}

struct Agent: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var url: String
    var status: ConnectionStatus
    var currentSessionId: String?
    var type: AgentType
    var workingDirectory: String?

    enum CodingKeys: String, CodingKey {
        case id, name, url, status, currentSessionId, type, workingDirectory
    }

    init(id: String, name: String, url: String, status: ConnectionStatus, currentSessionId: String? = nil, type: AgentType = .acp, workingDirectory: String? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.status = status
        self.currentSessionId = currentSessionId
        self.type = type
        self.workingDirectory = workingDirectory
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        url = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
        status = try container.decode(ConnectionStatus.self, forKey: .status)
        currentSessionId = try container.decodeIfPresent(String.self, forKey: .currentSessionId)
        type = try container.decodeIfPresent(AgentType.self, forKey: .type) ?? .acp
        workingDirectory = try container.decodeIfPresent(String.self, forKey: .workingDirectory)
    }
}

enum ConnectionStatus: Codable, Hashable {
    case connected
    case disconnected
    case connecting
    case reconnecting(attempt: Int)
    /// CLI is actively running — Mino should not send messages to avoid conflicts.
    case cliActive

    // Custom Codable for backward compatibility
    enum CodingKeys: String, CodingKey {
        case status, attempt
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(),
           let raw = try? container.decode(String.self) {
            switch raw {
            case "connected": self = .connected
            case "connecting": self = .connecting
            case "cliActive": self = .cliActive
            default: self = .disconnected
            }
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let status = try container.decode(String.self, forKey: .status)
        switch status {
        case "connected": self = .connected
        case "connecting": self = .connecting
        case "cliActive": self = .cliActive
        case "reconnecting":
            let attempt = try container.decodeIfPresent(Int.self, forKey: .attempt) ?? 0
            self = .reconnecting(attempt: attempt)
        default: self = .disconnected
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .connected: try container.encode("connected", forKey: .status)
        case .disconnected: try container.encode("disconnected", forKey: .status)
        case .connecting: try container.encode("connecting", forKey: .status)
        case .cliActive: try container.encode("cliActive", forKey: .status)
        case .reconnecting(let attempt):
            try container.encode("reconnecting", forKey: .status)
            try container.encode(attempt, forKey: .attempt)
        }
    }
}
