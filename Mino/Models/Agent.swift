import Foundation

struct Agent: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var url: String
    var status: ConnectionStatus
    var currentSessionId: String?

    enum CodingKeys: String, CodingKey {
        case id, name, url, status, currentSessionId
    }
}

enum ConnectionStatus: Codable, Hashable {
    case connected
    case disconnected
    case connecting
    case reconnecting(attempt: Int)

    // Custom Codable for backward compatibility
    enum CodingKeys: String, CodingKey {
        case status, attempt
    }

    init(from decoder: Decoder) throws {
        // Try simple string first (backward compat)
        if let container = try? decoder.singleValueContainer(),
           let raw = try? container.decode(String.self) {
            switch raw {
            case "connected": self = .connected
            case "connecting": self = .connecting
            default: self = .disconnected
            }
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let status = try container.decode(String.self, forKey: .status)
        switch status {
        case "connected": self = .connected
        case "connecting": self = .connecting
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
        case .reconnecting(let attempt):
            try container.encode("reconnecting", forKey: .status)
            try container.encode(attempt, forKey: .attempt)
        }
    }
}
