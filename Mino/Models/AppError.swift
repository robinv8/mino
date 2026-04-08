import Foundation

enum AppError: Identifiable, Equatable {
    case connectionFailed(String)
    case processStartFailed(String)
    case persistenceFailed(String)
    case generic(String)

    var id: String { message }

    var message: String {
        switch self {
        case .connectionFailed(let detail): "Connection failed: \(detail)"
        case .processStartFailed(let detail): "Process failed: \(detail)"
        case .persistenceFailed(let detail): "Save failed: \(detail)"
        case .generic(let detail): detail
        }
    }
}
