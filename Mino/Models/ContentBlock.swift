import Foundation

/// Content Spec v0.1 — Structured content blocks
enum ContentBlock: Codable, Identifiable, Hashable {
    case text(TextBlock)
    case image(ImageBlock)
    case code(CodeBlock)
    case link(LinkBlock)
    case file(FileBlock)
    case table(TableBlock)
    case action(ActionBlock)
    case radio(RadioBlock)
    case checkbox(CheckboxBlock)
    case dropdown(DropdownBlock)
    case audio(AudioBlock)
    case video(VideoBlock)
    case callout(CalloutBlock)
    case unknown(String) // Unrecognized type, graceful fallback

    var id: String {
        switch self {
        case .text(let b): b.id
        case .image(let b): b.id
        case .code(let b): b.id
        case .link(let b): b.id
        case .file(let b): b.id
        case .table(let b): b.id
        case .action(let b): b.id
        case .radio(let b): b.id
        case .checkbox(let b): b.id
        case .dropdown(let b): b.id
        case .audio(let b): b.id
        case .video(let b): b.id
        case .callout(let b): b.id
        case .unknown(let t): "unknown-\(t.hashValue)"
        }
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text": self = .text(try TextBlock(from: decoder))
        case "image": self = .image(try ImageBlock(from: decoder))
        case "code": self = .code(try CodeBlock(from: decoder))
        case "link": self = .link(try LinkBlock(from: decoder))
        case "file": self = .file(try FileBlock(from: decoder))
        case "table": self = .table(try TableBlock(from: decoder))
        case "action": self = .action(try ActionBlock(from: decoder))
        case "radio": self = .radio(try RadioBlock(from: decoder))
        case "checkbox": self = .checkbox(try CheckboxBlock(from: decoder))
        case "dropdown": self = .dropdown(try DropdownBlock(from: decoder))
        case "audio": self = .audio(try AudioBlock(from: decoder))
        case "video": self = .video(try VideoBlock(from: decoder))
        case "callout": self = .callout(try CalloutBlock(from: decoder))
        default: self = .unknown(type)
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let b): try b.encode(to: encoder)
        case .image(let b): try b.encode(to: encoder)
        case .code(let b): try b.encode(to: encoder)
        case .link(let b): try b.encode(to: encoder)
        case .file(let b): try b.encode(to: encoder)
        case .table(let b): try b.encode(to: encoder)
        case .action(let b): try b.encode(to: encoder)
        case .radio(let b): try b.encode(to: encoder)
        case .checkbox(let b): try b.encode(to: encoder)
        case .dropdown(let b): try b.encode(to: encoder)
        case .audio(let b): try b.encode(to: encoder)
        case .video(let b): try b.encode(to: encoder)
        case .callout(let b): try b.encode(to: encoder)
        case .unknown: break
        }
    }
}

// MARK: - Block Types

struct TextBlock: Codable, Hashable, Identifiable {
    let id: String
    let content: String

    enum CodingKeys: String, CodingKey { case type, content }
    init(content: String) {
        self.id = UUID().uuidString
        self.content = content
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.content = try c.decode(String.self, forKey: .content)
        self.id = UUID().uuidString
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode("text", forKey: .type)
        try c.encode(content, forKey: .content)
    }
}

struct ImageBlock: Codable, Hashable, Identifiable {
    let id: String
    let url: String
    let caption: String?
    let width: Int?
    let height: Int?

    enum CodingKeys: String, CodingKey { case type, url, caption, width, height }
    init(url: String, caption: String? = nil, width: Int? = nil, height: Int? = nil) {
        self.id = UUID().uuidString
        self.url = url
        self.caption = caption
        self.width = width
        self.height = height
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.url = try c.decode(String.self, forKey: .url)
        self.caption = try c.decodeIfPresent(String.self, forKey: .caption)
        self.width = try c.decodeIfPresent(Int.self, forKey: .width)
        self.height = try c.decodeIfPresent(Int.self, forKey: .height)
        self.id = UUID().uuidString
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode("image", forKey: .type)
        try c.encode(url, forKey: .url)
        try c.encodeIfPresent(caption, forKey: .caption)
        try c.encodeIfPresent(width, forKey: .width)
        try c.encodeIfPresent(height, forKey: .height)
    }
}

struct CodeBlock: Codable, Hashable, Identifiable {
    let id: String
    let content: String
    let language: String?
    let filename: String?
    let startLine: Int?

    enum CodingKeys: String, CodingKey { case type, content, language, filename, startLine }
    init(content: String, language: String? = nil, filename: String? = nil, startLine: Int? = nil) {
        self.id = UUID().uuidString
        self.content = content
        self.language = language
        self.filename = filename
        self.startLine = startLine
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.content = try c.decode(String.self, forKey: .content)
        self.language = try c.decodeIfPresent(String.self, forKey: .language)
        self.filename = try c.decodeIfPresent(String.self, forKey: .filename)
        self.startLine = try c.decodeIfPresent(Int.self, forKey: .startLine)
        self.id = UUID().uuidString
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode("code", forKey: .type)
        try c.encode(content, forKey: .content)
        try c.encodeIfPresent(language, forKey: .language)
        try c.encodeIfPresent(filename, forKey: .filename)
        try c.encodeIfPresent(startLine, forKey: .startLine)
    }
}

