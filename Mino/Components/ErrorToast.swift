import SwiftUI

struct ErrorToast: View {
    let error: AppError
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 14))

            Text(error.message)
                .font(.system(size: 13))
                .lineLimit(2)
                .foregroundStyle(.primary)

            Spacer()

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        .padding(.horizontal, 20)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
