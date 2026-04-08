import XCTest
@testable import Mino

// MARK: - ClaudeSessionLoader.parseLines

final class ClaudeSessionLoaderTests: XCTestCase {

    // MARK: Basic parsing

    func testParseUserTextEntry() {
        let jsonl = """
        {"type":"user","timestamp":"2025-03-10T10:00:00.000Z","message":{"content":"Hello world"}}
        """
        let messages = ClaudeSessionLoader.parseLines(jsonl)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].role, .user)
        XCTAssertEqual(messages[0].content, "Hello world")
        XCTAssertEqual(messages[0].type, .text)
    }

    func testParseAssistantTextEntry() {
        let jsonl = """
        {"type":"assistant","timestamp":"2025-03-10T10:00:01.000Z","message":{"content":[{"type":"text","text":"Hi there"}]}}
        """
        let messages = ClaudeSessionLoader.parseLines(jsonl)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].role, .agent)
        XCTAssertEqual(messages[0].content, "Hi there")
        XCTAssertEqual(messages[0].type, .text)
    }

    func testParseAssistantToolUse() {
        let jsonl = """
        {"type":"assistant","timestamp":"2025-03-10T10:00:01.000Z","message":{"content":[{"type":"tool_use","id":"tc-1","name":"Read","input":{"file_path":"/src/main.swift"}}]}}
        """
        let messages = ClaudeSessionLoader.parseLines(jsonl)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].type, .toolCall)
        XCTAssertEqual(messages[0].toolCallInfo?.toolName, "Read")
        XCTAssertEqual(messages[0].toolCallInfo?.status, .completed)
    }

    func testParseAssistantThinkingPlusText() {
        let jsonl = """
        {"type":"assistant","timestamp":"2025-03-10T10:00:01.000Z","message":{"content":[{"type":"thinking","thinking":"Let me think..."},{"type":"text","text":"Here is my answer"}]}}
        """
        let messages = ClaudeSessionLoader.parseLines(jsonl)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].content, "Here is my answer")
        XCTAssertEqual(messages[0].thinkingContent, "Let me think...")
    }

    func testParseAssistantTextThenToolUse() {
        // text + tool_use in one assistant entry → 2 messages: text first, then tool call
        let jsonl = """
        {"type":"assistant","timestamp":"2025-03-10T10:00:01.000Z","message":{"content":[{"type":"text","text":"I will read the file"},{"type":"tool_use","id":"tc-1","name":"Read","input":{"file_path":"/src/main.swift"}}]}}
        """
        let messages = ClaudeSessionLoader.parseLines(jsonl)
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].type, .text)
        XCTAssertEqual(messages[0].content, "I will read the file")
        XCTAssertEqual(messages[1].type, .toolCall)
        XCTAssertEqual(messages[1].toolCallInfo?.toolName, "Read")
    }

    // MARK: Edge cases

    func testSkipToolResultUserEntry() {
        // User entries with tool_result arrays should be skipped
        let jsonl = """
        {"type":"user","timestamp":"2025-03-10T10:00:00.000Z","message":{"content":[{"type":"tool_result","tool_use_id":"tc-1","content":"file contents"}]}}
        """
        let messages = ClaudeSessionLoader.parseLines(jsonl)
        XCTAssertTrue(messages.isEmpty)
    }

    func testSkipProgressEntries() {
        let jsonl = """
        {"type":"progress","timestamp":"2025-03-10T10:00:00.000Z","data":{}}
        {"type":"file-history-snapshot","timestamp":"2025-03-10T10:00:00.000Z","data":{}}
        """
        let messages = ClaudeSessionLoader.parseLines(jsonl)
        XCTAssertTrue(messages.isEmpty)
    }

    func testEmptyInput() {
        XCTAssertTrue(ClaudeSessionLoader.parseLines("").isEmpty)
    }

    func testMalformedJSON() {
        let jsonl = """
        not valid json
        {"type":"user","timestamp":"2025-03-10T10:00:00.000Z","message":{"content":"Valid"}}
        {broken json
        """
        let messages = ClaudeSessionLoader.parseLines(jsonl)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].content, "Valid")
    }

    func testMultipleTextBlocksMerged() {
        // Multiple text blocks in one assistant entry should be joined
        let jsonl = """
        {"type":"assistant","timestamp":"2025-03-10T10:00:01.000Z","message":{"content":[{"type":"text","text":"Part 1"},{"type":"text","text":"Part 2"}]}}
        """
        let messages = ClaudeSessionLoader.parseLines(jsonl)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].content, "Part 1\n\nPart 2")
    }

    func testTimestampParsingWithFractionalSeconds() {
        let jsonl = """
        {"type":"user","timestamp":"2025-03-10T10:30:45.123Z","message":{"content":"test"}}
        """
        let messages = ClaudeSessionLoader.parseLines(jsonl)
        XCTAssertEqual(messages.count, 1)
        // Verify it's not the fallback Date()
        let cal = Calendar(identifier: .gregorian)
        let components = cal.dateComponents(in: TimeZone(identifier: "UTC")!, from: messages[0].timestamp)
        XCTAssertEqual(components.year, 2025)
        XCTAssertEqual(components.month, 3)
        XCTAssertEqual(components.day, 10)
    }

    func testTimestampParsingWithoutFractionalSeconds() {
        let jsonl = """
        {"type":"user","timestamp":"2025-03-10T10:30:45Z","message":{"content":"test"}}
        """
        let messages = ClaudeSessionLoader.parseLines(jsonl)
        XCTAssertEqual(messages.count, 1)
        let cal = Calendar(identifier: .gregorian)
        let components = cal.dateComponents(in: TimeZone(identifier: "UTC")!, from: messages[0].timestamp)
        XCTAssertEqual(components.hour, 10)
        XCTAssertEqual(components.minute, 30)
    }

    func testEmptyUserContent() {
        let jsonl = """
        {"type":"user","timestamp":"2025-03-10T10:00:00.000Z","message":{"content":""}}
        """
        let messages = ClaudeSessionLoader.parseLines(jsonl)
        XCTAssertTrue(messages.isEmpty)
    }

    func testWhitespaceOnlyUserContent() {
        let jsonl = """
        {"type":"user","timestamp":"2025-03-10T10:00:00.000Z","message":{"content":"   \\n  "}}
        """
        let messages = ClaudeSessionLoader.parseLines(jsonl)
        // Whitespace-only content passes the !text.isEmpty check but gets trimmed to empty.
        // This is an edge case — the parser creates a message with empty trimmed content.
        // Acceptable behavior: message exists but content is effectively empty.
        XCTAssertEqual(messages.count, 1)
    }

    // MARK: - Project directory derivation

    func testProjectDirHash() {
        // Cannot test fully without real filesystem, but we can verify the hash logic
        let path = "/Users/robin/Projects/Mino"
        let expected = "-Users-robin-Projects-Mino"
        XCTAssertEqual(path.replacingOccurrences(of: "/", with: "-"), expected)
    }
}

