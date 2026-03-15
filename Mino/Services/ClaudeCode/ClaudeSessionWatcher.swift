import Foundation

/// Watches Claude Code JSONL session files for real-time changes from CLI usage.
/// Uses a polling timer to detect file content changes (DispatchSource on directories
/// only fires for structural changes, not content modifications to existing files).
class ClaudeSessionWatcher {
    private let projectDir: URL
    private let agentId: String
    /// Byte offset per session ID — tracks how far we've read each file.
    private var fileOffsets: [String: UInt64] = [:]
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.mino.session-watcher", qos: .utility)
    /// Session IDs managed by Mino's own ClaudeCodeClient — skip to avoid duplicates.
    private var excludedSessionIds: Set<String> = []
    private var isRunning = false

    /// Polling interval in seconds.
    private let pollInterval: TimeInterval = 2.0

    /// Called on **main queue** with new messages, their session ID, and the file's modification date.
    var onNewMessages: ((_ messages: [ChatMessage], _ sessionId: String, _ fileDate: Date) -> Void)?

    init(projectDir: URL, agentId: String) {
        self.projectDir = projectDir
        self.agentId = agentId
    }

    /// Start watching. Records current file sizes so only NEW content is reported.
    func start() {
        queue.async { [weak self] in
            self?.startOnQueue()
        }
    }

    private func startOnQueue() {
        guard !isRunning else { return }
        isRunning = true

        // Snapshot current sizes — we only want to see content written AFTER this point
        let sessions = ClaudeSessionLoader.listSessions(projectDir: projectDir)
        for session in sessions {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: session.filePath.path),
               let size = attrs[.size] as? UInt64 {
                fileOffsets[session.sessionId] = size
            }
        }

        // Poll for changes using a repeating timer
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + pollInterval, repeating: pollInterval)
        t.setEventHandler { [weak self] in
            self?.checkForChanges()
        }
        t.resume()
        timer = t
    }

    func stop() {
        queue.async { [weak self] in
            self?.timer?.cancel()
            self?.timer = nil
            self?.isRunning = false
        }
    }

    /// Mark a session ID as excluded (Mino's own active session).
    func exclude(sessionId: String) {
        queue.async { self.excludedSessionIds.insert(sessionId) }
    }

    /// Un-exclude a session ID (e.g., after Mino finishes generating).
    func removeExclusion(sessionId: String) {
        queue.async { self.excludedSessionIds.remove(sessionId) }
    }

    // MARK: - Private

    private func checkForChanges() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: projectDir,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        ) else { return }

        for file in files where file.pathExtension == "jsonl" {
            let sessionId = file.deletingPathExtension().lastPathComponent

            guard let attrs = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let sizeInt = attrs.fileSize else { continue }
            let currentSize = UInt64(sizeInt)
            let lastOffset = fileOffsets[sessionId] ?? 0
            let fileDate = attrs.contentModificationDate ?? Date()

            // No new content
            guard currentSize > lastOffset else { continue }

            if excludedSessionIds.contains(sessionId) {
                // Advance offset without reading — Mino already has these messages via streaming
                fileOffsets[sessionId] = currentSize
                continue
            }

            // Incremental read: only new bytes
            guard let handle = try? FileHandle(forReadingFrom: file) else { continue }
            handle.seek(toFileOffset: lastOffset)
            let newData = handle.readData(ofLength: Int(currentSize - lastOffset))
            try? handle.close()

            fileOffsets[sessionId] = currentSize

            guard let text = String(data: newData, encoding: .utf8) else { continue }
            let messages = ClaudeSessionLoader.parseLines(text)

            if !messages.isEmpty {
                DispatchQueue.main.async { [weak self] in
                    self?.onNewMessages?(messages, sessionId, fileDate)
                }
            }
        }
    }

    deinit {
        timer?.cancel()
        timer = nil
    }
}
