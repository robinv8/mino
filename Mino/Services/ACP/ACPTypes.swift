import Foundation

// MARK: - OpenClaw Gateway Frame Types

/// Request frame: client → gateway
struct GatewayRequest: Encodable {
    let type = "req"
    let id: String
    let method: String
    let params: [String: AnyCodable]
}

/// Response frame: gateway → client
struct GatewayResponse: Decodable {
    let type: String
    let id: String?
    let ok: Bool?
    let payload: [String: AnyCodable]?
    let error: GatewayError?
}

struct GatewayError: Decodable, Error, CustomStringConvertible {
    let code: String
    let message: String

    var description: String { "\(code): \(message)" }
}

/// Event frame: gateway → client (notifications)
struct GatewayEvent: Decodable {
    let type: String  // "event"
    let event: String
    let payload: [String: AnyCodable]?
    let seq: Int?
}

// MARK: - Frame Discriminator

enum GatewayFrame {
    case response(GatewayResponse)
    case event(GatewayEvent)
    case unknown

    static func parse(_ data: Data) -> GatewayFrame {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return .unknown
        }
        let decoder = JSONDecoder()
        switch type {
        case "res":
            if let resp = try? decoder.decode(GatewayResponse.self, from: data) {
                return .response(resp)
            }
        case "event":
            if let evt = try? decoder.decode(GatewayEvent.self, from: data) {
                return .event(evt)
            }
        default:
            break
        }
        return .unknown
    }
}

// MARK: - SessionUpdate (UI-facing)

enum SessionUpdate {
    case textDelta(String)
    case textComplete(String)
    case toolCallStart(ToolCallInfo)
    case toolCallEnd(ToolCallInfo)
    case thought(String)
    case permissionRequest(PermissionRequest)
    case error(String)
    case lifecycleStart
    case lifecycleEnd
    case image(url: String, caption: String?)
    case contentBlocks([ContentBlock])
}

// MARK: - AnyCodable (lightweight)

struct AnyCodable: Codable, Hashable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        String(describing: lhs.value) == String(describing: rhs.value)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(String(describing: value))
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }

    // Convenience accessors
    var stringValue: String? { value as? String }
    var intValue: Int? { value as? Int }
    var boolValue: Bool? { value as? Bool }
    var dictValue: [String: Any]? { value as? [String: Any] }
    var arrayValue: [Any]? { value as? [Any] }
}