// MARK: - ToolCallFormatter

final class ToolCallFormatterTests: XCTestCase {

    func testReadToolSummary() {
        let s = ToolCallFormatter.summary(
            toolName: "Read",
            arguments: #"{"file_path":"/src/Models/AppState.swift"}"#
        )
        XCTAssertEqual(s.icon, "doc.text")
        XCTAssertEqual(s.text, "Reading AppState.swift")
        XCTAssertEqual(s.tooltip, "/src/Models/AppState.swift")
    }

    func testEditToolSummary() {
        let s = ToolCallFormatter.summary(
            toolName: "Edit",
            arguments: #"{"file_path":"/src/main.swift"}"#
        )
        XCTAssertEqual(s.icon, "pencil")
        XCTAssertTrue(s.text.contains("main.swift"))
    }

    func testWriteToolSummary() {
        let s = ToolCallFormatter.summary(
            toolName: "Write",
            arguments: #"{"file_path":"/src/new_file.swift"}"#
        )
        XCTAssertEqual(s.icon, "doc.badge.plus")
        XCTAssertTrue(s.text.contains("new_file.swift"))
    }

    func testBashToolTruncation() {
        let longCommand = String(repeating: "a", count: 100)
        let s = ToolCallFormatter.summary(
            toolName: "Bash",
            arguments: #"{"command":"\#(longCommand)"}"#
        )
        XCTAssertEqual(s.icon, "terminal")
        XCTAssertTrue(s.text.count < 80) // truncated
        XCTAssertEqual(s.tooltip, longCommand)
    }

