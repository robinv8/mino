import Foundation

// MARK: - Claude Code stream-json Event Models

/// Top-level event from Claude Code's `--output-format stream-json` output.
/// Each line of stdout is a JSON object with a "type" field.
enum CCEvent {
    case system(CCSystemEvent)
    case assistant(CCAssistantEvent)
    case user(CCUserEvent)
    case result(CCResultEvent)
    case unknown

    static func parse(_ data: Data) -> CCEvent {
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = dict["type"] as? String else {
            return .unknown
        }

        switch type {
        case "system":
            return .system(CCSystemEvent(from: dict))
        case "assistant":
            return .assistant(CCAssistantEvent(from: dict))
        case "user":
            return .user(CCUserEvent(from: dict))
        case "result":
            return .result(CCResultEvent(from: dict))
        default:
            return .unknown
        }
    }
}

// MARK: - System Event

struct CCSystemEvent {
    let subtype: String
    let cwd: String?
    let sessionId: String?
    let tools: [String]?
    let model: String?

    init(from dict: [String: Any]) {
        self.subtype = dict["subtype"] as? String ?? ""
        self.cwd = dict["cwd"] as? String
        self.sessionId = dict["session_id"] as? String
        self.tools = dict["tools"] as? [String]
        self.model = dict["model"] as? String
    }
}

// MARK: - Assistant Event

struct CCAssistantEvent {
    let sessionId: String
    let contentBlocks: [CCContentBlock]

    init(from dict: [String: Any]) {
        self.sessionId = dict["session_id"] as? String ?? ""

        var blocks: [CCContentBlock] = []
        if let message = dict["message"] as? [String: Any],
           let content = message["content"] as? [[String: Any]] {
            for item in content {
                if let block = CCContentBlock.parse(item) {
                    blocks.append(block)
                }
            }
        }
        self.contentBlocks = blocks
    }
}

// MARK: - Content Block (inside assistant message)

enum CCContentBlock {
    case text(String)
    case toolUse(id: String, name: String, input: [String: Any])

    static func parse(_ dict: [String: Any]) -> CCContentBlock? {
        guard let type = dict["type"] as? String else { return nil }

        switch type {
        case "text":
            guard let text = dict["text"] as? String else { return nil }
            return .text(text)
        case "tool_use":
            let id = dict["id"] as? String ?? UUID().uuidString
            let name = dict["name"] as? String ?? "unknown"
            let input = dict["input"] as? [String: Any] ?? [:]
            return .toolUse(id: id, name: name, input: input)
        default:
            return nil
        }
    }
}

// MARK: - User Event (tool results)

struct CCUserEvent {
    let sessionId: String
    let toolResults: [CCToolResult]

    init(from dict: [String: Any]) {
        self.sessionId = dict["session_id"] as? String ?? ""

        var results: [CCToolResult] = []
        if let message = dict["message"] as? [String: Any],
           let content = message["content"] as? [[String: Any]] {
            for item in content {
                if let result = CCToolResult.parse(item) {
                    results.append(result)
                }
            }
        }
        // Also check top-level tool_use_result
        if let toolResult = dict["tool_use_result"] as? [String: Any],
           let result = CCToolResult.parse(toolResult) {
            results.append(result)
        }
        self.toolResults = results
    }
}

struct CCToolResult {
    let toolUseId: String
    let content: String
    let isError: Bool

    static func parse(_ dict: [String: Any]) -> CCToolResult? {
        guard dict["type"] as? String == "tool_result" else { return nil }
        let id = dict["tool_use_id"] as? String ?? ""
        let content: String
        if let text = dict["content"] as? String {
            content = text
        } else if let contentArray = dict["content"] as? [[String: Any]] {
            // Sometimes content is an array of {type: "text", text: "..."}
            content = contentArray.compactMap { $0["text"] as? String }.joined(separator: "\n")
        } else {
            content = ""
        }
        let isError = dict["is_error"] as? Bool ?? false
        return CCToolResult(toolUseId: id, content: content, isError: isError)
    }
}

// MARK: - Result Event (session end)

struct CCResultEvent {
    let isError: Bool
    let result: String
    let durationMs: Int
    let totalCostUsd: Double
    let sessionId: String

    init(from dict: [String: Any]) {
        self.isError = dict["is_error"] as? Bool ?? false
        self.result = dict["result"] as? String ?? ""
        self.durationMs = dict["duration_ms"] as? Int ?? 0
        self.totalCostUsd = dict["total_cost_usd"] as? Double ?? 0
        self.sessionId = dict["session_id"] as? String ?? ""
    }
}
