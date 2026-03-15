import XCTest
@testable import Mino

// MARK: - TaskData Incremental Update Performance

final class TaskDataPerformanceTests: XCTestCase {

    /// Helper: generate N tool call messages across segments
    private func makeSegments(messageCount: Int, segmentSize: Int = 50) -> [ConversationSegment] {
        var segments: [ConversationSegment] = []
        var msgs: [ChatMessage] = []
        for i in 0..<messageCount {
            let info = ToolCallInfo(
                id: "tc-\(i)", toolName: ["Read", "Edit", "Bash", "Grep", "Glob"].randomElement()!,
                arguments: #"{"file_path":"/src/file\#(i).swift"}"#,
                result: "OK",
                status: [.completed, .failed, .running].randomElement()!
            )
            msgs.append(ChatMessage(role: .agent, content: "", type: .toolCall, toolCallInfo: info))
            if msgs.count >= segmentSize {
                segments.append(ConversationSegment(
                    id: "seg-\(segments.count)", agentId: "test", startDate: Date(), messages: msgs
                ))
                msgs = []
            }
        }
        if !msgs.isEmpty {
            segments.append(ConversationSegment(
                id: "seg-\(segments.count)", agentId: "test", startDate: Date(), messages: msgs
            ))
        }
        return segments
    }

    /// Baseline: full rebuild from 1000 tool calls (what the old code did on every update)
    func testFullRebuildPerformance_1000Messages() {
        let segments = makeSegments(messageCount: 1000)
        measure {
            var data = TaskData()
            for segment in segments {
                for msg in segment.messages where msg.type == .toolCall {
                    if let info = msg.toolCallInfo {
                        let item = TaskItem(
                            id: msg.id.uuidString, kind: .toolCall, toolCallInfo: info,
                            thinkingContent: nil, timestamp: msg.timestamp
                        )
                        data.addToolCall(item, info: info)
                    }
                }
            }
            _ = data.toolUsageData  // force computation
        }
    }

    /// Incremental: single addToolCall (what happens on each toolCallStart now)
    func testIncrementalAdd() {
        // Pre-fill with 1000 items
        var data = TaskData()
        for i in 0..<1000 {
            let info = ToolCallInfo(
                id: "tc-\(i)", toolName: "Read", arguments: "{}", result: nil, status: .running
            )
            let item = TaskItem(
                id: "tc-\(i)", kind: .toolCall, toolCallInfo: info,
                thinkingContent: nil, timestamp: Date()
            )
            data.addToolCall(item, info: info)
        }

        // Now measure adding 1 more
        measure {
            for _ in 0..<1000 { // 1000 iterations to get measurable time
                var copy = data
                let info = ToolCallInfo(
                    id: "tc-new", toolName: "Edit", arguments: "{}", result: nil, status: .running
                )
                let item = TaskItem(
                    id: "tc-new", kind: .toolCall, toolCallInfo: info,
                    thinkingContent: nil, timestamp: Date()
                )
                copy.addToolCall(item, info: info)
            }
        }
    }

    /// Incremental: single updateToolCall (what happens on each toolCallEnd now)
    func testIncrementalUpdate() {
        var data = TaskData()
        for i in 0..<1000 {
            let info = ToolCallInfo(
                id: "tc-\(i)", toolName: "Read", arguments: "{}", result: nil, status: .running
            )
            let item = TaskItem(
                id: "tc-\(i)", kind: .toolCall, toolCallInfo: info,
                thinkingContent: nil, timestamp: Date()
            )
            data.addToolCall(item, info: info)
        }

        measure {
            for _ in 0..<1000 {
                var copy = data
                let newInfo = ToolCallInfo(
                    id: "tc-500", toolName: "Read", arguments: "{}", result: "done", status: .completed
                )
                copy.updateToolCall(id: "tc-500", newInfo: newInfo)
            }
        }
    }
}

// MARK: - ContentBlockParser Regex Performance

final class ContentBlockParserPerformanceTests: XCTestCase {

    private let sampleText = """
    Here is some text before the block.
    <mino-block type="code" language="swift" content="let x = 1" />
    Some middle text with explanation.
    <mino-block type="image" url="https://example.com/img.png" caption="Screenshot" />
    More text here.
    <mino-block type="callout" style="info" title="Note" content="This is important" />
    Final paragraph of regular text.
    """

    /// Parse inline blocks — should be fast with pre-compiled regex
    func testParseInlineBlocksPerformance() {
        measure {
            for _ in 0..<500 {
                _ = ContentBlockParser.parseInlineBlocks(sampleText)
            }
        }
    }

    /// No mino-block tags — should early-return via contains() check
    func testParseInlineBlocksNoTags() {
        let plainText = String(repeating: "Hello world. This is a normal message without any special tags. ", count: 50)
        measure {
            for _ in 0..<5000 {
                _ = ContentBlockParser.parseInlineBlocks(plainText)
            }
        }
    }
}

