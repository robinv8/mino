import Foundation

struct ToolCallFormatter {
    struct Summary {
        let icon: String
        let text: String
        /// Optional full path for tooltip display
        let tooltip: String?
    }

    static func summary(toolName: String, arguments: String) -> Summary {
        let args = parseArguments(arguments)

        switch toolName {
        case "Read":
            let path = args["file_path"] ?? ""
            return Summary(icon: "doc.text", text: "Reading \(fileName(from: path))", tooltip: path.isEmpty ? nil : path)

        case "Edit":
            let path = args["file_path"] ?? ""
            return Summary(icon: "pencil", text: "Editing \(fileName(from: path))", tooltip: path.isEmpty ? nil : path)

        case "Write":
            let path = args["file_path"] ?? ""
            return Summary(icon: "doc.badge.plus", text: "Writing \(fileName(from: path))", tooltip: path.isEmpty ? nil : path)

        case "Bash":
            let command = args["command"] ?? ""
            return Summary(icon: "terminal", text: "Running: \(truncate(command, to: 60))", tooltip: command.count > 60 ? command : nil)

        case "Glob":
            let pattern = args["pattern"] ?? ""
            return Summary(icon: "magnifyingglass", text: "Searching files: \(pattern)", tooltip: nil)

        case "Grep":
            let pattern = args["pattern"] ?? ""
            return Summary(icon: "magnifyingglass", text: "Searching content: \(pattern)", tooltip: nil)

        case "WebSearch":
            let query = args["query"] ?? ""
            return Summary(icon: "globe", text: "Searching: \(truncate(query, to: 60))", tooltip: nil)

        case "WebFetch":
            let url = args["url"] ?? ""
            let host = URL(string: url)?.host ?? url
            return Summary(icon: "globe", text: "Fetching: \(host)", tooltip: url.isEmpty ? nil : url)

        case "Agent":
            let desc = args["description"] ?? args["prompt"] ?? ""
            return Summary(icon: "person.2", text: "Agent: \(truncate(desc, to: 60))", tooltip: nil)

        default:
            return Summary(icon: "wrench", text: toolName, tooltip: nil)
        }
    }

    // MARK: - Private

    private static func parseArguments(_ json: String) -> [String: String] {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }
        return dict.compactMapValues { value in
            if let str = value as? String { return str }
            return nil
        }
    }

    private static func fileName(from path: String) -> String {
        guard !path.isEmpty else { return "" }
        return (path as NSString).lastPathComponent
    }

    private static func truncate(_ text: String, to limit: Int) -> String {
        if text.count <= limit { return text }
        return String(text.prefix(limit)) + "…"
    }
}
