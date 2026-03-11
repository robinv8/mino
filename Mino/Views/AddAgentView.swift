import SwiftUI

struct AddAgentView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var url: String = "ws://localhost:3000"

    var editingAgent: Agent?

    var body: some View {
        VStack(spacing: 16) {
            Text(editingAgent != nil ? "Edit Agent" : "Add Agent")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Name")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("e.g. OpenClaw", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("URL")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("ws://localhost:3000", text: $url)
                    .textFieldStyle(.roundedBorder)
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
                    } else {
                        appState.addAgent(name: name, url: url)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || url.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            if let agent = editingAgent {
                name = agent.name
                url = agent.url
            }
        }
    }
}