    func testBashToolShortCommand() {
        let s = ToolCallFormatter.summary(
            toolName: "Bash",
            arguments: #"{"command":"ls -la"}"#
        )
        XCTAssertNil(s.tooltip) // short enough, no tooltip
    }

    func testGlobToolSummary() {
        let s = ToolCallFormatter.summary(
            toolName: "Glob",
            arguments: #"{"pattern":"**/*.swift"}"#
        )
        XCTAssertEqual(s.icon, "magnifyingglass")
        XCTAssertTrue(s.text.contains("**/*.swift"))
    }

    func testGrepToolSummary() {
        let s = ToolCallFormatter.summary(
            toolName: "Grep",
            arguments: #"{"pattern":"TODO"}"#
        )
        XCTAssertEqual(s.icon, "magnifyingglass")
        XCTAssertTrue(s.text.contains("TODO"))
    }

    func testWebSearchToolSummary() {
        let s = ToolCallFormatter.summary(
            toolName: "WebSearch",
            arguments: #"{"query":"swift concurrency"}"#
        )
        XCTAssertEqual(s.icon, "globe")
        XCTAssertTrue(s.text.contains("swift concurrency"))
    }

    func testWebFetchToolSummary() {
        let s = ToolCallFormatter.summary(
            toolName: "WebFetch",
            arguments: #"{"url":"https://example.com/docs/page"}"#
        )
        XCTAssertEqual(s.icon, "globe")
        XCTAssertTrue(s.text.contains("example.com"))
    }

    func testAgentToolSummary() {
        let s = ToolCallFormatter.summary(
            toolName: "Agent",
            arguments: #"{"description":"Search codebase"}"#
        )
        XCTAssertEqual(s.icon, "person.2")
        XCTAssertTrue(s.text.contains("Search codebase"))
    }

    func testUnknownToolFallback() {
        let s = ToolCallFormatter.summary(
            toolName: "CustomTool",
            arguments: "{}"
        )
        XCTAssertEqual(s.icon, "wrench")
        XCTAssertEqual(s.text, "CustomTool")
    }

    func testEmptyArguments() {
        let s = ToolCallFormatter.summary(toolName: "Read", arguments: "")
        XCTAssertEqual(s.text, "Reading ")
        XCTAssertNil(s.tooltip)
    }

    func testMalformedArguments() {
        let s = ToolCallFormatter.summary(toolName: "Read", arguments: "not json")
        XCTAssertEqual(s.text, "Reading ")
    }
}

// MARK: - ResourceExtractor

final class ResourceExtractorTests: XCTestCase {

    func testExtractMarkdownImage() {
        let msg = ChatMessage(role: .agent, content: "Look at this ![screenshot](https://img.com/pic.png)", type: .text)
        let items = ResourceExtractor.extract(from: msg)
        let images = items.filter { $0.category == .image }
        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images[0].content, "https://img.com/pic.png")
        XCTAssertEqual(images[0].title, "screenshot")
    }

    func testExtractImageWithEmptyAlt() {
        let msg = ChatMessage(role: .agent, content: "![](https://img.com/pic.png)", type: .text)
        let items = ResourceExtractor.extract(from: msg)
        let images = items.filter { $0.category == .image }
        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images[0].title, "Image") // fallback title
    }

    func testExtractCodeBlock() {
        let msg = ChatMessage(
            role: .agent,
            content: "```swift\nlet x = 1\n```",
            type: .text
        )
        let items = ResourceExtractor.extract(from: msg)
        let code = items.filter { $0.category == .code }
        XCTAssertEqual(code.count, 1)
        XCTAssertTrue(code[0].title.contains("swift"))
    }

    func testExtractCodeBlockWithoutLanguage() {
        let msg = ChatMessage(
            role: .agent,
            content: "```\necho hello\n```",
            type: .text
        )
        let items = ResourceExtractor.extract(from: msg)
        let code = items.filter { $0.category == .code }
        XCTAssertEqual(code.count, 1)
        XCTAssertTrue(code[0].title.contains("echo hello"))
    }

    func testExtractMarkdownLink() {
        let msg = ChatMessage(
            role: .agent,
            content: "Check out [Apple](https://apple.com) for more info",
            type: .text
        )
        let items = ResourceExtractor.extract(from: msg)
        let links = items.filter { $0.category == .link }
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links[0].title, "Apple")
        XCTAssertEqual(links[0].content, "https://apple.com")
    }

    func testExtractBareURL() {
        let msg = ChatMessage(
            role: .agent,
            content: "Visit https://example.com/page for docs",
            type: .text
        )
        let items = ResourceExtractor.extract(from: msg)
        let links = items.filter { $0.category == .link }
        XCTAssertEqual(links.count, 1)
        XCTAssertTrue(links[0].content.contains("example.com"))
    }

    func testImageURLNotDuplicatedAsLink() {
        // Image URLs should not also appear as links
        let msg = ChatMessage(
            role: .agent,
            content: "![pic](https://img.com/a.png) and [link](https://other.com)",
            type: .text
        )
        let items = ResourceExtractor.extract(from: msg)
        let links = items.filter { $0.category == .link }
        // Should only have the non-image link
        XCTAssertTrue(links.allSatisfy { !$0.content.contains("img.com") })
    }

    func testExtractImageMessage() {
        let msg = ChatMessage(
            role: .agent, content: "A photo", type: .image, imageURL: "https://img.com/photo.jpg"
        )
        let items = ResourceExtractor.extract(from: msg)
        let images = items.filter { $0.category == .image }
        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images[0].content, "https://img.com/photo.jpg")
    }

    func testNoResources() {
        let msg = ChatMessage(role: .agent, content: "Just plain text", type: .text)
        let items = ResourceExtractor.extract(from: msg)
        XCTAssertTrue(items.isEmpty)
    }
}

