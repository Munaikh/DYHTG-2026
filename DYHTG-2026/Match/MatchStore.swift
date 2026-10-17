import AlgorithmArenaCore
import Foundation
import Observation

@MainActor
@Observable
final class MatchStore {
    enum Route: Equatable {
        case home
        case lobby
        case match
    }

    private(set) var snapshot: MatchSnapshot?
    private(set) var pendingCommand: MatchCommand?
    private(set) var isSending = false
    private(set) var isReconnecting = false
    private(set) var challenges: [ChallengeID: ChallengeDefinition] = [:]
    var drafts: [ChallengeID: ChallengeDraft] = [:]
    var actionError: ActionError?

    let course: CourseGraph
    private let makeService: () -> any MatchService
    private var service: (any MatchService)?
    private var observation: Task<Void, Never>?

    init(course: CourseGraph, makeService: @escaping () -> any MatchService) {
        self.course = course
        self.makeService = makeService
    }

    var route: Route {
        guard let snapshot else { return .home }
        return snapshot.room.phase == .lobby ? .lobby : .match
    }

    var viewer: PlayerProgress? {
        snapshot.flatMap { snapshot in snapshot.room.players.first { $0.id == snapshot.viewer.playerID } }
    }

    var opponent: PlayerProgress? {
        snapshot.flatMap { snapshot in snapshot.room.players.first { $0.id != snapshot.viewer.playerID } }
    }

    var availableChallenge: ChallengeDefinition? {
        snapshot?.viewer.availableChallenges.first
    }

    func feedback(for id: ChallengeID) -> FeedbackAvailability? {
        snapshot?.viewer.feedback.first { $0.challengeID == id }
    }

    func submission(for id: ChallengeID) -> PrivateSubmission? {
        snapshot?.viewer.submissions.first { $0.challengeID == id }
    }

    func submit(_ answer: SubmittedAnswer, to challenge: ChallengeDefinition) async {
        await perform(.submitAnswer(challengeID: challenge.id, answer: answer))
    }

    var isCreator: Bool {
        guard let snapshot else { return false }
        return snapshot.room.creatorID == snapshot.viewer.playerID
    }

    func createRoom(nickname: String, algorithm: AlgorithmKind) async throws {
        try await enterRoom(.createRoom(nickname: nickname, course: course.reference, algorithm: algorithm))
    }

    func joinRoom(code: String, nickname: String) async throws {
        try await enterRoom(.joinRoom(code: code, nickname: nickname))
    }

    func perform(_ action: MatchAction) async {
        await perform(action, reconciling: true)
    }

    private func perform(_ action: MatchAction, reconciling: Bool) async {
        guard let snapshot, pendingCommand == nil else { return }
        let command = MatchCommand(
            id: UUID(),
            scope: .match(
                matchID: snapshot.room.matchID,
                course: snapshot.room.course,
                expectedRevision: snapshot.revision
            ),
            action: action
        )
        let rejection = await deliver(command)
        guard reconciling, rejection?.code == .staleRevision else { return }
        await refresh()
        actionError = nil
        if isStillWanted(action) {
            await perform(action, reconciling: false)
        }
    }

    func retryPendingCommand() async {
        guard let pendingCommand else { return }
        await deliver(pendingCommand)
    }

    func discardPendingCommand() {
        pendingCommand = nil
        actionError = nil
    }

    func leave() async {
        if snapshot != nil {
            await perform(.leave)
        }
        reset()
    }

    func refresh() async {
        guard let service, let matchID = snapshot?.room.matchID else { return }
        do {
            let latest = try await service.snapshot(for: matchID)
            apply(latest)
            isReconnecting = false
        } catch {
            isReconnecting = true
        }
    }

    private func enterRoom(_ action: MatchAction) async throws {
        guard !isSending else { return }
        let service = makeService()
        let command = MatchCommand(id: UUID(), scope: .roomEntry, action: action)
        isSending = true
        defer { isSending = false }
        let receipt = try await service.send(command)
        self.service = service
        apply(receipt.snapshot)
        observe(receipt.snapshot.room.matchID)
    }

    @discardableResult
    private func deliver(_ command: MatchCommand) async -> MatchServiceError? {
        guard let service else { return nil }
        pendingCommand = command
        isSending = true
        defer { isSending = false }
        do {
            let receipt = try await service.send(command)
            pendingCommand = nil
            actionError = nil
            apply(receipt.snapshot)
            return nil
        } catch let error as MatchServiceError {
            pendingCommand = nil
            actionError = ActionError(error)
            return error
        } catch is CancellationError {
            return nil
        } catch {
            actionError = .connectionLost
            return nil
        }
    }

    private func isStillWanted(_ action: MatchAction) -> Bool {
        guard let snapshot, let viewer else { return false }
        switch action {
        case .selectAlgorithm(let algorithm):
            return snapshot.room.phase == .lobby && snapshot.room.algorithm != algorithm
        case .confirmAlgorithm(let algorithm):
            return snapshot.room.algorithm == algorithm && !viewer.algorithmConfirmed
        case .setReady(let ready):
            return viewer.ready != ready
        case .start:
            return snapshot.room.phase == .lobby
        case .confirmArrival(let node, _):
            return !viewer.hasArrived(at: node)
        case .chooseRoute:
            return viewer.routeChoice == nil
        case .submitAnswer(let challengeID, _):
            return availableChallenge?.id == challengeID && submission(for: challengeID) == nil
        case .finish:
            return viewer.stage != .finished
        case .leave:
            return true
        case .createRoom, .joinRoom:
            return false
        }
    }

    private func apply(_ latest: MatchSnapshot) {
        if let snapshot, latest.room.matchID == snapshot.room.matchID, !latest.supersedes(snapshot) {
            return
        }
        snapshot = latest
        for challenge in latest.viewer.availableChallenges {
            challenges[challenge.id] = challenge
        }
    }

    private func observe(_ matchID: MatchID) {
        observation?.cancel()
        observation = Task { [weak self] in
            guard let service = self?.service else { return }
            do {
                let stream = try await service.invalidations(for: matchID)
                for try await invalidation in stream {
                    guard let self else { return }
                    if let current = self.snapshot, invalidation.revision <= current.revision { continue }
                    await self.refresh()
                }
            } catch {
                self?.isReconnecting = true
            }
        }
    }

    private func reset() {
        observation?.cancel()
        observation = nil
        service = nil
        snapshot = nil
        challenges = [:]
        drafts = [:]
        pendingCommand = nil
        actionError = nil
        isReconnecting = false
    }
}
