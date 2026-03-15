import SwiftUI

struct ToolCallBubble: View {
    let message: ChatMessage
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack {
            if let info = message.toolCallInfo {
                let formatted = ToolCallFormatter.summary(toolName: info.toolName, arguments: info.arguments)
                let isSelected = appState.selectedToolCallId == message.id.uuidString

                HStack(spacing: 6) {
                    ToolCallStatusIcon(status: info.status, size: 12)
                    Image(systemName: formatted.icon)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text(formatted.text)
                        .font(.caption)
                        .lineLimit(1)
                }
                .help(formatted.tooltip ?? "")
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isSelected ? MinoTheme.accentSoft : MinoTheme.surfaceRaised)
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
            }
            Spacer(minLength: 60)
        }
    }

}
