import AlgorithmArenaCore
import AlgorithmArenaFixtures
import Foundation

actor DemoMatchService: MatchService {
    struct Timing: Sendable {
        var latency: Duration = .milliseconds(450)
        var opponent: Duration = .milliseconds(2200)
    }

    static let joinableCode = "ARENA1"

    private struct Seat {
        let id: PlayerID
        var nickname: String
        var confirmed = false
        var ready = false
        var atStart = false
    }

    private let course: CourseGraph
    private let timing: Timing
    private let viewerID = ArenaFixtures.playerID
    private let opponentID = ArenaFixtures.opponentID
    private var code = ""
    private var creatorID = ArenaFixtures.playerID
    private var algorithm = AlgorithmKind.dijkstra
    private var seats: [Seat] = []
    private var started = false
    private var revision = 0
    private var receipts: [UUID: (MatchCommand, CommandReceipt)] = [:]
    private var subscribers: [UUID: AsyncThrowingStream<SnapshotInvalidation, any Error>.Continuation] = [:]
    private var opponentTask: Task<Void, Never>?

    init(course: CourseGraph = ArenaFixtures.course, timing: Timing = Timing()) {
        self.course = course
        self.timing = timing
    }

    func send(_ command: MatchCommand) async throws -> CommandReceipt {
        if let (original, receipt) = receipts[command.id] {
            guard original == command else {
                throw MatchServiceError(code: .idempotencyConflict, message: "Command ID reused with a different payload.")
            }
            return receipt
        }
        try await Task.sleep(for: timing.latency)
        try validate(command.scope)
        try apply(command.action)
        revision += 1
        let receipt = CommandReceipt(commandID: command.id, acceptedRevision: revision, snapshot: makeSnapshot())
        receipts[command.id] = (command, receipt)
        broadcast()
        scheduleOpponent()
        return receipt
    }

    func snapshot(for matchID: MatchID) async throws -> MatchSnapshot {
        try Task.checkCancellation()
        guard !seats.isEmpty, matchID == ArenaFixtures.matchID else {
            throw MatchServiceError(code: .notMember, message: "Not a member of this match.")
        }
        return makeSnapshot()
    }

    func invalidations(for matchID: MatchID) async throws -> AsyncThrowingStream<SnapshotInvalidation, any Error> {
        guard !seats.isEmpty, matchID == ArenaFixtures.matchID else {
            throw MatchServiceError(code: .notMember, message: "Not a member of this match.")
        }
        let id = UUID()
        let (stream, continuation) = AsyncThrowingStream<SnapshotInvalidation, any Error>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeSubscriber(id) }
        }
        continuation.yield(SnapshotInvalidation(matchID: matchID, revision: revision))
        return stream
    }

    private func validate(_ scope: CommandScope) throws {
        switch scope {
        case .roomEntry:
            guard seats.isEmpty else {
                throw MatchServiceError(code: .invalidPhase, message: "Already in a room.")
            }
        case .match(let matchID, let reference, let expectedRevision):
            guard !seats.isEmpty, matchID == ArenaFixtures.matchID else {
                throw MatchServiceError(code: .notMember, message: "Not a member of this match.")
            }
            guard reference == course.reference else {
                throw MatchServiceError(code: .incompatibleCourse, message: "Course version mismatch.")
            }
            guard expectedRevision == revision else {
                throw MatchServiceError(code: .staleRevision, message: "Refetch the snapshot.", currentRevision: revision)
            }
        }
    }

    private func apply(_ action: MatchAction) throws {
        switch action {
        case .createRoom(let nickname, _, let selected):
            code = Self.makeCode()
            creatorID = viewerID
            algorithm = selected
            seats = [Seat(id: viewerID, nickname: nickname)]
        case .joinRoom(let joinCode, let nickname):
            guard joinCode.uppercased() == Self.joinableCode else {
                throw MatchServiceError(code: .roomNotFound, message: "No room uses this code.")
            }
            code = Self.joinableCode
            creatorID = opponentID
            algorithm = .aStar
            seats = [
                Seat(id: viewerID, nickname: nickname),
                Seat(id: opponentID, nickname: "Sam", confirmed: true, ready: true, atStart: true),
            ]
        case .selectAlgorithm(let selected):
            try requireLobby()
            guard creatorID == viewerID else {
                throw MatchServiceError(code: .invalidCommand, message: "Only the host chooses the algorithm.")
            }
            algorithm = selected
            for index in seats.indices {
                seats[index].confirmed = false
                seats[index].ready = false
            }
        case .confirmAlgorithm(let confirmed):
            try requireLobby()
            guard confirmed == algorithm else {
                throw MatchServiceError(code: .staleRevision, message: "Algorithm changed.", currentRevision: revision)
            }
            seats[0].confirmed = true
        case .setReady(let ready):
            try requireLobby()
            guard seats[0].confirmed || !ready else {
                throw MatchServiceError(code: .algorithmNotConfirmed, message: "Confirm the algorithm first.")
            }
            seats[0].ready = ready
        case .confirmArrival(let nodeID, _):
            try requireLobby()
            guard nodeID == course.stops.start else {
                throw MatchServiceError(code: .invalidPhase, message: "Only the start is open.")
            }
            seats[0].atStart = true
        case .start:
            try requireLobby()
            guard creatorID == viewerID else {
                throw MatchServiceError(code: .invalidCommand, message: "Only the host starts the match.")
            }
            guard canStart else {
                throw MatchServiceError(code: .arrivalRequired, message: "Both players must be ready at the start.")
            }
            started = true
        case .leave:
            opponentTask?.cancel()
        default:
            throw MatchServiceError(code: .invalidPhase, message: "Not available in this phase.")
        }
    }

    private var canStart: Bool {
        seats.count == 2 && seats.allSatisfy { $0.confirmed && $0.ready && $0.atStart }
    }

    private func requireLobby() throws {
        guard !started else {
            throw MatchServiceError(code: .invalidPhase, message: "The match has started.")
        }
    }

    private func scheduleOpponent() {
        opponentTask?.cancel()
        guard !started, nextOpponentStep() != nil else { return }
        opponentTask = Task { [timing] in
            try? await Task.sleep(for: timing.opponent)
            guard !Task.isCancelled else { return }
            self.performOpponentStep()
        }
    }

    private enum OpponentStep {
        case join, confirm, ready, start
    }

    private func nextOpponentStep() -> OpponentStep? {
        guard seats.count == 2 else { return creatorID == viewerID && !seats.isEmpty ? .join : nil }
        if !seats[1].confirmed { return .confirm }
        if !seats[1].ready { return .ready }
        if creatorID == opponentID, canStart { return .start }
        return nil
    }

    private func performOpponentStep() {
        guard let step = nextOpponentStep() else { return }
        switch step {
        case .join: seats.append(Seat(id: opponentID, nickname: "Sam", atStart: true))
        case .confirm: seats[1].confirmed = true
        case .ready: seats[1].ready = true
        case .start: started = true
        }
        revision += 1
        broadcast()
        scheduleOpponent()
    }

    private func broadcast() {
        let invalidation = SnapshotInvalidation(matchID: ArenaFixtures.matchID, revision: revision)
        for subscriber in subscribers.values {
            subscriber.yield(invalidation)
        }
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers[id] = nil
    }

    private func makeSnapshot() -> MatchSnapshot {
        let viewer = PrivatePlayerState(
            playerID: viewerID, submissions: [], feedback: [], availableChallenges: [], navigation: nil,
            learningCheck: nil
        )
        guard started else {
            return MatchSnapshot(
                revision: revision,
                serverTime: .now,
                room: PublicMatchState(
                    matchID: ArenaFixtures.matchID, roomCode: code, creatorID: creatorID,
                    course: course.reference, algorithm: algorithm, phase: .lobby,
                    players: seats.map(progress), result: nil
                ),
                viewer: viewer
            )
        }
        let fixture = ArenaFixtures.snapshot(.practice, algorithm: algorithm)
        let names = Dictionary(uniqueKeysWithValues: seats.map { ($0.id, $0.nickname) })
        return MatchSnapshot(
            revision: revision,
            serverTime: .now,
            room: PublicMatchState(
                matchID: fixture.room.matchID, roomCode: code, creatorID: creatorID,
                course: fixture.room.course, algorithm: algorithm, phase: fixture.room.phase,
                players: fixture.room.players.map { $0.renamed(names[$0.id] ?? $0.nickname) },
                result: nil
            ),
            viewer: fixture.viewer
        )
    }

    private func progress(_ seat: Seat) -> PlayerProgress {
        PlayerProgress(
            id: seat.id, nickname: seat.nickname, algorithmConfirmed: seat.confirmed, ready: seat.ready,
            connection: .online, stage: .atStart, routeChoice: nil,
            arrivals: seat.atStart ? [ConfirmedArrival(nodeID: course.stops.start, method: .location)] : [],
            completedChallengeIDs: [], releasedScore: 0, pendingRewardMaximum: 0, remainingAvailablePoints: 100
        )
    }

    private static func makeCode() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<6).map { _ in alphabet.randomElement()! })
    }
}

private extension PlayerProgress {
    func renamed(_ name: String) -> PlayerProgress {
        PlayerProgress(
            id: id, nickname: name, algorithmConfirmed: algorithmConfirmed, ready: ready,
            connection: connection, stage: stage, routeChoice: routeChoice, arrivals: arrivals,
            completedChallengeIDs: completedChallengeIDs, releasedScore: releasedScore,
            pendingRewardMaximum: pendingRewardMaximum, remainingAvailablePoints: remainingAvailablePoints
        )
    }
}
