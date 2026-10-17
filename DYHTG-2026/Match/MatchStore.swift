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
        case results
    }

    enum Mode {
        case live
        case practice
    }

    private(set) var snapshot: MatchSnapshot?
    private(set) var pendingCommand: MatchCommand?
    private(set) var mode: Mode?
    private(set) var isSending = false
    private(set) var isReconnecting = false
    private(set) var challenges: [ChallengeID: ChallengeDefinition] = [:]
    var drafts: [ChallengeID: ChallengeDraft] = [:]
    var actionError: ActionError?

    let course: CourseGraph
    private let liveService: () -> any MatchService
    private let practiceService: () -> any MatchService
    private let persistence: MatchPersistence?
    private var service: (any MatchService)?
    private var observation: Task<Void, Never>?

    init(
        course: CourseGraph,
        liveService: @escaping () -> any MatchService,
        practiceService: @escaping () -> any MatchService,
        persistence: MatchPersistence? = nil
    ) {
        self.course = course
        self.liveService = liveService
        self.practiceService = practiceService
        self.persistence = persistence
        restore()
    }

    var route: Route {
        guard let snapshot else { return .home }
        switch snapshot.room.phase {
        case .lobby: return .lobby
        case .finished, .incomplete: return .results
        case .practice, .active, .awaitingFinish: return .match
        }
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

    var isCreator: Bool {
        guard let snapshot else { return false }
        return snapshot.room.creatorID == snapshot.viewer.playerID
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

    func createRoom(nickname: String, algorithm: AlgorithmKind, mode: Mode) async throws {
        try await enterRoom(.createRoom(nickname: nickname, course: course.reference, algorithm: algorithm), mode: mode)
    }

    func joinRoom(code: String, nickname: String) async throws {
        try await enterRoom(.joinRoom(code: code, nickname: nickname), mode: .live)
    }

    func perform(_ action: MatchAction) async {
        await perform(action, reconciling: true)
    }

    func retryPendingCommand() async {
        guard let pendingCommand else { return }
        await deliver(pendingCommand)
    }

    func discardPendingCommand() {
        pendingCommand = nil
        actionError = nil
        save()
    }

    func leave() async {
        if route == .lobby || route == .match {
            await perform(.leave)
        }
        reset()
    }

    func refresh() async {
        guard let service, let matchID = snapshot?.room.matchID else { return }
        do {
            apply(try await service.snapshot(for: matchID))
            isReconnecting = false
        } catch let error as MatchServiceError where error.code == .notMember || error.code == .unauthenticated {
            reset()
            actionError = ActionError(
                title: "Match Unavailable",
                message: "This match can no longer be opened on this iPhone."
            )
        } catch {
            isReconnecting = true
        }
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

    private func enterRoom(_ action: MatchAction, mode: Mode) async throws {
        guard !isSending else { return }
        let service = mode == .live ? liveService() : practiceService()
        let command = MatchCommand(id: UUID(), scope: .roomEntry, action: action)
        isSending = true
        defer { isSending = false }
        let receipt = try await service.send(command)
        guard receipt.snapshot.room.course == course.reference else {
            throw MatchServiceError(code: .incompatibleCourse, message: "The room uses another course version.")
        }
        self.service = service
        self.mode = mode
        apply(receipt.snapshot)
        observe(receipt.snapshot.room.matchID)
    }

    @discardableResult
    private func deliver(_ command: MatchCommand) async -> MatchServiceError? {
        guard let service else { return nil }
        pendingCommand = command
        save()
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
            actionError = ActionError(error, during: command.action)
            save()
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
        save()
    }

    private func observe(_ matchID: MatchID) {
        observation?.cancel()
        observation = Task { [weak self] in
            while !Task.isCancelled {
                guard let service = self?.service else { return }
                do {
                    let stream = try await service.invalidations(for: matchID)
                    await self?.refresh()
                    for try await invalidation in stream {
                        guard let self else { return }
                        if let current = self.snapshot, invalidation.revision <= current.revision { continue }
                        await self.refresh()
                    }
                } catch is CancellationError {
                    return
                } catch {
                    self?.isReconnecting = true
                }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func restore() {
        guard let state = persistence?.load() else { return }
        snapshot = state.lastConfirmedSnapshot
        pendingCommand = state.pendingCommand
        mode = .live
        service = liveService()
        isReconnecting = true
        for challenge in state.lastConfirmedSnapshot.viewer.availableChallenges {
            challenges[challenge.id] = challenge
        }
        observe(state.lastConfirmedSnapshot.room.matchID)
        Task {
            await refresh()
            if pendingCommand != nil {
                await retryPendingCommand()
            }
        }
    }

    private func save() {
        guard mode == .live, let persistence else { return }
        guard let snapshot, route != .results else {
            persistence.clear()
            return
        }
        persistence.save(ReconnectState(lastConfirmedSnapshot: snapshot, pendingCommand: pendingCommand))
    }

    private func reset() {
        observation?.cancel()
        observation = nil
        service = nil
        mode = nil
        snapshot = nil
        challenges = [:]
        drafts = [:]
        pendingCommand = nil
        actionError = nil
        isReconnecting = false
        persistence?.clear()
    }
}