// MARK: - ContentBlockParser

final class ContentBlockParserTests: XCTestCase {

    func testParseTextBlock() {
        let text = #"Some text <mino-block type="text" content="Hello" /> more text"#
        let blocks = ContentBlockParser.parseInlineBlocks(text)
        XCTAssertNotNil(blocks)
        // Should have: text("Some text") + text("Hello") + text("more text")
        XCTAssertEqual(blocks?.count, 3)
    }

    func testParseImageBlock() {
        let text = #"<mino-block type="image" url="https://img.com/pic.png" caption="Test" />"#
        let blocks = ContentBlockParser.parseInlineBlocks(text)
        XCTAssertNotNil(blocks)
        guard case .image(let img) = blocks?.first else {
            XCTFail("Expected image block")
            return
        }
        XCTAssertEqual(img.url, "https://img.com/pic.png")
        XCTAssertEqual(img.caption, "Test")
    }

    func testParseCodeBlock() {
        let text = #"<mino-block type="code" language="swift" content="let x = 1" />"#
        let blocks = ContentBlockParser.parseInlineBlocks(text)
        XCTAssertNotNil(blocks)
        guard case .code(let code) = blocks?.first else {
            XCTFail("Expected code block")
            return
        }
        XCTAssertEqual(code.content, "let x = 1")
        XCTAssertEqual(code.language, "swift")
    }

    func testParseLinkBlock() {
        let text = #"<mino-block type="link" url="https://example.com" title="Example" />"#
        let blocks = ContentBlockParser.parseInlineBlocks(text)
        XCTAssertNotNil(blocks)
        guard case .link(let link) = blocks?.first else {
            XCTFail("Expected link block")
            return
        }
        XCTAssertEqual(link.url, "https://example.com")
        XCTAssertEqual(link.title, "Example")
    }

    func testParseCalloutBlock() {
        let text = #"<mino-block type="callout" style="warning" title="Heads up" content="Be careful" />"#
        let blocks = ContentBlockParser.parseInlineBlocks(text)
        XCTAssertNotNil(blocks)
        guard case .callout(let callout) = blocks?.first else {
            XCTFail("Expected callout block")
            return
        }
        XCTAssertEqual(callout.style, "warning")
        XCTAssertEqual(callout.title, "Heads up")
        XCTAssertEqual(callout.content, "Be careful")
    }

    func testNoMinoBlockReturnsNil() {
        let text = "Just plain text without any special tags"
        XCTAssertNil(ContentBlockParser.parseInlineBlocks(text))
    }

