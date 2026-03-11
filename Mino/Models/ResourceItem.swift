import Foundation

struct ResourceItem: Identifiable, Codable, Hashable {
    let id: UUID
    let category: ResourceCategory
    let title: String
    let content: String
    let sourceMessageId: UUID
    let timestamp: Date

    init(
        id: UUID = UUID(),
        category: ResourceCategory,
        title: String,
        content: String,
        sourceMessageId: UUID,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.content = content
        self.sourceMessageId = sourceMessageId
        self.timestamp = timestamp
    }
}

enum ResourceCategory: String, Codable, CaseIterable {
    case image
    case code
    case link
    case file

    var label: String {
        switch self {
        case .image: "Images"
        case .code: "Code"
        case .link: "Links"
        case .file: "Files"
        }
    }

    var icon: String {
        switch self {
        case .image: "photo"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .link: "link"
        case .file: "doc"
        }
    }
}
