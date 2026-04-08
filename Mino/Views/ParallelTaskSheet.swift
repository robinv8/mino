import SwiftUI

struct ParallelTaskSheet: View {
    @Environment(AppState.self) var appState
    @Environment(\.dismiss) var dismiss
    @State private var prompt: String = ""
    @State private var selectedAgentIds: Set<String> = []

    private let maxConcurrent = 6

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Dispatch to Agents")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .padding(16)

            Divider()

            // Prompt input
            VStack(alignment: .leading, spacing: 6) {
                Text("Prompt")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                TextEditor(text: $prompt)
                    .font(.system(size: 13))
                    .frame(minHeight: 80, maxHeight: 160)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(.controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(MinoTheme.border, lineWidth: 0.5)
                    )
            }
            .padding(16)

            Divider()

            // Agent selection
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Select Agents")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Select All") {
                        selectedAgentIds = Set(appState.agents.map(\.id))
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(appState.agents) { agent in
                            agentRow(agent)
                        }
                    }
                }
                .frame(maxHeight: 200)

                if selectedAgentIds.count > maxConcurrent {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.system(size: 10))
                        Text("Max \(maxConcurrent) concurrent agents. Only the first \(maxConcurrent) will be dispatched.")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(16)

            Divider()

            // Actions
            HStack {
                Spacer()
                Button("Dispatch") {
                    dispatch()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedAgentIds.isEmpty)
            }
            .padding(16)
        }
        .frame(width: 480)
    }

    private func agentRow(_ agent: Agent) -> some View {
        let isSelected = selectedAgentIds.contains(agent.id)
        let status = appState.activityStatus(for: agent.id)
        let isBusy = appState.generatingAgentIds.contains(agent.id)

        return HStack(spacing: 10) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                .font(.system(size: 14))

            ZStack {
                Circle()
                    .fill(MinoTheme.avatarColor(for: agent.name))
                    .frame(width: 22, height: 22)
                Text(String(agent.name.prefix(1)).uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
            }

            Text(agent.name)
                .font(.system(size: 13))
                .lineLimit(1)

            Spacer()

            if isBusy {
                Text("Busy")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(Capsule())
            } else if case .error = status {
                Text("Error")
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red.opacity(0.1))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? MinoTheme.accentSoft : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelected {
                selectedAgentIds.remove(agent.id)
            } else {
                selectedAgentIds.insert(agent.id)
            }
        }
    }

    private func dispatch() {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let targets = Array(selectedAgentIds.prefix(maxConcurrent))
        dismiss()
        for agentId in targets {
            Task {
                await appState.sendMessageToAgent(trimmed, agentId: agentId)
            }
        }
    }
}
