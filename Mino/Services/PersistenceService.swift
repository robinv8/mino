import Foundation

actor PersistenceService {
    private let baseURL: URL
    private let conversationsURL: URL
    private let agentsURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var saveTask: Task<Void, Never>?

    init(baseURL: URL? = nil) {
        let base: URL
        if let baseURL {
            base = baseURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            base = appSupport.appendingPathComponent("Mino", isDirectory: true)
        }
        self.baseURL = base
        conversationsURL = base.appendingPathComponent("conversations", isDirectory: true)
        agentsURL = base.appendingPathComponent("agents.json")
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        let fm = FileManager.default
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        try? fm.createDirectory(at: conversationsURL, withIntermediateDirectories: true)
    }

    // MARK: - Agents

    func saveAgents(_ agents: [Agent]) throws {
        let data = try encoder.encode(agents)
        try data.write(to: agentsURL, options: .atomic)
    }

    func loadAgents() throws -> [Agent] {
        guard FileManager.default.fileExists(atPath: agentsURL.path) else {
            return []
        }
        let data = try Data(contentsOf: agentsURL)
        return try decoder.decode([Agent].self, from: data)
    }

    // MARK: - Conversations

    func saveConversations(agentId: String, segments: [ConversationSegment]) throws {
        let url = conversationsURL.appendingPathComponent("\(agentId).json")
        let data = try encoder.encode(segments)
        try data.write(to: url, options: .atomic)
    }

    func loadConversations(agentId: String) throws -> [ConversationSegment] {
        let url = conversationsURL.appendingPathComponent("\(agentId).json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode([ConversationSegment].self, from: data)
    }

    func loadAllConversations(agentIds: [String]) throws -> [String: [ConversationSegment]] {
        var result: [String: [ConversationSegment]] = [:]
        for agentId in agentIds {
            let segments = try loadConversations(agentId: agentId)
            if !segments.isEmpty {
                result[agentId] = segments
            }
        }
        return result
    }

    // MARK: - Private

    private func ensureDirectories() {
        let fm = FileManager.default
        try? fm.createDirectory(at: baseURL, withIntermediateDirectories: true)
        try? fm.createDirectory(at: conversationsURL, withIntermediateDirectories: true)
    }
}
