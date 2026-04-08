import SwiftUI

struct CommandView: View {
    @Environment(AppState.self) var appState
    @State private var showingParallelTask = false

    private let columns = [GridItem(.adaptive(minimum: 280), spacing: 16)]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Command Grid")
                    .font(.system(size: 14, weight: .semibold))

                Spacer()

                Button {
                    showingParallelTask = true
                } label: {
                    Label("Dispatch", systemImage: "paperplane")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(appState.agents.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            if appState.agents.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(appState.agents) { agent in
                            AgentCard(agent: agent)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
        .sheet(isPresented: $showingParallelTask) {
            ParallelTaskSheet()
                .environment(appState)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 32))
                .foregroundStyle(.quaternary)
            Text("No agents yet")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Add agents to use the Command Grid")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
