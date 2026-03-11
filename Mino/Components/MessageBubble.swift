import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage
    var onPermissionRespond: ((Bool) -> Void)?

    var body: some View {
        switch message.type {
        case .streaming:
            StreamingBubble(message: message)
        case .toolCall:
            ToolCallBubble(message: message)
        case .confirmation:
            ConfirmationBubble(message: message) { granted in
                onPermissionRespond?(granted)
            }
        case .image:
            ImageBubble(message: message)
        case .text, .error:
            standardBubble
        }
    }

    private var standardBubble: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                // Thinking section for agent messages
                if message.role == .agent && !message.thinkingContent.isEmpty {
                    ThinkingSection(content: message.thinkingContent)
                }

                if message.type == .error {
                    errorContent
                } else if let blocks = message.contentBlocks, !blocks.isEmpty {
                    blocksBubble(blocks)
                } else {
                    markdownBubble
                }

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if message.role == .agent { Spacer(minLength: 60) }
        }
    }

    private var markdownBubble: some View {
        Group {
            if message.role == .user {
                MarkdownContent(content: message.content, role: .user)
                    .padding(.horizontal, MinoTheme.bubblePaddingH)
                    .padding(.vertical, MinoTheme.bubblePaddingV)
                    .background(MinoTheme.userBubbleGradient)
                    .clipShape(RoundedRectangle(cornerRadius: MinoTheme.cornerRadius, style: .continuous))
                    .shadow(color: Color(hex: 0x6B4CE6).opacity(0.18), radius: 8, y: 2)
            } else {
                MarkdownContent(content: message.content, role: .agent)
                    .padding(.horizontal, MinoTheme.bubblePaddingH)
                    .padding(.vertical, MinoTheme.bubblePaddingV)
                    .background(MinoTheme.agentBubble)
                    .clipShape(RoundedRectangle(cornerRadius: MinoTheme.cornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: MinoTheme.cornerRadius, style: .continuous)
                            .stroke(MinoTheme.border, lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.04), radius: MinoTheme.bubbleShadowRadius, y: 2)
            }
        }
    }

    private func blocksBubble(_ blocks: [ContentBlock]) -> some View {
        ContentBlocksView(blocks: blocks)
            .padding(.horizontal, MinoTheme.bubblePaddingH)
            .padding(.vertical, MinoTheme.bubblePaddingV)
            .background(MinoTheme.agentBubble)
            .clipShape(RoundedRectangle(cornerRadius: MinoTheme.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MinoTheme.cornerRadius, style: .continuous)
                    .stroke(MinoTheme.border, lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.04), radius: MinoTheme.bubbleShadowRadius, y: 2)
    }

    private var errorContent: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message.content)
        }
        .padding(.horizontal, MinoTheme.bubblePaddingH)
        .padding(.vertical, MinoTheme.bubblePaddingV)
        .background(Color.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: MinoTheme.cornerRadius))
    }
}
