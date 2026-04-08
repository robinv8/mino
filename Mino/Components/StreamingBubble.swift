import SwiftUI

struct StreamingBubble: View {
    let message: ChatMessage
    @State private var showCursor = true

    // Pre-compiled regex for stripping mino-block tags during streaming
    private static let minoBlockStripRegex: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: #"<mino-block\s+[^>]*?(?:\/>|>[\s\S]*?<\/mino-block>)"#,
            options: []
        )
    }()

    /// Strip incomplete or complete <mino-block> tags from streaming text
    private var displayContent: String {
        var text = message.content
        // Remove all complete <mino-block> tags in a single pass
        if let regex = Self.minoBlockStripRegex {
            text = regex.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: ""
            )
        }
        // Remove any incomplete <mino-block tag being built at the end
        if let start = text.range(of: "<mino-block", options: .backwards) {
            text = String(text[..<start.lowerBound])
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                // Thinking section
                if !message.thinkingContent.isEmpty {
                    ThinkingSection(
                        content: message.thinkingContent,
                        isStreaming: message.isStreaming && message.content.isEmpty
                    )
                }

                // Content
                HStack(alignment: .bottom, spacing: 0) {
                    if message.content.isEmpty && message.thinkingContent.isEmpty {
                        Text("Thinking...")
                            .foregroundStyle(.secondary)
                            .italic()
                    } else if message.content.isEmpty {
                        EmptyView()
                    } else if message.isStreaming {
                        let clean = displayContent
                        if !clean.isEmpty {
                            Text(clean)
                        }
                    } else {
                        MarkdownContent(content: message.content, role: .agent)
                    }

                    if message.isStreaming && !message.content.isEmpty {
                        Rectangle()
                            .fill(Color.primary.opacity(0.4))
                            .frame(width: 1, height: 16)
                            .opacity(showCursor ? 1 : 0)
                    }
                }
                .padding(.horizontal, MinoTheme.bubblePaddingH)
                .padding(.vertical, MinoTheme.bubblePaddingV)

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 60)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5).repeatForever()) {
                showCursor.toggle()
            }
        }
    }
}
