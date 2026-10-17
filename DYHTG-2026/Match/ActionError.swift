import AlgorithmArenaCore
import Foundation

struct ActionError: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
    var canRetry = false
}

extension ActionError {
    init(_ error: MatchServiceError, canRetry: Bool = false) {
        self.init(title: error.code.title, message: error.code.guidance, canRetry: canRetry)
    }

    static let connectionLost = ActionError(
        title: "Connection Lost",
        message: "Your last action may not have reached the room. Trying again sends the same action, so nothing counts twice.",
        canRetry: true
    )
}
