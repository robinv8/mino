import Foundation

enum ResourceExtractor {
    /// Extract resources from a message's content
    static func extract(from message: ChatMessage) -> [ResourceItem] {
        var items: [ResourceItem] = []
        let text = message.content

        // Images from image messages
        if message.type == .image, let url = message.imageURL {
            items.append(ResourceItem(
                category: .image,
                title: text.isEmpty ? "Image" : String(text.prefix(40)),
                content: url,
                sourceMessageId: message.id,
                timestamp: message.timestamp
            ))
        }

        // Markdown images: ![alt](url)
        extractImages(from: text, message: message, into: &items)

        // Code blocks
        extractCodeBlocks(from: text, message: message, into: &items)

        // Links (markdown + bare URLs)
        extractLinks(from: text, message: message, into: &items)

        return items
    }

    private static func extractImages(from text: String, message: ChatMessage, into items: inout [ResourceItem]) {
        // ![alt](url)
        let pattern = /!\[([^\]]*)\]\(([^)]+)\)/
        for match in text.matches(of: pattern) {
            let alt = String(match.output.1)
            let url = String(match.output.2)
            items.append(ResourceItem(
                category: .image,
                title: alt.isEmpty ? "Image" : alt,
                content: url,
                sourceMessageId: message.id,
                timestamp: message.timestamp
            ))
        }
    }

    private static func extractCodeBlocks(from text: String, message: ChatMessage, into items: inout [ResourceItem]) {
        // Use NSRegularExpression for multiline matching
        guard let regex = try? NSRegularExpression(pattern: "```(\\w*)\\n([\\s\\S]*?)```", options: []) else { return }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        for match in matches {
            let lang = match.numberOfRanges > 1 ? nsText.substring(with: match.range(at: 1)) : ""
            let code = match.numberOfRanges > 2 ? nsText.substring(with: match.range(at: 2)) : ""
            let preview = code.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !preview.isEmpty else { continue }

            let title: String
            if lang.isEmpty {
                title = String(preview.prefix(30))
            } else {
                title = "\(lang): \(preview.prefix(24))"
            }

            items.append(ResourceItem(
                category: .code,
                title: title,
                content: code,
                sourceMessageId: message.id,
                timestamp: message.timestamp
            ))
        }
    }

    private static func extractLinks(from text: String, message: ChatMessage, into items: inout [ResourceItem]) {
        // Collect image URLs to exclude
        var imageURLs = Set<String>()
        let imgPattern = /!\[[^\]]*\]\(([^)]+)\)/
        for match in text.matches(of: imgPattern) {
            imageURLs.insert(String(match.output.1))
        }

        // Markdown links: [text](url) — filter out ones preceded by '!'
        let linkPattern = /\[([^\]]+)\]\((https?:\/\/[^)]+)\)/
        var capturedURLs = Set<String>()
        for match in text.matches(of: linkPattern) {
            let matchStart = match.range.lowerBound
            // Check if preceded by '!' (image syntax)
            if matchStart > text.startIndex {
                let prev = text[text.index(before: matchStart)]
                if prev == "!" { continue }
            }
            let linkText = String(match.output.1)
            let url = String(match.output.2)
            guard !imageURLs.contains(url) else { continue }
            capturedURLs.insert(url)
            items.append(ResourceItem(
                category: .link,
                title: linkText,
                content: url,
                sourceMessageId: message.id,
                timestamp: message.timestamp
            ))
        }

        // Bare URLs
        let barePattern = /https?:\/\/[^\s\)>"]+/
        for match in text.matches(of: barePattern) {
            let url = String(match.output)
            if !capturedURLs.contains(url) && !imageURLs.contains(url) {
                let host = URL(string: url)?.host ?? url
                items.append(ResourceItem(
                    category: .link,
                    title: host,
                    content: url,
                    sourceMessageId: message.id,
                    timestamp: message.timestamp
                ))
            }
        }
    }
}
