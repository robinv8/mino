import Foundation

enum ClaudeConfigReader {
    /// Read MCP server names from ~/.claude.json top-level "mcpServers" object.
    static func readMCPServers() -> [String] {
        guard let home = realHomeDirectory() else { return [] }
        let configURL = home.appendingPathComponent(".claude.json")
        guard let data = try? Data(contentsOf: configURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let mcpServers = json["mcpServers"] as? [String: Any] else {
            return []
        }
        return mcpServers.keys.sorted()
    }

    /// List installed plugin directory names from ~/.claude/plugins/marketplaces/.
    static func readPlugins() -> [String] {
        guard let home = realHomeDirectory() else { return [] }
        let pluginsURL = home.appendingPathComponent(".claude/plugins/marketplaces")
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: pluginsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return contents
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map { $0.lastPathComponent }
            .sorted()
    }

    private static func realHomeDirectory() -> URL? {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir))
        }
        return nil
    }
}
