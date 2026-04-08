import SwiftUI
import MarkdownUI

struct MarkdownContent: View {
    let content: String
    let role: MessageRole

    var body: some View {
        Markdown(Self.processContent(content))
            .markdownTheme(minoTheme)
            .markdownImageProvider(LocalImageProvider())
            .textSelection(.enabled)
    }

    // MARK: - Content Processing (cached)

    /// LRU-style cache for processed content. Avoids repeated regex + FileManager.fileExists().
    private static var contentCache: [String: String] = [:]
    private static let maxCacheSize = 200

    private static let imagePathRegex: NSRegularExpression? = {
        try? NSRegularExpression(
            pattern: #"(?:^|\s)(\/[\w\-\.\/~]+\.(?:png|jpg|jpeg|gif|webp|bmp|tiff|svg|heic))(?:\s|$)"#,
            options: [.caseInsensitive, .anchorsMatchLines]
        )
    }()

    /// Convert bare local image paths into markdown image syntax (cached).
    private static func processContent(_ content: String) -> String {
        if let cached = contentCache[content] { return cached }

        let result = processContentUncached(content)
        // Evict oldest entries if cache is too large
        if contentCache.count >= maxCacheSize {
            // Simple eviction: clear half the cache
            let keysToRemove = Array(contentCache.keys.prefix(maxCacheSize / 2))
            for key in keysToRemove { contentCache.removeValue(forKey: key) }
        }
        contentCache[content] = result
        return result
    }

    private static func processContentUncached(_ content: String) -> String {
        guard let regex = imagePathRegex else { return content }

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
                ForegroundColor(role == .user ? .white.opacity(0.9) : .primary)
                BackgroundColor(role == .user ? .white.opacity(0.12) : Color.primary.opacity(0.04))
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
                    .background(Color.primary.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: MinoTheme.cornerRadiusSmall, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: MinoTheme.cornerRadiusSmall, style: .continuous)
                            .stroke(MinoTheme.border, lineWidth: 0.5)
                    )
            }
            .link {
                ForegroundColor(role == .user ? .white : Color.accentColor)
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
                        .fill(Color.primary.opacity(0.15))
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
