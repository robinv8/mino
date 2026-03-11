import SwiftUI

struct ConfirmationBubble: View {
    let message: ChatMessage
    let onRespond: (Bool) -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Text(message.content)
                    .padding(.horizontal, 14)
                    .padding(.top, 10)

                if let request = message.permissionRequest {
                    if let response = request.response {
                        HStack(spacing: 6) {
                            Image(systemName: response ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(response ? .green : .red)
                            Text(response ? "Allowed" : "Denied")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                    } else {
                        HStack(spacing: 10) {
                            Button("Allow") {
                                onRespond(true)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.purple)
                            .controlSize(.small)

                            Button("Deny") {
                                onRespond(false)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                    }
                }
            }
            .background(MinoTheme.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: MinoTheme.cornerRadiusSmall, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MinoTheme.cornerRadiusSmall, style: .continuous)
                    .stroke(MinoTheme.border, lineWidth: 0.5)
            )

            Spacer(minLength: 60)
        }
    }
}
