import AlgorithmArenaCore
import AlgorithmArenaFixtures
import Foundation

struct DemoMatch {
    struct Player {
        let id: PlayerID
        var nickname: String
        var confirmed = false
        var ready = false
        var stage: PlayerStage = .atStart
        var route: RouteBranch?
        var arrivals: [ConfirmedArrival] = []
        var submissions: [ChallengeSlot: PrivateSubmission] = [:]
        var finished = false
        var steps = 0
    }

    static let sharedSlots: [ChallengeSlot] = [.first, .third]

    let course: CourseGraph
    let code: String
    let creatorID: PlayerID
    var algorithm: AlgorithmKind
    var phase = MatchPhase.lobby
    var players: [Player]
    var departedID: PlayerID?
    var learningCheck: LearningCheckRecord?

    private var stops: CourseStops { course.stops }

    func player(_ id: PlayerID) -> Player? {
        players.first { $0.id == id }
    }

    var canStart: Bool {
        players.count == 2 && players.allSatisfy { $0.confirmed && $0.ready && $0.hasArrived(at: stops.start) }
    }

    mutating func apply(_ action: MatchAction, by id: PlayerID, commandID: UUID) throws {
        guard let index = players.firstIndex(where: { $0.id == id }) else {
            throw MatchServiceError(code: .notMember, message: "Not a member of this match.")
        }
        switch action {
        case .selectAlgorithm(let selected):
            try requirePhase(.lobby)
            guard id == creatorID else { throw invalid("Only the host chooses the algorithm.") }
            algorithm = selected
            for index in players.indices {
                players[index].confirmed = false
                players[index].ready = false
            }
        case .confirmAlgorithm(let confirmed):
            try requirePhase(.lobby)
            guard confirmed == algorithm else { throw invalid("The algorithm changed.") }
            players[index].confirmed = true
        case .setReady(let ready):
            try requirePhase(.lobby)
            guard players[index].confirmed || !ready else {
                throw MatchServiceError(code: .algorithmNotConfirmed, message: "Confirm the algorithm first.")
            }
            players[index].ready = ready
        case .start:
            try requirePhase(.lobby)
            guard id == creatorID else { throw invalid("Only the host starts the match.") }
            guard canStart else {
                throw MatchServiceError(code: .arrivalRequired, message: "Both players must be ready at the start.")
            }
            phase = .practice
            for index in players.indices {
                players[index].stage = .practice
            }
        case .confirmArrival(let node, let evidence):
            try arrive(at: node, evidence: evidence, player: index)
        case .chooseRoute(let branch):
            guard players[index].stage == .choosingRoute else {
                throw MatchServiceError(code: .routeAlreadyLocked, message: "The route is already chosen.")
            }
            players[index].route = branch
            players[index].stage = .walking(target: branch == .bonus ? stops.bonusMiddle : stops.standardMiddle)
            players[index].steps += 1
        case .submitAnswer(let challengeID, let answer):
            try submit(answer, to: challengeID, player: index, commandID: commandID)
        case .finish(let evidence):
            guard players[index].stage == .walking(target: stops.finish) else {
                throw MatchServiceError(code: .arrivalRequired, message: "Reach the finish first.")
            }
            players[index].arrivals.append(ConfirmedArrival(nodeID: stops.finish, method: evidence.method))
            players[index].stage = .finished
            players[index].finished = true
            players[index].steps += 1
            phase = players.allSatisfy(\.finished) ? .finished : .awaitingFinish
        case .leave:
            departedID = id
            players[index].stage = .departed
            phase = phase == .lobby ? .lobby : .incomplete
        case .createRoom, .joinRoom:
            throw invalid("Already in a room.")
        }
    }

    private mutating func arrive(at node: NodeID, evidence: ArrivalEvidence, player index: Int) throws {
        let arrival = ConfirmedArrival(nodeID: node, method: evidence.method)
        if phase == .lobby {
            guard node == stops.start else { throw invalid("Only the start is open.") }
            if !players[index].hasArrived(at: node) { players[index].arrivals.append(arrival) }
            return
        }
        guard players[index].stage == .walking(target: node), node != stops.finish, let slot = slot(at: node) else {
            throw invalid("That isn't your next stop.")
        }
        players[index].arrivals.append(arrival)
        players[index].stage = .challenge(challengeID: ArenaFixtures.challengeID(slot, algorithm))
        players[index].steps += 1
    }

