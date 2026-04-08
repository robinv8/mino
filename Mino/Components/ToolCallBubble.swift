import SwiftUI

struct ToolCallBubble: View {
    let message: ChatMessage
    @Environment(AppState.self) var appState

    private var isDiffTool: Bool {
        guard let info = message.toolCallInfo else { return false }
        return info.toolName == "Edit" || info.toolName == "Write"
    }

    private var isBashTool: Bool {
        message.toolCallInfo?.toolName == "Bash"
    }

    var body: some View {
        HStack {
            if let info = message.toolCallInfo {
                let formatted = ToolCallFormatter.summary(toolName: info.toolName, arguments: info.arguments)
                let isSelected = appState.selectedToolCallId == message.id.uuidString

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        ToolCallStatusIcon(status: info.status, size: 12)
                        Image(systemName: formatted.icon)
                            .foregroundStyle(.secondary)
                            .font(.system(size: 11))
                        Text(formatted.text)
                            .font(.system(size: 11))
                            .lineLimit(1)
                    }
                    .help(formatted.tooltip ?? "")
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isSelected ? MinoTheme.accentSoft : Color.primary.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: MinoTheme.cornerRadiusSmall, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: MinoTheme.cornerRadiusSmall, style: .continuous)
                            .stroke(isSelected ? MinoTheme.accent.opacity(0.3) : MinoTheme.border, lineWidth: 0.5)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            appState.selectedToolCallId = message.id.uuidString
                            if !appState.isTaskPanelVisible {
                                appState.isTaskPanelVisible = true
                            }
                        }
                    }

                    // Inline diff for Edit/Write tools
                    if isDiffTool && info.status != .running {
                        DiffView(toolName: info.toolName, arguments: info.arguments)
                            .frame(maxWidth: 600)
                    }

                    // Terminal output for Bash tool
                    if isBashTool, let result = info.result, !result.isEmpty, info.status != .running {
                        TerminalOutputView(output: result)
                            .frame(maxWidth: 600)
                    }
                }
            }
            Spacer(minLength: 60)
        }
    }
}
