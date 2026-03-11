import SwiftUI
import MarkdownUI

struct MarkdownContent: View {
    let content: String
    let role: MessageRole

    var body: some View {
        Markdown(processedContent)
            .markdownTheme(minoTheme)
            .markdownImageProvider(LocalImageProvider())
            .textSelection(.enabled)
    }

    private static let imagePathRegex: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: #"(?:^|\s)(\/[\w\-\.\/~]+\.(?:png|jpg|jpeg|gif|webp|bmp|tiff|svg|heic))(?:\s|$)"#,
            options: [.caseInsensitive, .anchorsMatchLines]
        )
    }()

    /// Convert bare local image paths into markdown image syntax
    private var processedContent: String {
        guard let regex = Self.imagePathRegex else { return content }

        let nsContent = content as NSString
        let matches = regex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))
        guard !matches.isEmpty else { return content }

        var result = content

        // Replace in reverse to preserve indices
        for match in matches.reversed() {
            let pathRange = match.range(at: 1)
            let path = nsContent.substring(with: pathRange)

            // Skip if already inside markdown image/link syntax
            if pathRange.location > 1 {
                let before = nsContent.substring(with: NSRange(location: pathRange.location - 2, length: 2))
                if before.hasSuffix("](") || before.hasSuffix("![") { continue }
            }

            // Only convert if file actually exists
            let expandedPath = (path as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expandedPath) {
                let replacement = "\n![image](\(expandedPath))\n"
                result = (result as NSString).replacingCharacters(in: pathRange, with: replacement)
            }
        }

        return result
    }

    private var minoTheme: MarkdownUI.Theme {
        .gitHub
            .text {
                ForegroundColor(role == .user ? .white : .primary)
                FontSize(MinoTheme.bodySize)
            }
            .code {
                FontFamilyVariant(.monospaced)
                FontSize(MinoTheme.codeSize)
                ForegroundColor(role == .user ? .white.opacity(0.9) : Color(hex: 0x7C5CFC))
                BackgroundColor(role == .user ? .white.opacity(0.12) : Color(hex: 0x7C5CFC).opacity(0.08))
            }
            .codeBlock { configuration in
                configuration.label
                    .relativeLineSpacing(.em(0.2))
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(MinoTheme.codeSize)
                        ForegroundColor(.primary)
                    }
                    .padding(12)
                    .background(Color(.controlBackgroundColor).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: MinoTheme.cornerRadiusSmall, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: MinoTheme.cornerRadiusSmall, style: .continuous)
                            .stroke(MinoTheme.border, lineWidth: 0.5)
                    )
            }
            .link {
                ForegroundColor(role == .user ? .white : Color(hex: 0x7C5CFC))
            }
            .heading1 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontWeight(.bold)
                        FontSize(18)
                    }
                    .padding(.bottom, 4)
            }
            .heading2 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(16)
                    }
                    .padding(.bottom, 2)
            }
            .blockquote { configuration in
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(MinoTheme.accent.opacity(0.3))
                        .frame(width: 2.5)
                    configuration.label
                        .markdownTextStyle {
                            ForegroundColor(.secondary)
                            FontStyle(.italic)
                        }
                        .padding(.leading, 10)
                }
            }
    }
}