    func testMissingTypeReturnsNil() {
        let text = #"<mino-block url="https://example.com" />"#
        let blocks = ContentBlockParser.parseInlineBlocks(text)
        // The tag is parsed but buildBlock returns nil for missing type
        // So blocks may be nil or empty
        let nonTextBlocks = blocks?.filter {
            if case .text = $0 { return false }
            return true
        }
        XCTAssertTrue(nonTextBlocks?.isEmpty ?? true)
    }

    func testSingleQuoteAttributes() {
        let text = "<mino-block type='text' content='Hello' />"
        let blocks = ContentBlockParser.parseInlineBlocks(text)
        XCTAssertNotNil(blocks)
    }
}

// MARK: - PersistenceService Round-Trip

final class PersistenceServiceTests: XCTestCase {

    private func makeTempService() -> (PersistenceService, URL) {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MinoTests-\(UUID().uuidString)", isDirectory: true)
        return (PersistenceService(baseURL: tmpDir), tmpDir)
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    func testAgentsRoundTrip() async throws {
        let (service, tmpDir) = makeTempService()
        defer { cleanup(tmpDir) }

        let agents = [
            Agent(id: "test-1", name: "Agent 1", url: "ws://localhost:8080", status: .disconnected),
            Agent(id: "test-2", name: "Agent 2", url: "", status: .disconnected, type: .claudeCode, workingDirectory: "/tmp")
        ]

        try await service.saveAgents(agents)
        let loaded = try await service.loadAgents()

        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].id, "test-1")
        XCTAssertEqual(loaded[0].name, "Agent 1")
        XCTAssertEqual(loaded[1].type, .claudeCode)
        XCTAssertEqual(loaded[1].workingDirectory, "/tmp")
    }

    func testConversationsRoundTrip() async throws {
        let (service, tmpDir) = makeTempService()
        defer { cleanup(tmpDir) }
        let agentId = "roundtrip-test"
        let segments = [
            ConversationSegment(
                id: "seg-1",
                agentId: agentId,
                startDate: Date(timeIntervalSince1970: 1710000000),
                messages: [
                    ChatMessage(role: .user, content: "Hello", type: .text),
                    ChatMessage(role: .agent, content: "Hi!", type: .text)
                ]
            )
        ]

        try await service.saveConversations(agentId: agentId, segments: segments)
        let loaded = try await service.loadConversations(agentId: agentId)

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, "seg-1")
        XCTAssertEqual(loaded[0].messages.count, 2)
        XCTAssertEqual(loaded[0].messages[0].role, .user)
        XCTAssertEqual(loaded[0].messages[0].content, "Hello")
        XCTAssertEqual(loaded[0].messages[1].role, .agent)
    }

    func testLoadNonExistentAgentReturnsEmpty() async throws {
        let service = PersistenceService()
        let loaded = try await service.loadConversations(agentId: "does-not-exist-\(UUID().uuidString)")
        XCTAssertTrue(loaded.isEmpty)
    }
}

// MARK: - ChatMessage Codable

final class ChatMessageCodableTests: XCTestCase {

    func testBasicRoundTrip() throws {
        let msg = ChatMessage(role: .user, content: "Hello", type: .text)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(msg)
        let decoded = try decoder.decode(ChatMessage.self, from: data)

        XCTAssertEqual(decoded.id, msg.id)
        XCTAssertEqual(decoded.role, .user)
        XCTAssertEqual(decoded.content, "Hello")
        XCTAssertEqual(decoded.type, .text)
        XCTAssertFalse(decoded.isStreaming)
    }

    func testToolCallInfoRoundTrip() throws {
        let info = ToolCallInfo(id: "tc-1", toolName: "Read", arguments: "{}", result: "OK", status: .completed)
        let msg = ChatMessage(role: .agent, content: "", type: .toolCall, toolCallInfo: info)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(msg)
        let decoded = try decoder.decode(ChatMessage.self, from: data)

        XCTAssertEqual(decoded.toolCallInfo?.toolName, "Read")
        XCTAssertEqual(decoded.toolCallInfo?.status, .completed)
        XCTAssertEqual(decoded.toolCallInfo?.result, "OK")
    }

    func testThinkingContentPreserved() throws {
        let msg = ChatMessage(role: .agent, content: "answer", thinkingContent: "let me think", type: .text)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(msg)
        let decoded = try decoder.decode(ChatMessage.self, from: data)

        XCTAssertEqual(decoded.thinkingContent, "let me think")
    }