struct LinkBlock: Codable, Hashable, Identifiable {
    let id: String
    let url: String
    let title: String?
    let description: String?
    let image: String?

    enum CodingKeys: String, CodingKey { case type, url, title, description, image }
    init(url: String, title: String? = nil, description: String? = nil, image: String? = nil) {
        self.id = UUID().uuidString
        self.url = url
        self.title = title
        self.description = description
        self.image = image
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.url = try c.decode(String.self, forKey: .url)
        self.title = try c.decodeIfPresent(String.self, forKey: .title)
        self.description = try c.decodeIfPresent(String.self, forKey: .description)
        self.image = try c.decodeIfPresent(String.self, forKey: .image)
        self.id = UUID().uuidString
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode("link", forKey: .type)
        try c.encode(url, forKey: .url)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encodeIfPresent(image, forKey: .image)
    }
}

struct FileBlock: Codable, Hashable, Identifiable {
    let id: String
    let path: String
    let name: String?
    let size: Int?
    let mimeType: String?

    enum CodingKeys: String, CodingKey { case type, path, name, size, mimeType }
    init(path: String, name: String? = nil, size: Int? = nil, mimeType: String? = nil) {
        self.id = UUID().uuidString
        self.path = path
        self.name = name
        self.size = size
        self.mimeType = mimeType
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.path = try c.decode(String.self, forKey: .path)
        self.name = try c.decodeIfPresent(String.self, forKey: .name)
        self.size = try c.decodeIfPresent(Int.self, forKey: .size)
        self.mimeType = try c.decodeIfPresent(String.self, forKey: .mimeType)
        self.id = UUID().uuidString
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode("file", forKey: .type)
        try c.encode(path, forKey: .path)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(size, forKey: .size)
        try c.encodeIfPresent(mimeType, forKey: .mimeType)
    }
}

struct TableBlock: Codable, Hashable, Identifiable {
    let id: String
    let headers: [String]
    let rows: [[String]]
    let caption: String?

    enum CodingKeys: String, CodingKey { case type, headers, rows, caption }
    init(headers: [String], rows: [[String]], caption: String? = nil) {
        self.id = UUID().uuidString
        self.headers = headers
        self.rows = rows
        self.caption = caption
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.headers = try c.decode([String].self, forKey: .headers)
        self.rows = try c.decode([[String]].self, forKey: .rows)
        self.caption = try c.decodeIfPresent(String.self, forKey: .caption)
        self.id = UUID().uuidString
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode("table", forKey: .type)
        try c.encode(headers, forKey: .headers)
        try c.encode(rows, forKey: .rows)
        try c.encodeIfPresent(caption, forKey: .caption)
    }
}

struct ActionBlock: Codable, Hashable, Identifiable {
    let id: String
    let prompt: String?
    let actions: [ActionItem]

    enum CodingKeys: String, CodingKey { case type, prompt, actions }
    init(prompt: String? = nil, actions: [ActionItem]) {
        self.id = UUID().uuidString
        self.prompt = prompt
        self.actions = actions
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.prompt = try c.decodeIfPresent(String.self, forKey: .prompt)
        self.actions = try c.decode([ActionItem].self, forKey: .actions)
        self.id = UUID().uuidString
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode("action", forKey: .type)
        try c.encodeIfPresent(prompt, forKey: .prompt)
        try c.encode(actions, forKey: .actions)
    }
}

struct ActionItem: Codable, Hashable, Identifiable {
    let id: String
    let label: String
    let style: String?
}

// MARK: - Selection Option (shared by radio/checkbox/dropdown)

struct SelectionOption: Codable, Hashable, Identifiable {
    let id: String
    let label: String
    let description: String?

    init(id: String, label: String, description: String? = nil) {
        self.id = id
        self.label = label
        self.description = description
    }
}

// MARK: - Radio Block (Single Select)

struct RadioBlock: Codable, Hashable, Identifiable {
    let id: String
    let label: String?
    let options: [SelectionOption]
    let defaultValue: String?

    enum CodingKeys: String, CodingKey { case type, label, options, defaultValue }
    init(label: String? = nil, options: [SelectionOption], defaultValue: String? = nil) {
        self.id = UUID().uuidString
        self.label = label
        self.options = options
        self.defaultValue = defaultValue
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.label = try c.decodeIfPresent(String.self, forKey: .label)
        self.options = try c.decode([SelectionOption].self, forKey: .options)
        self.defaultValue = try c.decodeIfPresent(String.self, forKey: .defaultValue)
        self.id = UUID().uuidString
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode("radio", forKey: .type)
        try c.encodeIfPresent(label, forKey: .label)
        try c.encode(options, forKey: .options)
        try c.encodeIfPresent(defaultValue, forKey: .defaultValue)
    }
}

