import Foundation

/// Manages a Claude Code subprocess, providing stdin/stdout communication.
/// Uses plain class + DispatchQueue instead of actor to avoid cooperative thread pool blocking.
final class ClaudeCodeTransport: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.mino.cc-transport")
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var eventContinuation: AsyncStream<CCEvent>.Continuation?

    var isRunning: Bool {
        queue.sync { process?.isRunning ?? false }
    }

    /// Start a Claude Code process for a single prompt.
    /// When `sessionId` is provided, passes `--resume <sessionId>` to continue a previous conversation.
    func start(message: String, cwd: String, sessionId: String? = nil) throws -> AsyncStream<CCEvent> {
        stop()

        let proc = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()

        var cmd = "claude -p --output-format stream-json --verbose --dangerously-skip-permissions"
        if let sessionId, !sessionId.isEmpty {
            // Shell-escape the sessionId to prevent injection
            let escaped = sessionId.replacingOccurrences(of: "'", with: "'\\''")
            cmd += " --resume '\(escaped)'"
        }

        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-l", "-c", cmd]
        proc.currentDirectoryURL = URL(fileURLWithPath: cwd)
        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = stderr

        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "dumb"
        // Ensure common CLI tool paths are available (macOS app sandbox may strip them)
        let extraPaths = [
            "\(NSHomeDirectory())/.local/bin",
            "/usr/local/bin",
            "/opt/homebrew/bin",
        ]
        let currentPath = env["PATH"] ?? "/usr/bin:/bin"
        env["PATH"] = (extraPaths + [currentPath]).joined(separator: ":")
        proc.environment = env

        let (stream, continuation) = AsyncStream.makeStream(of: CCEvent.self)

        queue.sync {
            self.process = proc
            self.stdinPipe = stdin
            self.stdoutPipe = stdout
            self.stderrPipe = stderr
            self.eventContinuation = continuation
        }

        // Buffer for accumulating partial JSON lines
        var buffer = Data()
        let bufferQueue = DispatchQueue(label: "com.mino.cc-buffer")

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                // EOF
                handle.readabilityHandler = nil
                bufferQueue.sync {
                    if !buffer.isEmpty {
                        let event = CCEvent.parse(buffer)
                        if case .unknown = event { } else {
                            self?.queue.sync { self?.eventContinuation?.yield(event) }
                        }
                        buffer.removeAll()
                    }
                }
                return
            }

            bufferQueue.sync {
                buffer.append(chunk)
                while let newlineRange = buffer.range(of: Data([0x0A])) {
                    let lineData = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
                    buffer.removeSubrange(buffer.startIndex...newlineRange.lowerBound)
                    if lineData.isEmpty { continue }
                    let event = CCEvent.parse(lineData)
                    if case .unknown = event { continue }
                    self?.queue.sync { self?.eventContinuation?.yield(event) }
                }
            }
        }

        // Drain stderr to prevent pipe buffer filling up
        stderr.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }

        try proc.run()

        // Write message to stdin, then close to signal EOF
        if let data = message.data(using: .utf8) {
            stdin.fileHandleForWriting.write(data)
        }
        stdin.fileHandleForWriting.closeFile()

        // Monitor process termination
        proc.terminationHandler = { [weak self] proc in
            guard let self else { return }
            self.queue.sync {
                if proc.terminationStatus != 0 {
                    let errorEvent = CCResultEvent(from: [
                        "is_error": true,
                        "result": "Claude Code process exited with code \(proc.terminationStatus)",
                        "duration_ms": 0,
                        "total_cost_usd": 0,
                        "session_id": ""
                    ])
                    self.eventContinuation?.yield(.result(errorEvent))
                }
                self.eventContinuation?.finish()
                self.eventContinuation = nil
            }
        }

        return stream
    }

    /// Stop the running process.
    func stop() {
        queue.sync {
            stdoutPipe?.fileHandleForReading.readabilityHandler = nil
            stderrPipe?.fileHandleForReading.readabilityHandler = nil
            if let proc = process, proc.isRunning {
                proc.terminate()
            }
            process = nil
            stdinPipe = nil
            stdoutPipe = nil
            stderrPipe = nil
            eventContinuation?.finish()
            eventContinuation = nil
        }
    }
}
