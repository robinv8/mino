import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            ComponentsGalleryTab()
                .tabItem {
                    Label("Components", systemImage: "square.grid.2x2")
                }
        }
        .frame(width: 680, height: 560)
    }
}

// MARK: - Components Gallery

private struct ComponentsGalleryTab: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                // 逐个展示每种 block
                sectionCard("text — Rich Text") {
                    ContentBlockView(block: .text(TextBlock(content: "This is **bold**, this is *italic*, and this is `inline code`.\n\n> A blockquote for emphasis.")))
                }

                sectionCard("image — Image") {
                    VStack(alignment: .leading, spacing: 8) {
                        // 用 SwiftUI 生成示例图
                        ZStack {
                            RoundedRectangle(cornerRadius: MinoTheme.cornerRadiusSmall, style: .continuous)
                                .fill(LinearGradient(
                                    colors: [Color(hex: 0x7C5CFC), Color(hex: 0x6B4CE6)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ))
                            VStack(spacing: 6) {
                                Image(systemName: "photo")
                                    .font(.system(size: 28))
                                Text("Image Block")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                        }
                        .frame(height: 140)

                        Text("A sample image with caption")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                sectionCard("code — Code Block") {
                    ContentBlockView(block: .code(CodeBlock(
                        content: "struct ContentBlock: Codable {\n    let type: String\n    let content: String\n}",
                        language: "swift",
                        filename: "ContentBlock.swift",
                        startLine: 1
                    )))
                }

                sectionCard("link — Link Card") {
                    ContentBlockView(block: .link(LinkBlock(
                        url: "https://github.com",
                        title: "GitHub",
                        description: "Where the world builds software."
                    )))
                }

                sectionCard("file — File Reference") {
                    ContentBlockView(block: .file(FileBlock(
                        path: "/Users/robin/Documents/report.pdf",
                        name: "report.pdf",
                        size: 2_048_576,
                        mimeType: "application/pdf"
                    )))
                }

                sectionCard("table — Table") {
                    ContentBlockView(block: .table(TableBlock(
                        headers: ["Component", "Status", "Version"],
                        rows: [
                            ["text", "Supported", "0.1"],
                            ["image", "Supported", "0.1"],
                            ["code", "Supported", "0.1"],
                            ["link", "Supported", "0.1"],
                            ["file", "Supported", "0.1"],
                            ["table", "Supported", "0.1"],
                            ["action", "Supported", "0.1"],
                        ],
                        caption: "Content Spec v0.1 Components"
                    )))
                }

                sectionCard("action — Action Buttons") {
                    ContentBlockView(block: .action(ActionBlock(
                        prompt: "Do you want to apply this change?",
                        actions: [
                            ActionItem(id: "apply", label: "Apply", style: "primary"),
                            ActionItem(id: "reject", label: "Reject", style: "danger"),
                            ActionItem(id: "skip", label: "Skip", style: nil),
                        ]
                    )))
                }

                sectionCard("radio — Single Select") {
                    ContentBlockView(block: .radio(RadioBlock(
                        label: "Select a framework:",
                        options: [
                            SelectionOption(id: "swiftui", label: "SwiftUI", description: "Declarative UI framework"),
                            SelectionOption(id: "uikit", label: "UIKit", description: "Imperative UI framework"),
                            SelectionOption(id: "appkit", label: "AppKit", description: "macOS native framework"),
                        ],
                        defaultValue: "swiftui"
                    )))
                }

                sectionCard("checkbox — Multi Select") {
                    ContentBlockView(block: .checkbox(CheckboxBlock(
                        label: "Select features to enable:",
                        options: [
                            SelectionOption(id: "dark", label: "Dark Mode"),
                            SelectionOption(id: "sync", label: "Cloud Sync"),
                            SelectionOption(id: "notify", label: "Notifications"),
                        ],
                        defaultValues: ["dark"]
                    )))
                }

                sectionCard("dropdown — Dropdown Select") {
                    ContentBlockView(block: .dropdown(DropdownBlock(
                        label: "Choose a language:",
                        placeholder: "Select language...",
                        options: [
                            SelectionOption(id: "swift", label: "Swift"),
                            SelectionOption(id: "python", label: "Python"),
                            SelectionOption(id: "rust", label: "Rust"),
                            SelectionOption(id: "go", label: "Go"),
                        ]
                    )))
                }

                // mino-block 标签示例
                sectionCard("Inline Tag — <mino-block />") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Agent 可在文本中嵌入标签：")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text(#"<mino-block type="image" url="/tmp/chart.png" caption="Revenue" />"#)
                            .font(.system(size: 11, design: .monospaced))
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.03))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }

                specVersion
            }
            .padding(24)
        }
        .background(Color(.windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Content Spec Components")
                .font(.system(size: 16, weight: .bold))
            Text("Mino 当前支持渲染的结构化内容组件预览")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
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

    private var specVersion: some View {
        HStack {
            Spacer()
            Text("Content Spec v0.1 · 10 components")
                .font(.system(size: 10))
                .foregroundStyle(.quaternary)
            Spacer()
        }
        .padding(.top, 8)
    }
}