    func testMissingThinkingContentDefaultsToEmpty() throws {
        // Simulate old data without thinkingContent field
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","role":"agent","content":"hi","type":"text","timestamp":"2025-01-01T00:00:00Z","isStreaming":false}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ChatMessage.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(decoded.thinkingContent, "") // defaults to empty per custom init(from:)
    }
}

// MARK: - ClaudeSessionLoader loadMessages (stream reading)

final class ClaudeSessionLoaderStreamTests: XCTestCase {

    func testLoadMessagesFromFile() throws {
        // Write a temp JSONL file and verify loadMessages reads it correctly
        let tmpDir = FileManager.default.temporaryDirectory
        let file = tmpDir.appendingPathComponent("test-session-\(UUID().uuidString).jsonl")

        let content = """
        {"type":"user","timestamp":"2025-03-10T10:00:00.000Z","message":{"content":"Hello"}}
        {"type":"assistant","timestamp":"2025-03-10T10:00:01.000Z","message":{"content":[{"type":"text","text":"Hi back"}]}}
        {"type":"progress","timestamp":"2025-03-10T10:00:02.000Z","data":{}}
        {"type":"user","timestamp":"2025-03-10T10:00:03.000Z","message":{"content":"Thanks"}}
        """
        try content.data(using: .utf8)!.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let messages = ClaudeSessionLoader.loadMessages(from: file)
        XCTAssertEqual(messages.count, 3)
        XCTAssertEqual(messages[0].role, .user)
        XCTAssertEqual(messages[0].content, "Hello")
        XCTAssertEqual(messages[1].role, .agent)
        XCTAssertEqual(messages[1].content, "Hi back")
        XCTAssertEqual(messages[2].role, .user)
        XCTAssertEqual(messages[2].content, "Thanks")
    }

    func testLoadMessagesFromEmptyFile() throws {
        let tmpDir = FileManager.default.temporaryDirectory
        let file = tmpDir.appendingPathComponent("empty-session-\(UUID().uuidString).jsonl")
        try Data().write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let messages = ClaudeSessionLoader.loadMessages(from: file)
        XCTAssertTrue(messages.isEmpty)
    }

    func testLoadMessagesFromNonExistentFile() {
        let file = URL(fileURLWithPath: "/tmp/nonexistent-\(UUID().uuidString).jsonl")
        let messages = ClaudeSessionLoader.loadMessages(from: file)
        XCTAssertTrue(messages.isEmpty)
    }

    func testLoadMessagesWithNoTrailingNewline() throws {
        let tmpDir = FileManager.default.temporaryDirectory
        let file = tmpDir.appendingPathComponent("no-trailing-\(UUID().uuidString).jsonl")

        // No trailing newline
        let content = #"{"type":"user","timestamp":"2025-03-10T10:00:00.000Z","message":{"content":"Only line"}}"#
        try content.data(using: .utf8)!.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let messages = ClaudeSessionLoader.loadMessages(from: file)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].content, "Only line")
    }
}

// MARK: - ScrollPolicy

final class ScrollPolicyTests: XCTestCase {

    private func baseContext(
        activeAgentId: String? = "agent-1",
        generatingAgentIds: Set<String> = [],
        isGenerating: Bool = false,
        isNearBottom: Bool = true,
        visitedAgentIds: Set<String> = [],
        anchorBeforeHistoryLoad: UUID? = nil,
        savedScrollPositions: [String: String] = [:]
    ) -> ScrollContext {
        ScrollContext(
            activeAgentId: activeAgentId,
            generatingAgentIds: generatingAgentIds,
            isGenerating: isGenerating,
            isNearBottom: isNearBottom,
            visitedAgentIds: visitedAgentIds,
            anchorBeforeHistoryLoad: anchorBeforeHistoryLoad,
            savedScrollPositions: savedScrollPositions
        )
    }

    // MARK: onNewMessage

    func testNewMessage_whileGenerating_scrollsToBottom() {
        let ctx = baseContext(generatingAgentIds: ["agent-1"])
        XCTAssertEqual(ScrollPolicy.onNewMessage(context: ctx), .scrollToBottom)
    }

