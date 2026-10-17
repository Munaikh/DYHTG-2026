import AlgorithmArenaCore

extension AlgorithmKind {
    var title: String {
        switch self {
        case .dijkstra: "Dijkstra"
        case .aStar: "A*"
        }
    }

    var rule: String {
        switch self {
        case .dijkstra:
            "Always expand the frontier node with the lowest cost from the start."
        case .aStar:
            "Always expand the frontier node with the lowest g + h: the cost so far plus an estimate of what's left."
        }
    }
}

extension MatchErrorCode {
    var title: String {
        switch self {
        case .roomNotFound: "Room Not Found"
        case .roomFull: "Room Is Full"
        case .unauthenticated, .notMember: "Session Expired"
        case .staleRevision: "Room Updated"
        case .algorithmNotConfirmed: "Confirm the Algorithm"
        case .arrivalRequired, .staleLocation, .inaccurateLocation, .outsideArrivalRadius: "Check-In Failed"
        case .rateLimited: "Too Many Attempts"
        case .incompatibleContract, .incompatibleCourse: "Update Required"
        case .disconnected, .serviceUnavailable: "Can't Reach the Room"
        default: "Action Not Available"
        }
    }

    var guidance: String {
        switch self {
        case .roomNotFound: "Check the six-character code with the other player and try again."
        case .roomFull: "This room already has two players."
        case .unauthenticated, .notMember: "Rejoin the room with its code."
        case .staleRevision: "The room changed while you were acting. You're now looking at the latest state."
        case .algorithmNotConfirmed: "Both players need to confirm the algorithm first."
        case .arrivalRequired: "Check in at the start before the match begins."
        case .staleLocation: "Your location was too old. Hold still for a moment and check in again."
        case .inaccurateLocation: "Your location isn't precise enough yet. Move away from tall buildings and try again."
        case .outsideArrivalRadius: "You're not close enough yet. Walk a little closer and check in again."
        case .rateLimited: "Wait a moment before trying again."
        case .incompatibleContract, .incompatibleCourse: "Update Arena to keep playing this course."
        case .disconnected, .serviceUnavailable: "Check your connection. Your progress is saved."
        default: "That isn't possible right now. The room shows the latest state."
        }
    }
}
