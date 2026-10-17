import AlgorithmArenaCore
import AlgorithmArenaFixtures
import Foundation

actor DemoMatchService: MatchService {
    struct Timing: Sendable {
        var latency: Duration = .milliseconds(450)
        var lobby: Duration = .milliseconds(2200)
        var opponent: Duration = .seconds(5)
    }

    private let course: CourseGraph
    private let timing: Timing
    private let viewerID = ArenaFixtures.playerID
    private let opponentID = ArenaFixtures.opponentID
    private var match: DemoMatch?
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
        try apply(command)
        revision += 1
        let receipt = CommandReceipt(
            commandID: command.id,
            acceptedRevision: revision,
            snapshot: match!.snapshot(revision: revision, viewerID: viewerID)
        )
        receipts[command.id] = (command, receipt)
        didChange()
        return receipt
    }

    func snapshot(for matchID: MatchID) async throws -> MatchSnapshot {
        try Task.checkCancellation()
        return try requireMatch(matchID).snapshot(revision: revision, viewerID: viewerID)
    }

    func invalidations(for matchID: MatchID) async throws -> AsyncThrowingStream<SnapshotInvalidation, any Error> {
        _ = try requireMatch(matchID)
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
            guard match == nil else {
                throw MatchServiceError(code: .invalidPhase, message: "Already in a room.")
            }
        case .match(let matchID, let reference, let expectedRevision):
            _ = try requireMatch(matchID)
            guard reference == course.reference else {
                throw MatchServiceError(code: .incompatibleCourse, message: "Course version mismatch.")
            }
            guard expectedRevision == revision else {
                throw MatchServiceError(code: .staleRevision, message: "Refetch the snapshot.", currentRevision: revision)
            }
        }
    }

    private func apply(_ command: MatchCommand) throws {
        switch command.action {
        case .createRoom(let nickname, _, let algorithm):
            match = DemoMatch(
                course: course,
                code: Self.makeCode(),
                creatorID: viewerID,
                algorithm: algorithm,
                players: [DemoMatch.Player(id: viewerID, nickname: nickname)]
            )
        case .joinRoom:
            throw MatchServiceError(code: .roomNotFound, message: "Practice rooms can't be joined.")
        default:
            try match?.apply(command.action, by: viewerID, commandID: command.id)
        }
    }

    private func didChange() {
        for subscriber in subscribers.values {
            subscriber.yield(SnapshotInvalidation(matchID: ArenaFixtures.matchID, revision: revision))
        }
        scheduleOpponent()
    }

    private func scheduleOpponent() {
        opponentTask?.cancel()
        guard let match, let move = match.nextOpponentMove(viewerID: viewerID, opponentID: opponentID) else { return }
        let delay = match.phase == .lobby ? timing.lobby : timing.opponent
        opponentTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self.perform(move)
        }
    }

    private func perform(_ move: DemoMatch.OpponentMove) {
        switch move {
        case .join:
            match?.players.append(DemoMatch.Player(id: opponentID, nickname: "Practice Partner"))
        case .act(let action):
            do {
                try match?.apply(action, by: opponentID, commandID: UUID())
            } catch {
                return
            }
        }
        revision += 1
        didChange()
    }

    private func requireMatch(_ matchID: MatchID) throws -> DemoMatch {
        guard let match, matchID == ArenaFixtures.matchID else {
            throw MatchServiceError(code: .notMember, message: "Not a member of this match.")
        }
        return match
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers[id] = nil
    }

    private static func makeCode() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<6).map { _ in alphabet.randomElement()! })
    }
}
