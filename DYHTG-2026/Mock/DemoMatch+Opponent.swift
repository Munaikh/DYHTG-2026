import AlgorithmArenaCore
import AlgorithmArenaFixtures
import Foundation

extension DemoMatch {
    enum OpponentMove {
        case join
        case act(MatchAction)
    }

    func nextOpponentMove(viewerID: PlayerID, opponentID: PlayerID) -> OpponentMove? {
        guard departedID == nil else { return nil }
        guard let opponent = player(opponentID) else {
            return creatorID == viewerID ? .join : nil
        }
        if phase == .lobby {
            if !opponent.hasArrived(at: course.stops.start) {
                return .act(.confirmArrival(nodeID: course.stops.start, evidence: evidence(at: course.stops.start)))
            }
            if !opponent.confirmed { return .act(.confirmAlgorithm(algorithm: algorithm)) }
            if !opponent.ready { return .act(.setReady(ready: true)) }
            if creatorID == opponentID, canStart { return .act(.start) }
            return nil
        }
        guard let viewer = player(viewerID), opponent.steps < viewer.steps else { return nil }
        switch opponent.stage {
        case .practice:
            return .act(.submitAnswer(challengeID: ArenaFixtures.challengeID(.practice, algorithm), answer: ArenaFixtures.correctAnswer(.practice, algorithm)))
        case .walking(let target) where target == course.stops.finish:
            return .act(.finish(evidence: evidence(at: target)))
        case .walking(let target):
            return .act(.confirmArrival(nodeID: target, evidence: evidence(at: target)))
        case .choosingRoute:
            return .act(.chooseRoute(branch: .standard))
        case .challenge(let challengeID):
            guard let slot = ChallengeSlot.allCases.first(where: { ArenaFixtures.challengeID($0, algorithm) == challengeID }) else {
                return nil
            }
            return .act(.submitAnswer(challengeID: challengeID, answer: opponentAnswer(for: slot)))
        default:
            return nil
        }
    }

    private func opponentAnswer(for slot: ChallengeSlot) -> SubmittedAnswer {
        let correct = ArenaFixtures.correctAnswer(slot, algorithm)
        guard slot == .first, case .selectNode(let options) = ArenaFixtures.challenge(slot, algorithm).action,
            let wrong = options.first(where: { .node(nodeID: $0) != correct })
        else { return correct }
        return .node(nodeID: wrong)
    }

    private func evidence(at node: NodeID) -> ArrivalEvidence {
        let coordinate = course.nodes.first { $0.id == node }?.coordinate ?? Coordinate(latitude: 0, longitude: 0)
        return .location(fix: LocationFix(coordinate: coordinate, capturedAt: .now, horizontalAccuracyMetres: 5))
    }
}