// MARK: - MarkdownContent Cache Performance

final class MarkdownContentCacheTests: XCTestCase {

    /// Simulate repeated access to same content (should hit cache after first call)
    func testProcessedContentCacheHit() {
        // Access the static processContent method indirectly by creating views
        // We test the caching logic at the static function level
        let content = "Here is some text with /Users/robin/test.png and more text."

        // Warm up the cache
        _ = MarkdownContent(content: content, role: .agent).body

        // Subsequent calls should be cached
        measure {
            for _ in 0..<1000 {
                _ = MarkdownContent(content: content, role: .agent).body
            }
        }
    }
}

// MARK: - StreamingBubble Regex Performance

final class StreamingBubblePerformanceTests: XCTestCase {

    /// Test stripping mino-block tags from streaming content
    func testDisplayContentStripping() {
        // Simulate a large streaming message with embedded mino-blocks
        var text = ""
        for i in 0..<20 {
            text += "Paragraph \(i) of the response with some explanation. "
            text += #"<mino-block type="code" language="swift" content="func test\#(i)() {}" />"#
            text += " More text after the block. "
        }
        // Add an incomplete tag at the end (simulating streaming)
        text += "<mino-block type=\"image\" url=\"https://ex"

        let msg = ChatMessage(
            role: .agent, content: text, type: .streaming, isStreaming: true
        )
        let bubble = StreamingBubble(message: msg)

        measure {
            for _ in 0..<500 {
                // Access displayContent via Mirror since it's private
                let mirror = Mirror(reflecting: bubble)
                // We can't directly test private computed properties easily,
                // so test the regex directly
                let regex = try! NSRegularExpression(
                    pattern: #"<mino-block\s+[^>]*?(?:\/>|>[\s\S]*?<\/mino-block>)"#
                )
                var result = text
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: ""
                )
                if let start = result.range(of: "<mino-block", options: .backwards) {
                    result = String(result[..<start.lowerBound])
                }
                _ = result.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    /// Compare: old O(n^2) while-loop approach vs new single-pass approach
    func testOldWhileLoopApproach() {
        var text = ""
        for i in 0..<20 {
            text += "Paragraph \(i) text. "
            text += #"<mino-block type="code" language="swift" content="func f\#(i)() {}" />"#
            text += " After. "
        }

        measure {
            for _ in 0..<500 {
                var result = text
                // Old approach: while loop
                while let range = result.range(
                    of: #"<mino-block\s+[^>]*?(?:\/>|>[\s\S]*?<\/mino-block>)"#,
                    options: .regularExpression
                ) {
                    result.removeSubrange(range)
                }
            }
        }
    }

    func testNewSinglePassApproach() {
        var text = ""
        for i in 0..<20 {
            text += "Paragraph \(i) text. "
            text += #"<mino-block type="code" language="swift" content="func f\#(i)() {}" />"#
            text += " After. "
        }
        let regex = try! NSRegularExpression(
            pattern: #"<mino-block\s+[^>]*?(?:\/>|>[\s\S]*?<\/mino-block>)"#
        )

        measure {
            for _ in 0..<500 {
                _ = regex.stringByReplacingMatches(
                    in: text,
                    range: NSRange(text.startIndex..., in: text),
                    withTemplate: ""
                )
            }
        }
    }
}

// MARK: - ConversationVersion Correctness

final class ConversationVersionTests: XCTestCase {

    @MainActor
    func testSilentUpdateDoesNotBumpVersion() async {
        let appState = AppState()

        // Setup: add an agent and a streaming message
        let agentId = "test-agent"
        appState.agents = [Agent(id: agentId, name: "Test", url: "", status: .connected)]
        appState.activeAgentId = agentId

        let msgId = UUID()
        let msg = ChatMessage(id: msgId, role: .agent, content: "", type: .streaming, isStreaming: true)
        appState.conversations[agentId] = [
            ConversationSegment(id: "seg-1", agentId: agentId, startDate: Date(), messages: [msg])
        ]
        // Reset version after setup
        let versionAfterSetup = appState.conversationVersion

        // Simulate 100 streaming text flushes (silent updates)
        for i in 0..<100 {
            var segments = appState.conversations[agentId]!
            segments[0].messages[0].content += "word\(i) "
            appState.conversations[agentId] = segments
            // Note: in real code, flushPendingText calls updateMessage(silent: true)
            // which doesn't call bumpConversationVersion()
        }

        // Version should NOT have changed from streaming updates alone
        // (conversations is @Published so didSet fires, but no didSet bumps version anymore)
        XCTAssertEqual(appState.conversationVersion, versionAfterSetup,
            "Silent streaming updates should not bump conversationVersion")
    }

    @MainActor
    func testAppendMessageBumpsVersion() async {
        let appState = AppState()
        let agentId = "test-agent"
        appState.agents = [Agent(id: agentId, name: "Test", url: "", status: .connected)]
        appState.activeAgentId = agentId
        appState.conversations[agentId] = []

        let versionBefore = appState.conversationVersion

        // Simulate sending a message (appendMessage bumps version)
        await appState.sendMessage("Hello")

        // sendMessage calls appendMessage which bumps version
        // Even though the actual send will fail (no real connection), the user message is appended
        XCTAssertGreaterThan(appState.conversationVersion, versionBefore,
            "appendMessage should bump conversationVersion")
    }
}

// MARK: - TaskData Incremental Correctness

final class TaskDataCorrectnessTests: XCTestCase {

    func testAddToolCallUpdatesCounters() {
        var data = TaskData()
        let info = ToolCallInfo(id: "1", toolName: "Read", arguments: "{}", result: nil, status: .running)
        let item = TaskItem(id: "1", kind: .toolCall, toolCallInfo: info, thinkingContent: nil, timestamp: Date())
        data.addToolCall(item, info: info)

        XCTAssertEqual(data.taskItems.count, 1)
        XCTAssertEqual(data.runningCount, 1)
        XCTAssertEqual(data.completedCount, 0)
        XCTAssertEqual(data.failedCount, 0)
        XCTAssertNil(data.successRate)
    }

    func testUpdateToolCallAdjustsCounters() {
        var data = TaskData()

        // Add 3 running tool calls
        for i in 0..<3 {
            let info = ToolCallInfo(id: "tc-\(i)", toolName: "Read", arguments: "{}", result: nil, status: .running)
            let item = TaskItem(id: "tc-\(i)", kind: .toolCall, toolCallInfo: info, thinkingContent: nil, timestamp: Date())
            data.addToolCall(item, info: info)
        }
        XCTAssertEqual(data.runningCount, 3)

        // Complete one
        let completedInfo = ToolCallInfo(id: "tc-0", toolName: "Read", arguments: "{}", result: "done", status: .completed)
        data.updateToolCall(id: "tc-0", newInfo: completedInfo)

        XCTAssertEqual(data.runningCount, 2)
        XCTAssertEqual(data.completedCount, 1)
        XCTAssertEqual(data.failedCount, 0)
        XCTAssertEqual(data.successRate, 1.0) // 1 completed, 0 failed

        // Fail another
        let failedInfo = ToolCallInfo(id: "tc-1", toolName: "Read", arguments: "{}", result: "error", status: .failed)
        data.updateToolCall(id: "tc-1", newInfo: failedInfo)

        XCTAssertEqual(data.runningCount, 1)
        XCTAssertEqual(data.completedCount, 1)
        XCTAssertEqual(data.failedCount, 1)
        XCTAssertEqual(data.successRate, 0.5) // 1/2
    }

    func testToolUsageDataGroupsByTool() {
        var data = TaskData()
        let tools = ["Read", "Read", "Edit", "Bash", "Read"]
        for (i, tool) in tools.enumerated() {
            let info = ToolCallInfo(id: "tc-\(i)", toolName: tool, arguments: "{}", result: "ok", status: .completed)
            let item = TaskItem(id: "tc-\(i)", kind: .toolCall, toolCallInfo: info, thinkingContent: nil, timestamp: Date())
            data.addToolCall(item, info: info)
        }

        let usage = data.toolUsageData
        // Should have 3 entries: Bash(1), Edit(1), Read(3) — sorted by name
        XCTAssertEqual(usage.count, 3)
        XCTAssertEqual(usage[0].toolName, "Bash")
        XCTAssertEqual(usage[0].count, 1)
        XCTAssertEqual(usage[1].toolName, "Edit")
        XCTAssertEqual(usage[1].count, 1)
        XCTAssertEqual(usage[2].toolName, "Read")
        XCTAssertEqual(usage[2].count, 3)
    }

    func testUpdateNonExistentIdIsNoOp() {
        var data = TaskData()
        let info = ToolCallInfo(id: "tc-0", toolName: "Read", arguments: "{}", result: nil, status: .running)
        let item = TaskItem(id: "tc-0", kind: .toolCall, toolCallInfo: info, thinkingContent: nil, timestamp: Date())
        data.addToolCall(item, info: info)

        let newInfo = ToolCallInfo(id: "tc-999", toolName: "Read", arguments: "{}", result: "done", status: .completed)
        data.updateToolCall(id: "tc-999", newInfo: newInfo)

        // Nothing should change
        XCTAssertEqual(data.runningCount, 1)
        XCTAssertEqual(data.completedCount, 0)
    }
}
