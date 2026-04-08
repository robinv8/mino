import Foundation

enum AgentActivityStatus: Equatable {
    case idle
    case thinking
    case coding(filesChanged: Int)
    case error(String)
    case done
}
