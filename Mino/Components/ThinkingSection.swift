import SwiftUI

struct ThinkingSection: View {
    let content: String
    let isStreaming: Bool
    @State private var isExpanded: Bool

    init(content: String, isStreaming: Bool = false) {
        self.content = content
        self.isStreaming = isStreaming
        self._isExpanded = State(initialValue: isStreaming)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Text(content)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
                .textSelection(.enabled)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(MinoTheme.accent.opacity(0.6))
                Text(isStreaming ? "Thinking..." : "Thought process")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
                if isStreaming {
                    ProgressView()
                        .controlSize(.mini)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(MinoTheme.accentSoft.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: MinoTheme.cornerRadiusSmall, style: .continuous))
        .onChange(of: isStreaming) { _, newValue in
            if newValue {
                isExpanded = true
            }
        }
    }
}