// MARK: - Checkbox Block (Multi Select)

struct CheckboxBlock: Codable, Hashable, Identifiable {
    let id: String
    let label: String?
    let options: [SelectionOption]
    let defaultValues: [String]?

    enum CodingKeys: String, CodingKey { case type, label, options, defaultValues }
    init(label: String? = nil, options: [SelectionOption], defaultValues: [String]? = nil) {
        self.id = UUID().uuidString
        self.label = label
        self.options = options
        self.defaultValues = defaultValues
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.label = try c.decodeIfPresent(String.self, forKey: .label)
        self.options = try c.decode([SelectionOption].self, forKey: .options)
        self.defaultValues = try c.decodeIfPresent([String].self, forKey: .defaultValues)
        self.id = UUID().uuidString
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode("checkbox", forKey: .type)
        try c.encodeIfPresent(label, forKey: .label)
        try c.encode(options, forKey: .options)
        try c.encodeIfPresent(defaultValues, forKey: .defaultValues)
    }
}

// MARK: - Dropdown Block

struct DropdownBlock: Codable, Hashable, Identifiable {
    let id: String
    let label: String?
    let placeholder: String?
    let options: [SelectionOption]
    let defaultValue: String?

    enum CodingKeys: String, CodingKey { case type, label, placeholder, options, defaultValue }
    init(label: String? = nil, placeholder: String? = nil, options: [SelectionOption], defaultValue: String? = nil) {
        self.id = UUID().uuidString
        self.label = label
        self.placeholder = placeholder
        self.options = options
        self.defaultValue = defaultValue
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.label = try c.decodeIfPresent(String.self, forKey: .label)
        self.placeholder = try c.decodeIfPresent(String.self, forKey: .placeholder)
        self.options = try c.decode([SelectionOption].self, forKey: .options)
        self.defaultValue = try c.decodeIfPresent(String.self, forKey: .defaultValue)
        self.id = UUID().uuidString
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode("dropdown", forKey: .type)
        try c.encodeIfPresent(label, forKey: .label)
        try c.encodeIfPresent(placeholder, forKey: .placeholder)
        try c.encode(options, forKey: .options)
        try c.encodeIfPresent(defaultValue, forKey: .defaultValue)
    }
}

// MARK: - Audio Block

struct AudioBlock: Codable, Hashable, Identifiable {
    let id: String
    let url: String
    let title: String?
    let duration: Double? // seconds

    enum CodingKeys: String, CodingKey { case type, url, title, duration }
    init(url: String, title: String? = nil, duration: Double? = nil) {
        self.id = UUID().uuidString
        self.url = url
        self.title = title
        self.duration = duration
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.url = try c.decode(String.self, forKey: .url)
        self.title = try c.decodeIfPresent(String.self, forKey: .title)
        self.duration = try c.decodeIfPresent(Double.self, forKey: .duration)
        self.id = UUID().uuidString
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode("audio", forKey: .type)
        try c.encode(url, forKey: .url)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(duration, forKey: .duration)
    }
}

// MARK: - Video Block

struct VideoBlock: Codable, Hashable, Identifiable {
    let id: String
    let url: String
    let caption: String?
    let width: Int?
    let height: Int?

    enum CodingKeys: String, CodingKey { case type, url, caption, width, height }
    init(url: String, caption: String? = nil, width: Int? = nil, height: Int? = nil) {
        self.id = UUID().uuidString
        self.url = url
        self.caption = caption
        self.width = width
        self.height = height
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.url = try c.decode(String.self, forKey: .url)
        self.caption = try c.decodeIfPresent(String.self, forKey: .caption)
        self.width = try c.decodeIfPresent(Int.self, forKey: .width)
        self.height = try c.decodeIfPresent(Int.self, forKey: .height)
        self.id = UUID().uuidString
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode("video", forKey: .type)
        try c.encode(url, forKey: .url)
        try c.encodeIfPresent(caption, forKey: .caption)
        try c.encodeIfPresent(width, forKey: .width)
        try c.encodeIfPresent(height, forKey: .height)
    }
}

// MARK: - Callout Block

struct CalloutBlock: Codable, Hashable, Identifiable {
    let id: String
    let style: String // info, warning, error, success
    let title: String?
    let content: String

    enum CodingKeys: String, CodingKey { case type, style, title, content }
    init(style: String = "info", title: String? = nil, content: String) {
        self.id = UUID().uuidString
        self.style = style
        self.title = title
        self.content = content
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.style = try c.decodeIfPresent(String.self, forKey: .style) ?? "info"
        self.title = try c.decodeIfPresent(String.self, forKey: .title)
        self.content = try c.decode(String.self, forKey: .content)
        self.id = UUID().uuidString
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode("callout", forKey: .type)
        try c.encode(style, forKey: .style)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encode(content, forKey: .content)
    }
}

// MARK: - Blocks Container (for JSON decoding)

struct ContentBlocks: Codable {
    let blocks: [ContentBlock]
}
