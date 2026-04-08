import SwiftUI
import Sparkle

struct SettingsView: View {
    @ObservedObject var updaterViewModel: CheckForUpdatesViewModel

    var body: some View {
        TabView {
            GeneralSettingsTab(updaterViewModel: updaterViewModel)
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            ClaudeCodeSettingsTab()
                .tabItem {
                    Label("Claude Code", systemImage: "terminal")
                }

            AppearanceSettingsTab()
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }

            #if DEBUG
            ComponentsGalleryTab()
                .tabItem {
                    Label("Components", systemImage: "square.grid.2x2")
                }
            #endif
        }
        .frame(width: 520, height: 400)
    }
}

// MARK: - General Settings

private struct GeneralSettingsTab: View {
    @ObservedObject var updaterViewModel: CheckForUpdatesViewModel
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    var body: some View {
        Form {
            Section("Notifications") {
                Toggle("Enable notifications when tasks complete", isOn: $notificationsEnabled)
            }

            Section("Startup") {
                Toggle("Launch Mino at login", isOn: $launchAtLogin)
            }

            Section("About") {
                LabeledContent("Version") {
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Build") {
                    Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Updates") {
                Toggle("Automatically check for updates", isOn: Binding(
                    get: { updaterViewModel.updater.automaticallyChecksForUpdates },
                    set: { updaterViewModel.updater.automaticallyChecksForUpdates = $0 }
                ))

                Button("Check for Updates...") {
                    updaterViewModel.checkForUpdates()
                }
                .disabled(!updaterViewModel.canCheckForUpdates)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Claude Code Settings

private struct ClaudeCodeSettingsTab: View {
    @AppStorage("claudeExecutablePath") private var claudeExecutablePath = ""
    @State private var detectedPath: String = ""

    var body: some View {
        Form {
            Section("Executable Path") {
                TextField("claude binary path", text: $claudeExecutablePath, prompt: Text("Auto-detect"))
                    .textFieldStyle(.roundedBorder)

                if !detectedPath.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 11))
                        Text("Found: \(detectedPath)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Leave empty to auto-detect from PATH. Mino checks ~/.local/bin, /usr/local/bin, and /opt/homebrew/bin.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Section("Permissions") {
                LabeledContent("Mode") {
                    Text("dangerously-skip-permissions")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text("Mino runs Claude Code with --dangerously-skip-permissions for uninterrupted operation.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .task {
            detectClaude()
        }
    }

    private func detectClaude() {
        let paths = [
            "\(NSHomeDirectory())/.local/bin/claude",
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
        ]
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                detectedPath = path
                return
            }
        }
    }
}

// MARK: - Appearance Settings

private struct AppearanceSettingsTab: View {
    @AppStorage("appearance") private var appearance = "system"

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Appearance", selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Components Gallery (Debug only)

#if DEBUG
private struct ComponentsGalleryTab: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Content Spec Components")
                    .font(.system(size: 16, weight: .bold))
                Text("Preview of structured content components supported by Mino")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                sectionCard("text — Rich Text") {
                    ContentBlockView(block: .text(TextBlock(content: "This is **bold**, *italic*, and `code`.")))
                }

                sectionCard("code — Code Block") {
                    ContentBlockView(block: .code(CodeBlock(
                        content: "struct ContentBlock: Codable {\n    let type: String\n}",
                        language: "swift",
                        filename: "ContentBlock.swift",
                        startLine: 1
                    )))
                }

                sectionCard("table — Table") {
                    ContentBlockView(block: .table(TableBlock(
                        headers: ["Component", "Status"],
                        rows: [["text", "OK"], ["code", "OK"], ["table", "OK"]],
                        caption: "Content Spec v0.1"
                    )))
                }
            }
            .padding(24)
        }
        .background(Color(.windowBackgroundColor))
    }

    private func sectionCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(MinoTheme.accent)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(MinoTheme.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: MinoTheme.cornerRadiusSmall, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: MinoTheme.cornerRadiusSmall, style: .continuous)
                        .stroke(MinoTheme.border, lineWidth: 0.5)
                )
        }
    }
}
#endif