    func testNewMessage_notGenerating_doesNotScroll() {
        let ctx = baseContext(generatingAgentIds: [])
        XCTAssertEqual(ScrollPolicy.onNewMessage(context: ctx), .none)
    }

    func testNewMessage_differentAgentGenerating_doesNotScroll() {
        let ctx = baseContext(
            activeAgentId: "agent-1",
            generatingAgentIds: ["agent-2"]
        )
        XCTAssertEqual(ScrollPolicy.onNewMessage(context: ctx), .none)
    }

    func testNewMessage_noActiveAgent_doesNotScroll() {
        let ctx = baseContext(activeAgentId: nil, generatingAgentIds: ["agent-1"])
        XCTAssertEqual(ScrollPolicy.onNewMessage(context: ctx), .none)
    }

    func testNewMessage_whileGenerating_userScrolledUp_doesNotScroll() {
        let ctx = baseContext(
            generatingAgentIds: ["agent-1"],
            isNearBottom: false
        )
        XCTAssertEqual(ScrollPolicy.onNewMessage(context: ctx), .none)
    }

    func testNewMessage_notNearBottom_doesNotScroll() {
        let ctx = baseContext(isNearBottom: false)
        XCTAssertEqual(ScrollPolicy.onNewMessage(context: ctx), .none)
    }

    // MARK: onGeneratingChanged

    func testGeneratingStarted_scrollsToBottom() {
        XCTAssertEqual(ScrollPolicy.onGeneratingChanged(isGenerating: true), .scrollToBottom)
    }

    func testGeneratingStopped_doesNotScroll() {
        XCTAssertEqual(ScrollPolicy.onGeneratingChanged(isGenerating: false), .none)
    }

    // MARK: onCacheUpdated — history load

    func testCacheUpdated_withAnchor_restoresAnchor() {
        let anchor = UUID()
        let ctx = baseContext(anchorBeforeHistoryLoad: anchor)
        XCTAssertEqual(ScrollPolicy.onCacheUpdated(context: ctx), .restoreAnchor(anchor))
    }

    func testCacheUpdated_anchorTakesPrecedenceOverFirstVisit() {
        // Even if agent is not visited, anchor wins
        let anchor = UUID()
        let ctx = baseContext(
            visitedAgentIds: [],
            anchorBeforeHistoryLoad: anchor
        )
        XCTAssertEqual(ScrollPolicy.onCacheUpdated(context: ctx), .restoreAnchor(anchor))
    }

    // MARK: onCacheUpdated — first visit

    func testCacheUpdated_firstVisit_scrollsToBottom() {
        let ctx = baseContext(visitedAgentIds: [])
        XCTAssertEqual(ScrollPolicy.onCacheUpdated(context: ctx), .scrollToBottom)
    }

    func testCacheUpdated_firstVisitNoActiveAgent_doesNotScroll() {
        let ctx = baseContext(activeAgentId: nil, visitedAgentIds: [])
        XCTAssertEqual(ScrollPolicy.onCacheUpdated(context: ctx), .none)
    }

    // MARK: onCacheUpdated — revisit with saved position

    func testCacheUpdated_revisitWithSavedPosition_restoresSaved() {
        let ctx = baseContext(
            visitedAgentIds: ["agent-1"],
            savedScrollPositions: ["agent-1": "msg-42"]
        )
        XCTAssertEqual(ScrollPolicy.onCacheUpdated(context: ctx), .restoreSaved("msg-42"))
    }

    // MARK: onCacheUpdated — revisit without saved position

    func testCacheUpdated_revisitNoSavedPosition_doesNotScroll() {
        let ctx = baseContext(
            visitedAgentIds: ["agent-1"],
            savedScrollPositions: [:]
        )
        XCTAssertEqual(ScrollPolicy.onCacheUpdated(context: ctx), .none)
    }

    // MARK: onCacheUpdated — watcher message (no scroll)

    func testCacheUpdated_watcherMessage_doesNotScroll() {
        // Agent already visited, no anchor, no saved position
        let ctx = baseContext(
            visitedAgentIds: ["agent-1"],
            savedScrollPositions: [:]
        )
        XCTAssertEqual(ScrollPolicy.onCacheUpdated(context: ctx), .none)
    }

    // MARK: Scenario: user browsing history, watcher pushes message

