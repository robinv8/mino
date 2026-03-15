import Foundation

struct ClaudeSessionSummary {
    let sessionId: String
    let filePath: URL
    let modifiedDate: Date
    let fileSize: Int64
}

/// Discovers, indexes, and parses Claude Code local JSONL session files.
class ClaudeSessionLoader {

    /// Resolve the real home directory (bypasses sandbox container).
    private static var realHomeDirectory: URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir))
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    /// Derive the Claude Code project directory for a given working directory.
    /// Rule: `/Users/robin/Projects/Mino` → `-Users-robin-Projects-Mino`
    static func projectDir(for workingDirectory: String) -> URL? {
        let hash = workingDirectory.replacingOccurrences(of: "/", with: "-")
        let dir = realHomeDirectory
            .appendingPathComponent(".claude/projects")
            .appendingPathComponent(hash)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        return dir
    }

    /// List all JSONL sessions in a project directory, sorted by modification date descending.
    static func listSessions(projectDir: URL) -> [ClaudeSessionSummary] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: projectDir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]) else {
            return []
        }
        return files
            .filter { $0.pathExtension == "jsonl" }
            .compactMap { url -> ClaudeSessionSummary? in
                guard let attrs = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                      let modified = attrs.contentModificationDate,
                      let size = attrs.fileSize else { return nil }
                let sessionId = url.deletingPathExtension().lastPathComponent
                return ClaudeSessionSummary(
                    sessionId: sessionId,
                    filePath: url,
                    modifiedDate: modified,
                    fileSize: Int64(size)
                )
            }
            .sorted { $0.modifiedDate > $1.modifiedDate }
    }

    /// Result of initial load: the newest session's tail messages + older session summaries.
    struct LoadResult {
        let segment: ConversationSegment?
        /// How many messages were skipped at the front of the loaded session.
        let skippedMessagesInSession: Int
        /// Older sessions available for on-demand loading (newest-first).
        let olderSessions: [ClaudeSessionSummary]
    }

    /// Load only the tail of the most recent session.
    /// Returns the newest session with its last `tailCount` messages,
    /// plus summaries of all older sessions for on-demand loading.
    static func loadMostRecentSession(
        for workingDirectory: String,
        agentId: String,
        tailCount: Int = 50
    ) -> LoadResult {
        guard let projectDir = projectDir(for: workingDirectory) else {
            return LoadResult(segment: nil, skippedMessagesInSession: 0, olderSessions: [])
        }
        let sessions = listSessions(projectDir: projectDir) // newest-first
        guard let newest = sessions.first else {
            return LoadResult(segment: nil, skippedMessagesInSession: 0, olderSessions: [])
        }
        let olderSessions = Array(sessions.dropFirst())

        let allMessages = loadMessages(from: newest.filePath)
        let skipped = max(0, allMessages.count - tailCount)
        let tailMessages = Array(allMessages.suffix(tailCount))

        guard !tailMessages.isEmpty else {
            return LoadResult(segment: nil, skippedMessagesInSession: 0, olderSessions: olderSessions)
        }

        let segment = ConversationSegment(
            id: newest.sessionId,
            agentId: agentId,
            startDate: newest.modifiedDate,
            messages: tailMessages,
            claudeSessionId: newest.sessionId
        )
        return LoadResult(segment: segment, skippedMessagesInSession: skipped, olderSessions: olderSessions)
    }

    /// Load a full session from a summary, returning a segment.
    static func loadSession(_ summary: ClaudeSessionSummary, agentId: String) -> ConversationSegment? {
        let messages = loadMessages(from: summary.filePath)
        guard !messages.isEmpty else { return nil }
        return ConversationSegment(
            id: summary.sessionId,
            agentId: agentId,
            startDate: summary.modifiedDate,
            messages: messages,
            claudeSessionId: summary.sessionId
        )
    }

    /// Load earlier messages from a session file that were previously skipped.
    /// Returns the next `count` messages before the current offset, and the new remaining count.
    static func loadEarlierMessages(
        from file: URL,
        currentSkipped: Int,
        count: Int = 50
    ) -> (messages: [ChatMessage], newSkipped: Int) {
        let allMessages = loadMessages(from: file)
        guard currentSkipped > 0, !allMessages.isEmpty else {
            return ([], 0)
        }
        let start = max(0, currentSkipped - count)
        let slice = Array(allMessages[start..<currentSkipped])
        return (slice, start)
    }

    /// Parse a JSONL file into ChatMessage array using streaming FileHandle reads.
    static func loadMessages(from file: URL) -> [ChatMessage] {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return [] }
        defer { try? handle.close() }

        var messages: [ChatMessage] = []
        var buffer = Data()
        let chunkSize = 64 * 1024  // 64KB chunks
        let newline = UInt8(0x0A)  // \n

        while true {
            let chunk = handle.readData(ofLength: chunkSize)
            if chunk.isEmpty { break }
            buffer.append(chunk)

            // Process complete lines from buffer
            while let newlineIndex = buffer.firstIndex(of: newline) {
                let lineData = buffer[buffer.startIndex..<newlineIndex]
                buffer = buffer[(newlineIndex + 1)...]

                guard !lineData.isEmpty,
                      let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                      let type = json["type"] as? String else { continue }

                let timestamp = parseTimestamp(json["timestamp"]) ?? Date()
                switch type {
                case "user":
                    if let msg = parseUserEntry(json, timestamp: timestamp) {
                        messages.append(msg)
                    }
                case "assistant":
                    messages.append(contentsOf: parseAssistantEntry(json, timestamp: timestamp))
                default:
                    continue
                }
            }
        }

        // Process any remaining data after last newline
        if !buffer.isEmpty,
           let json = try? JSONSerialization.jsonObject(with: buffer) as? [String: Any],
           let type = json["type"] as? String {
            let timestamp = parseTimestamp(json["timestamp"]) ?? Date()
            switch type {
            case "user":
                if let msg = parseUserEntry(json, timestamp: timestamp) {
                    messages.append(msg)
                }
            case "assistant":
                messages.append(contentsOf: parseAssistantEntry(json, timestamp: timestamp))
            default: break
            }
        }

        return messages
    }

    /// Parse JSONL text (one or more lines) into ChatMessage array.
    /// Reusable for both full-file loading and incremental reads.
    static func parseLines(_ text: String) -> [ChatMessage] {
        var messages: [ChatMessage] = []
        let lines = text.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  let lineData = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }

            guard let type = json["type"] as? String else { continue }
            let timestamp = parseTimestamp(json["timestamp"]) ?? Date()

            switch type {
            case "user":
                if let msg = parseUserEntry(json, timestamp: timestamp) {
                    messages.append(msg)
                }
            case "assistant":
                messages.append(contentsOf: parseAssistantEntry(json, timestamp: timestamp))
            default:
                continue
            }
        }
        return messages
    }

    // MARK: - Private Parsing

    private static let isoFormatterFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoFormatterBasic = ISO8601DateFormatter()

    private static func parseTimestamp(_ value: Any?) -> Date? {
        guard let str = value as? String else { return nil }
        return isoFormatterFractional.date(from: str) ?? isoFormatterBasic.date(from: str)
    }

    private static func parseUserEntry(_ json: [String: Any], timestamp: Date) -> ChatMessage? {
        guard let message = json["message"] as? [String: Any],
              let content = message["content"] else { return nil }

        // Only handle string content (skip tool_result arrays)
        guard let text = content as? String, !text.isEmpty else { return nil }

        return ChatMessage(
            role: .user,
            content: text.trimmingCharacters(in: .whitespacesAndNewlines),
            type: .text,
            timestamp: timestamp
        )
    }

    private static func parseAssistantEntry(_ json: [String: Any], timestamp: Date) -> [ChatMessage] {
        guard let message = json["message"] as? [String: Any],
              let contentArray = message["content"] as? [[String: Any]] else { return [] }

        var results: [ChatMessage] = []
        var thinkingText = ""
        var textParts: [String] = []

        for block in contentArray {
            guard let blockType = block["type"] as? String else { continue }

            switch blockType {
            case "thinking":
                if let thinking = block["thinking"] as? String {
                    thinkingText += thinking
                }

            case "text":
                if let text = block["text"] as? String, !text.isEmpty {
                    textParts.append(text)
                }

            case "tool_use":
                // Flush accumulated text before tool_use
                if !textParts.isEmpty || !thinkingText.isEmpty {
                    let combined = textParts.joined(separator: "\n\n")
                    results.append(ChatMessage(
                        role: .agent,
                        content: combined,
                        thinkingContent: thinkingText,
                        type: .text,
                        timestamp: timestamp
                    ))
                    textParts = []
                    thinkingText = ""
                }

                let toolId = block["id"] as? String ?? UUID().uuidString
                let toolName = block["name"] as? String ?? "unknown"
                let inputDict = block["input"] as? [String: Any]
                let argsString: String
                if let inputDict,
                   let argsData = try? JSONSerialization.data(withJSONObject: inputDict, options: [.sortedKeys]),
                   let argsStr = String(data: argsData, encoding: .utf8) {
                    argsString = argsStr
                } else {
                    argsString = "{}"
                }

                results.append(ChatMessage(
                    role: .agent,
                    content: "",
                    type: .toolCall,
                    timestamp: timestamp,
                    toolCallInfo: ToolCallInfo(
                        id: toolId,
                        toolName: toolName,
                        arguments: argsString,
                        result: nil,
                        status: .completed
                    )
                ))

            default:
                continue
            }
        }

        // Flush remaining text/thinking
        if !textParts.isEmpty || !thinkingText.isEmpty {
            let combined = textParts.joined(separator: "\n\n")
            results.append(ChatMessage(
                role: .agent,
                content: combined,
                thinkingContent: thinkingText,
                type: .text,
                timestamp: timestamp
            ))
        }

        return results
    }
}
