import SwiftUI

struct ToolCallBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                if let info = message.toolCallInfo {
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 8) {
                            if !info.arguments.isEmpty {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Arguments")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(info.arguments)
                                        .font(.system(.caption, design: .monospaced))
                                        .padding(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(.quaternary)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                            }
                            if let result = info.result {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Result")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(result)
                                        .font(.system(.caption, design: .monospaced))
                                        .padding(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(.quaternary)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                            }
                        }
                        .padding(.top, 4)
                    } label: {
                        HStack(spacing: 6) {
                            statusIcon(info.status)
                            Text(info.toolName)
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(.medium)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(MinoTheme.surfaceRaised)
                    .clipShape(RoundedRectangle(cornerRadius: MinoTheme.cornerRadiusSmall, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: MinoTheme.cornerRadiusSmall, style: .continuous)
                            .stroke(MinoTheme.border, lineWidth: 0.5)
                    )
                }
            }
            Spacer(minLength: 60)
        }
    }

    @ViewBuilder
    private func statusIcon(_ status: ToolCallStatus) -> some View {
        switch status {
        case .running:
            ProgressView()
                .controlSize(.small)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }
}
