import SwiftUI

struct AddAgentView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var url: String = "ws://localhost:3000"
    @State private var agentType: AgentType = .acp
    @State private var workingDirectory: String = ""

    var editingAgent: Agent?

    var body: some View {
        VStack(spacing: 16) {
            Text(editingAgent != nil ? "Edit Agent" : "Add Agent")
                .font(.headline)

            if editingAgent == nil {
                Picker("Type", selection: $agentType) {
                    Text("ACP (WebSocket)").tag(AgentType.acp)
                    Text("Claude Code").tag(AgentType.claudeCode)
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Name")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField(agentType == .claudeCode ? "e.g. My Project" : "e.g. OpenClaw", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            if agentType == .acp {
                VStack(alignment: .leading, spacing: 8) {
                    Text("URL")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField("ws://localhost:3000", text: $url)
                        .textFieldStyle(.roundedBorder)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Working Directory")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack {
                        TextField("/path/to/project", text: $workingDirectory)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse") {
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = false
                            panel.canChooseDirectories = true
                            panel.allowsMultipleSelection = false
                            if panel.runModal() == .OK, let url = panel.url {
                                workingDirectory = url.path
                                if name.isEmpty {
                                    name = url.lastPathComponent
                                }
                            }
                        }
                    }
                }
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(editingAgent != nil ? "Save" : "Add") {
                    if let agent = editingAgent {
                        appState.updateAgent(id: agent.id, name: name, url: url)
                    } else if agentType == .claudeCode {
                        appState.addClaudeCodeAgent(name: name, workingDirectory: workingDirectory)
                    } else {
                        appState.addAgent(name: name, url: url)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            if let agent = editingAgent {
                name = agent.name
                url = agent.url
                agentType = agent.type
                workingDirectory = agent.workingDirectory ?? ""
            }
        }
    }

    private var isValid: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return false }
        if agentType == .acp {
            return !url.trimmingCharacters(in: .whitespaces).isEmpty
        } else {
            return !workingDirectory.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }
}
