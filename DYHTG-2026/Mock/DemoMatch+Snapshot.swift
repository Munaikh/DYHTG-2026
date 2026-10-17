import AlgorithmArenaCore
import AlgorithmArenaFixtures
import Foundation

extension DemoMatch {
    func snapshot(revision: Int, viewerID: PlayerID) -> MatchSnapshot {
        MatchSnapshot(
            revision: revision,
            serverTime: .now,
            room: PublicMatchState(
                matchID: ArenaFixtures.matchID,
                roomCode: code,
                creatorID: creatorID,
                course: course.reference,
                algorithm: algorithm,
                phase: phase,
                players: players.map(progress),
                result: result
            ),
            viewer: privateState(for: viewerID)
        )
    }

    private func progress(_ player: Player) -> PlayerProgress {
        let scored = player.submissions
            .filter { $0.key != .practice && $0.key != .learningCheck }
            .sorted { $0.value.acceptedAt < $1.value.acceptedAt }
            .map(\.value.challengeID)
        return PlayerProgress(
            id: player.id,
            nickname: player.nickname,
            algorithmConfirmed: player.confirmed,
            ready: player.ready,
            connection: .online,
            stage: player.stage,
            routeChoice: player.route,
            arrivals: player.arrivals,
            completedChallengeIDs: scored,
            releasedScore: awards(for: player).reduce(0) { $0 + $1.points },
            pendingRewardMaximum: pendingPoints(for: player),
            remainingAvailablePoints: remainingPoints(for: player)
        )
    }

    private var result: MatchResult? {
        let standings = players.map { player in
            let awards = awards(for: player)
            return Standing(
                playerID: player.id,
                routeChoice: player.route,
                score: awards.reduce(0) { $0 + $1.points },
                awards: awards
            )
        }
        if let departedID, phase == .incomplete {
            return .incomplete(departedPlayerID: departedID, standings: standings)
        }
        guard phase == .finished, standings.count == 2 else { return nil }
        if standings[0].score == standings[1].score {
            return .draw(standings: standings)
        }
        let winner = standings.max { $0.score < $1.score }!
        return .winner(playerID: winner.playerID, standings: standings)
    }

    private func privateState(for id: PlayerID) -> PrivatePlayerState {
        guard let player = player(id) else {
            return PrivatePlayerState(
                playerID: id, submissions: [], feedback: [], availableChallenges: [], navigation: nil,
                learningCheck: nil
            )
        }
        let ordered = ChallengeSlot.allCases.compactMap { slot in player.submissions[slot].map { (slot, $0) } }
        return PrivatePlayerState(
            playerID: id,
            submissions: ordered.map(\.1),
            feedback: ordered.map { feedback(for: $0.0, viewer: player) },
            availableChallenges: availableSlot(for: player).map { [ArenaFixtures.challenge($0, algorithm)] } ?? [],
            navigation: navigation(for: player),
            learningCheck: learningCheck
        )
    }

    private func feedback(for slot: ChallengeSlot, viewer: Player) -> FeedbackAvailability {
        let challengeID = ArenaFixtures.challengeID(slot, algorithm)
        guard isReleased(slot) else { return .pending(challengeID: challengeID) }
        let authored = ArenaFixtures.feedback(slot, algorithm)
        let correct = ArenaFixtures.correctAnswer(slot, algorithm)
        let visible = Self.sharedSlots.contains(slot) ? players : [viewer]
        let answers = visible.compactMap { player in
            player.submissions[slot].map { submission in
                ReleasedAnswer(
                    playerID: player.id,
                    answer: submission.answer,
                    isCorrect: submission.answer == correct,
                    awardedPoints: points(for: player, in: slot)
                )
            }
        }
        return .released(
            feedback: ReleasedFeedback(
                challengeID: challengeID,
                correctAnswer: correct,
                explanation: authored.explanation,
                workedSteps: authored.workedSteps,
                trace: authored.trace,
                answers: answers
            )
        )
    }

    private func navigation(for player: Player) -> NavigationState? {
        guard case .walking(let target) = player.stage, let from = player.arrivals.last?.nodeID else { return nil }
        return NavigationState(nextStop: target, edgeIDs: legEdges(from: from, to: target, branch: player.route ?? .standard))
    }

    private func legEdges(from origin: NodeID, to target: NodeID, branch: RouteBranch) -> [EdgeID] {
        guard let route = course.routes.first(where: { $0.branch == branch }) else { return [] }
        var node = course.stops.start
        var leg: [EdgeID] = []
        for id in route.edgeIDs {
            guard let edge = course.edges.first(where: { $0.id == id }) else { continue }
            let next = edge.from == node ? edge.to : edge.from
            if node == origin || !leg.isEmpty { leg.append(id) }
            node = next
            if !leg.isEmpty && node == target { break }
        }
        return leg
    }
}
