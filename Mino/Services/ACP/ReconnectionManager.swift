import Foundation

actor ReconnectionManager {
    private var attempt: Int = 0
    private var reconnectTask: Task<Void, Never>?
    private let maxAttempts = 5
    private let baseDelay: UInt64 = 1_000_000_000 // 1 second in nanoseconds

    var isReconnecting: Bool {
        reconnectTask != nil && !reconnectTask!.isCancelled
    }

    var currentAttempt: Int { attempt }

    /// Starts reconnection with exponential backoff.
    /// Calls `reconnect` closure on each attempt. Returns true if reconnection succeeded.
    func start(reconnect: @escaping () async throws -> Void,
               onAttempt: @escaping (Int) -> Void,
               onSuccess: @escaping () -> Void,
               onFailure: @escaping () -> Void) {
        cancel()
        attempt = 0

        reconnectTask = Task {
            while attempt < maxAttempts && !Task.isCancelled {
                attempt += 1
                let currentAttempt = attempt
                onAttempt(currentAttempt)

                // Exponential backoff: 1s, 2s, 4s, 8s, 16s
                let delay = baseDelay * UInt64(1 << (currentAttempt - 1))
                do {
                    try await Task.sleep(nanoseconds: delay)
                } catch {
                    return // cancelled
                }

                guard !Task.isCancelled else { return }

                do {
                    try await reconnect()
                    onSuccess()
                    self.reconnectTask = nil
                    self.attempt = 0
                    return
                } catch {
                    // Continue to next attempt
                }
            }

            if !Task.isCancelled {
                onFailure()
            }
            self.reconnectTask = nil
        }
    }

    func cancel() {
        reconnectTask?.cancel()
        reconnectTask = nil
        attempt = 0
    }
}