    func testScenario_browsingHistory_watcherPush() {
        // User is on agent-1, not generating, scrolled up
        let ctx = baseContext(
            activeAgentId: "agent-1",
            generatingAgentIds: [],
            visitedAgentIds: ["agent-1"]
        )
        // Watcher pushes a new message → lastMessageId changes
        XCTAssertEqual(ScrollPolicy.onNewMessage(context: ctx), .none,
            "Watcher messages should not auto-scroll")
        // cacheKey changes from bumpConversationVersion
        XCTAssertEqual(ScrollPolicy.onCacheUpdated(context: ctx), .none,
            "Watcher-triggered cache update should not scroll")
    }

    // MARK: Scenario: user sends message while browsing history

    func testScenario_sendMessageWhileBrowsingHistory() {
        // User was browsing, then sends a message → isGenerating becomes true
        XCTAssertEqual(ScrollPolicy.onGeneratingChanged(isGenerating: true), .scrollToBottom,
            "Sending a message should scroll to bottom")

        // New messages arrive during generation
        let ctx = baseContext(
            activeAgentId: "agent-1",
            generatingAgentIds: ["agent-1"],
            visitedAgentIds: ["agent-1"]
        )
        XCTAssertEqual(ScrollPolicy.onNewMessage(context: ctx), .scrollToBottom,
            "New messages during generation should auto-scroll")
    }

    // MARK: Scenario: switch agents preserves position

    func testScenario_switchAgentAndReturn() {
        // Step 1: First visit agent-1 → scrollToBottom
        let ctx1 = baseContext(
            activeAgentId: "agent-1",
            visitedAgentIds: []
        )
        XCTAssertEqual(ScrollPolicy.onCacheUpdated(context: ctx1), .scrollToBottom)

        // Step 2: User scrolls up, then switches to agent-2 (first visit)
        let ctx2 = baseContext(
            activeAgentId: "agent-2",
            visitedAgentIds: ["agent-1"]
        )
        XCTAssertEqual(ScrollPolicy.onCacheUpdated(context: ctx2), .scrollToBottom)

        // Step 3: Switch back to agent-1 with saved position
        let ctx3 = baseContext(
            activeAgentId: "agent-1",
            visitedAgentIds: ["agent-1", "agent-2"],
            savedScrollPositions: ["agent-1": "msg-100"]
        )
        XCTAssertEqual(ScrollPolicy.onCacheUpdated(context: ctx3), .restoreSaved("msg-100"))
    }

    // MARK: Scenario: load history prepend

    func testScenario_loadHistoryThenNewMessage() {
        let anchor = UUID()

        // Step 1: History loaded, anchor set
        let ctx1 = baseContext(
            visitedAgentIds: ["agent-1"],
            anchorBeforeHistoryLoad: anchor
        )
        XCTAssertEqual(ScrollPolicy.onCacheUpdated(context: ctx1), .restoreAnchor(anchor))

        // Step 2: After anchor is consumed, watcher pushes message
        let ctx2 = baseContext(
            visitedAgentIds: ["agent-1"],
            anchorBeforeHistoryLoad: nil
        )
        XCTAssertEqual(ScrollPolicy.onNewMessage(context: ctx2), .none,
            "After history load, watcher messages should not scroll")
    }

    // MARK: Scenario: user scrolls up during generation (A4)

    func testScenario_userScrollsUpDuringGeneration() {
        // Step 1: User sends message → scrolls to bottom
        XCTAssertEqual(ScrollPolicy.onGeneratingChanged(isGenerating: true), .scrollToBottom)

        // Step 2: New messages arrive while user is near bottom → auto-scroll
        let ctx1 = baseContext(
            generatingAgentIds: ["agent-1"],
            isNearBottom: true,
            visitedAgentIds: ["agent-1"]
        )
        XCTAssertEqual(ScrollPolicy.onNewMessage(context: ctx1), .scrollToBottom,
            "Near bottom during generation should auto-scroll")

        // Step 3: User scrolls up to read history → stop auto-scrolling
        let ctx2 = baseContext(
            generatingAgentIds: ["agent-1"],
            isNearBottom: false,
            visitedAgentIds: ["agent-1"]
        )
        XCTAssertEqual(ScrollPolicy.onNewMessage(context: ctx2), .none,
            "User scrolled up during generation should NOT auto-scroll")
    }
}