    private mutating func submit(_ answer: SubmittedAnswer, to challengeID: ChallengeID, player index: Int, commandID: UUID) throws {
        guard let slot = availableSlot(for: players[index]), ArenaFixtures.challengeID(slot, algorithm) == challengeID else {
            if players[index].submissions.values.contains(where: { $0.challengeID == challengeID }) {
                throw MatchServiceError(code: .alreadySubmitted, message: "Already answered.")
            }
            throw MatchServiceError(code: .challengeUnavailable, message: "This question isn't open.")
        }
        let submission = PrivateSubmission(challengeID: challengeID, commandID: commandID, answer: answer, acceptedAt: .now)
        players[index].submissions[slot] = submission
        switch slot {
        case .practice:
            players[index].stage = .walking(target: stops.first)
            phase = .active
        case .first:
            players[index].stage = .choosingRoute
        case .standardMiddle, .bonusMiddle:
            players[index].stage = .walking(target: stops.third)
        case .third:
            players[index].stage = .walking(target: stops.finish)
        case .learningCheck:
            guard case .transfer(let node, let reason) = answer,
                case .transfer(let correctNode, let correctReason) = ArenaFixtures.correctAnswer(.learningCheck, algorithm)
            else { throw invalid("Choose a node and a reason.") }
            learningCheck = LearningCheckRecord(
                challengeID: challengeID, firstAnswer: answer, answeredAt: .now,
                nodeCorrect: node == correctNode, reasonCorrect: reason == correctReason
            )
            return
        }
        players[index].steps += 1
    }

    func availableSlot(for player: Player) -> ChallengeSlot? {
        switch player.stage {
        case .practice:
            return .practice
        case .challenge(let challengeID):
            return ChallengeSlot.allCases.first { ArenaFixtures.challengeID($0, algorithm) == challengeID }
        case .finished where player.id == ArenaFixtures.playerID && learningCheck == nil:
            return .learningCheck
        default:
            return nil
        }
    }

    func isReleased(_ slot: ChallengeSlot) -> Bool {
        guard Self.sharedSlots.contains(slot) else { return true }
        return players.count == 2 && players.allSatisfy { $0.submissions[slot] != nil }
    }

    func points(for player: Player, in slot: ChallengeSlot) -> Int {
        guard let submission = player.submissions[slot], submission.answer == ArenaFixtures.correctAnswer(slot, algorithm) else {
            return 0
        }
        return ArenaFixtures.challenge(slot, algorithm).maximumPoints
    }

    func awards(for player: Player) -> [ScoreAward] {
        let scored: [ChallengeSlot] = [.first, .standardMiddle, .bonusMiddle, .third]
        var awards = scored
            .filter { player.submissions[$0] != nil && isReleased($0) }
            .map { ScoreAward(slot: $0, points: points(for: player, in: $0)) }
        if player.finished {
            awards.append(ScoreAward(slot: nil, points: 20))
        }
        return awards
    }

    func remainingPoints(for player: Player) -> Int {
        guard phase != .incomplete else { return 0 }
        let middle: Int
        if let route = player.route {
            let slot: ChallengeSlot = route == .bonus ? .bonusMiddle : .standardMiddle
            middle = player.submissions[slot] == nil ? ArenaFixtures.challenge(slot, algorithm).maximumPoints : 0
        } else {
            middle = 40
        }
        return (player.submissions[.first] == nil ? 20 : 0) + middle
            + (player.submissions[.third] == nil ? 20 : 0) + (player.finished ? 0 : 20)
    }

    func pendingPoints(for player: Player) -> Int {
        Self.sharedSlots
            .filter { player.submissions[$0] != nil && !isReleased($0) }
            .reduce(0) { $0 + ArenaFixtures.challenge($1, algorithm).maximumPoints }
    }

    func slot(at node: NodeID) -> ChallengeSlot? {
        switch node {
        case stops.first: .first
        case stops.standardMiddle: .standardMiddle
        case stops.bonusMiddle: .bonusMiddle
        case stops.third: .third
        default: nil
        }
    }

    private func requirePhase(_ expected: MatchPhase) throws {
        guard phase == expected else {
            throw MatchServiceError(code: .invalidPhase, message: "Not available in this phase.")
        }
    }

    private func invalid(_ message: String) -> MatchServiceError {
        MatchServiceError(code: .invalidCommand, message: message)
    }
}

extension DemoMatch.Player {
    func hasArrived(at node: NodeID) -> Bool {
        arrivals.contains { $0.nodeID == node }
    }
}

private extension ArrivalEvidence {
    var method: ArrivalMethod {
        switch self {
        case .location: .location
        case .organiserApproval: .organiserApproval
        }
    }
}
