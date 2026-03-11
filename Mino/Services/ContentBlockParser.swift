import Foundation

enum ContentBlockParser {

    // MARK: - Parse JSON blocks

    /// 解析 JSON 格式的 blocks 数组
    static func parseJSON(_ data: [String: Any]) -> [ContentBlock]? {
        guard let blocksArray = data["blocks"] as? [[String: Any]] else { return nil }
        var blocks: [ContentBlock] = []
        for blockDict in blocksArray {
            if let block = decodeBlock(blockDict) {
                blocks.append(block)
            }
        }
        return blocks.isEmpty ? nil : blocks
    }

    /// 从单个 dict 解码一个 ContentBlock
    private static func decodeBlock(_ dict: [String: Any]) -> ContentBlock? {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        return try? JSONDecoder().decode(ContentBlock.self, from: jsonData)
    }

    // MARK: - Parse mino-block tags from text

    /// 解析文本中的 <mino-block /> 标签，返回混合的 blocks 列表
    /// 纯文本段 → TextBlock，标签 → 对应 block
    static func parseInlineBlocks(_ text: String) -> [ContentBlock]? {
        // Quick check: 有没有 mino-block 标签
        guard text.contains("<mino-block") else { return nil }

        var blocks: [ContentBlock] = []
        let nsText = text as NSString

        // 匹配 <mino-block type="..." attr="..." /> 或 <mino-block type="..." attr="...">content</mino-block>
        guard let regex = try? NSRegularExpression(
            pattern: #"<mino-block\s+([^>]*?)(?:\/>|>([\s\S]*?)<\/mino-block>)"#,
            options: []
        ) else { return nil }

        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else { return nil }

        var lastEnd = 0
        for match in matches {
            // 标签前的文本 → TextBlock
            let beforeRange = NSRange(location: lastEnd, length: match.range.location - lastEnd)
            if beforeRange.length > 0 {
                let before = nsText.substring(with: beforeRange).trimmingCharacters(in: .whitespacesAndNewlines)
                if !before.isEmpty {
                    blocks.append(.text(TextBlock(content: before)))
                }
            }

            // 解析标签属性
            let attrsString = nsText.substring(with: match.range(at: 1))
            let innerContent = match.numberOfRanges > 2 && match.range(at: 2).location != NSNotFound
                ? nsText.substring(with: match.range(at: 2))
                : nil
            let attrs = parseAttributes(attrsString)

            if let block = buildBlock(from: attrs, innerContent: innerContent) {
                blocks.append(block)
            }

            lastEnd = match.range.location + match.range.length
        }

        // 标签后的剩余文本
        if lastEnd < nsText.length {
            let after = nsText.substring(from: lastEnd).trimmingCharacters(in: .whitespacesAndNewlines)
            if !after.isEmpty {
                blocks.append(.text(TextBlock(content: after)))
            }
        }

        return blocks.isEmpty ? nil : blocks
    }

    // MARK: - Attribute Parsing

    /// 解析 HTML-like 属性: key="value" key='value'
    private static func parseAttributes(_ str: String) -> [String: String] {
        var attrs: [String: String] = [:]
        guard let regex = try? NSRegularExpression(
            pattern: #"(\w+)\s*=\s*(?:"([^"]*)"|'([^']*)')"#,
            options: []
        ) else { return attrs }

        let nsStr = str as NSString
        for match in regex.matches(in: str, range: NSRange(location: 0, length: nsStr.length)) {
            let key = nsStr.substring(with: match.range(at: 1))
            let value: String
            if match.range(at: 2).location != NSNotFound {
                value = nsStr.substring(with: match.range(at: 2))
            } else if match.range(at: 3).location != NSNotFound {
                value = nsStr.substring(with: match.range(at: 3))
            } else {
                continue
            }
            attrs[key] = value
        }
        return attrs
    }

    /// 根据解析出的属性构建对应的 ContentBlock
    private static func buildBlock(from attrs: [String: String], innerContent: String?) -> ContentBlock? {
        guard let type = attrs["type"] else { return nil }

        switch type {
        case "text":
            let content = innerContent ?? attrs["content"] ?? ""
            return .text(TextBlock(content: content))

        case "image":
            guard let url = attrs["url"] else { return nil }
            return .image(ImageBlock(
                url: url,
                caption: attrs["caption"],
                width: attrs["width"].flatMap(Int.init),
                height: attrs["height"].flatMap(Int.init)
            ))

        case "code":
            let content = innerContent ?? attrs["content"] ?? ""
            return .code(CodeBlock(
                content: content,
                language: attrs["language"],
                filename: attrs["filename"],
                startLine: attrs["startLine"].flatMap(Int.init)
            ))

        case "link":
            guard let url = attrs["url"] else { return nil }
            return .link(LinkBlock(
                url: url,
                title: attrs["title"],
                description: attrs["description"],
                image: attrs["image"]
            ))

        case "file":
            guard let path = attrs["path"] else { return nil }
            return .file(FileBlock(
                path: path,
                name: attrs["name"],
                size: attrs["size"].flatMap(Int.init),
                mimeType: attrs["mimeType"]
            ))

        case "table":
            guard let headers = parseJSONArray(attrs["headers"]),
                  let rows = parseJSONMatrix(attrs["rows"]) else { return nil }
            return .table(TableBlock(headers: headers, rows: rows, caption: attrs["caption"]))

        case "action":
            guard let actionsJSON = attrs["actions"],
                  let data = actionsJSON.data(using: .utf8),
                  let actions = try? JSONDecoder().decode([ActionItem].self, from: data) else { return nil }
            return .action(ActionBlock(prompt: attrs["prompt"], actions: actions))

        case "radio":
            guard let options = parseOptions(attrs["options"]) else { return nil }
            return .radio(RadioBlock(label: attrs["label"], options: options, defaultValue: attrs["defaultValue"]))

        case "checkbox":
            guard let options = parseOptions(attrs["options"]) else { return nil }
            let defaults = parseJSONArray(attrs["defaultValues"])
            return .checkbox(CheckboxBlock(label: attrs["label"], options: options, defaultValues: defaults))

        case "dropdown":
            guard let options = parseOptions(attrs["options"]) else { return nil }
            return .dropdown(DropdownBlock(label: attrs["label"], placeholder: attrs["placeholder"], options: options, defaultValue: attrs["defaultValue"]))

        default:
            return .unknown(type)
        }
    }

    // MARK: - JSON Helpers for inline attributes

    private static func parseJSONArray(_ str: String?) -> [String]? {
        guard let str, let data = str.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [String] else { return nil }
        return arr
    }

    private static func parseJSONMatrix(_ str: String?) -> [[String]]? {
        guard let str, let data = str.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String]] else { return nil }
        return arr
    }

    private static func parseOptions(_ str: String?) -> [SelectionOption]? {
        guard let str, let data = str.data(using: .utf8),
              let options = try? JSONDecoder().decode([SelectionOption].self, from: data) else { return nil }
        return options
    }
}
