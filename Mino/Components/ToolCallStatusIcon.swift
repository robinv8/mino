import SwiftUI

/// Shared status icon for tool call items — used in ChatView and TaskPanel.
struct ToolCallStatusIcon: View {
    let status: ToolCallStatus
    var size: CGFloat = 11

    var body: some View {
        switch status {
        case .running:
            ProgressView()
                .controlSize(.mini)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: size))
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.system(size: size))
        }
    }
}
