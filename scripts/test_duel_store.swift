// Offline recovery tests for the actual iOS DuelStore, compiled by test_duel_store.sh.
// The transport protocol/default adapter below replace only network dependencies.
import AlgorithmArenaCore
import Foundation

@MainActor
protocol DuelService {
    func send(_ command: DuelCommand) async throws -> DuelSnapshot
    func snapshot(id: UUID) async throws -> DuelSnapshot
}

@MainActor
final class SupabaseDuelService: DuelService {
    func send(_ command: DuelCommand) async throws -> DuelSnapshot { throw Failure("Unexpected default network adapter") }
    func snapshot(id: UUID) async throws -> DuelSnapshot { throw Failure("Unexpected default network adapter") }
}

private struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

@MainActor
private final class MockService: DuelService {
    enum Reply {
        case value(DuelSnapshot)
        case failure(MatchServiceError)
        case disconnected
        case cancelled
        case deferred
    }
    var sendReplies: [Reply] = []
    var snapshotReplies: [Reply] = []
    private(set) var commands: [DuelCommand] = []
    private(set) var snapshotIDs: [UUID] = []
    private var sendContinuation: CheckedContinuation<DuelSnapshot, any Error>?
    private var snapshotContinuation: CheckedContinuation<DuelSnapshot, any Error>?
    var sendSuspended: Bool { sendContinuation != nil }
    var snapshotSuspended: Bool { snapshotContinuation != nil }

    func send(_ command: DuelCommand) async throws -> DuelSnapshot {
        commands.append(command)
        guard !sendReplies.isEmpty else { throw Failure("No send reply for \(command.action)") }
        let next = sendReplies.removeFirst()
        if case .deferred = next {
            return try await withCheckedThrowingContinuation { sendContinuation = $0 }
        }
        return try value(next)
    }

    func snapshot(id: UUID) async throws -> DuelSnapshot {
        snapshotIDs.append(id)
        guard !snapshotReplies.isEmpty else { throw Failure("No snapshot reply") }
        let next = snapshotReplies.removeFirst()
        if case .deferred = next {
            return try await withCheckedThrowingContinuation { snapshotContinuation = $0 }
        }
        return try value(next)
    }

    func finishSend(_ reply: Reply) {
        guard let continuation = sendContinuation else { return }
        sendContinuation = nil
        continuation.resume(with: Result { try value(reply) })
    }

    func takeSendCompletion() -> (Reply) -> Void {
        let continuation = sendContinuation!
        sendContinuation = nil
        return { reply in continuation.resume(with: Result { try self.value(reply) }) }
    }

    func finishSnapshot(_ reply: Reply) {
        guard let continuation = snapshotContinuation else { return }
        snapshotContinuation = nil
        continuation.resume(with: Result { try value(reply) })
    }

    private func value(_ reply: Reply) throws -> DuelSnapshot {
        switch reply {
        case .value(let snapshot): return snapshot
        case .failure(let error): throw error
        case .disconnected: throw URLError(.networkConnectionLost)
        case .cancelled: throw CancellationError()
        case .deferred: throw Failure("Cannot resolve a deferred reply twice")
        }
    }
}

private enum Fixture {
    static let roomID = UUID()
    static let hostID = UUID()
    static let guestID = UUID()
    static let stale = MatchServiceError(code: .staleRevision, message: "Changed on server")
    static let unavailable = MatchServiceError(code: .notMember, message: "No longer a member")

    static func snapshot(
        id: UUID = roomID, revision: Int = 9, phase: DuelPhase = .answering,
        round: Int = 0, submitted: Bool = false, ready: Bool = true,
        continued: Bool = false
    ) -> DuelSnapshot {
        DuelSnapshot(id: id, roomCode: "TST123", creatorID: hostID, viewerID: hostID,
                     revision: revision, phase: phase, roundIndex: round, roundCount: 3,
                     algorithm: .dijkstra,
                     players: [
                        DuelPlayer(id: hostID, nickname: "Host", ready: ready, score: 0,
                                   submitted: submitted, hasContinued: continued),
                        DuelPlayer(id: guestID, nickname: "Guest", ready: true, score: 0,
                                   submitted: false, hasContinued: false)
                     ])
    }
}

@MainActor
private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw Failure(message) }
}

@MainActor
private func waitUntil(_ condition: () -> Bool) async throws {
    for _ in 0..<1000 {
        if condition() { return }
        await Task.yield()
    }
    throw Failure("A controlled request never reached its suspension point")
}

@MainActor
private func boot(_ service: MockService, snapshot: DuelSnapshot = Fixture.snapshot(), file: URL? = nil) async -> DuelStore {
    service.sendReplies.insert(.value(snapshot), at: 0)
    let store = DuelStore(service: service, persistenceURL: file)
    await store.create(nickname: "Host", algorithm: .dijkstra)
    return store
}

@MainActor
private func lostReceiptRetriesTheExactCommand() async throws {
    let service = MockService()
    service.sendReplies = [.disconnected, .value(Fixture.snapshot(revision: 10, submitted: true))]
    let store = await boot(service)
    await store.perform(.submit, answer: "B")
    let uncertain = store.pending
    try expect(uncertain != nil && store.isOffline && !store.canAct, "A lost receipt must preserve the pending action and block fresh actions")
    await store.retry()
    try expect(service.commands.count == 3, "Expected create, first submit, duplicate submit")
    try expect(service.commands[1] == service.commands[2], "Retry must preserve every payload field and UUID")
    try expect(store.pending == nil && !store.isOffline && store.snapshot?.revision == 10, "Accepted duplicate must clear pending and reconcile latest snapshot")
}

@MainActor
private func staleRevisionReissuesOnlyTheSameValidRound() async throws {
    let service = MockService()
    service.sendReplies = [.failure(Fixture.stale), .value(Fixture.snapshot(revision: 11, submitted: true))]
    service.snapshotReplies = [.value(Fixture.snapshot(revision: 10))]
    let store = await boot(service)
    await store.perform(.submit, answer: "B")
    try expect(service.commands.count == 3, "A rejected command on the same open round should be reissued")
    let old = service.commands[1], replacement = service.commands[2]
    try expect(old.id != replacement.id, "A definitively rejected revision gets a fresh UUID")
    try expect(replacement.revision == 10 && replacement.answerNodeID == old.answerNodeID && replacement.action == old.action && replacement.matchID == old.matchID, "Only the revision and UUID may change during stale reconciliation")
    try expect(store.snapshot?.revision == 11 && store.pending == nil, "Reissued submit should settle")

    let invalidStates = [
        Fixture.snapshot(revision: 10, round: 1),
        Fixture.snapshot(revision: 10, phase: .reveal),
        Fixture.snapshot(revision: 10, submitted: true),
        Fixture.snapshot(revision: 10, phase: .finished)
    ]
    for latest in invalidStates {
        let service = MockService()
        service.sendReplies = [.failure(Fixture.stale)]
        service.snapshotReplies = [.value(latest)]
        let store = await boot(service)
        await store.perform(.submit, answer: "B")
        try expect(service.commands.count == 2, "Do not reissue across round/phase changes or after a submitted answer")
        try expect(store.pending == nil && store.snapshot == latest, "Refresh should reconcile the authoritative state")
    }
}

@MainActor
private func failedRefreshCannotReissueFromStaleLocalState() async throws {
    let service = MockService()
    service.sendReplies = [.failure(Fixture.stale)]
    service.snapshotReplies = [.disconnected]
    let store = await boot(service)
    await store.perform(.submit, answer: "B")
    try expect(service.commands.count == 2, "Failed refresh must not create a new command using the same stale revision")
    try expect(store.isOffline && store.pending == nil, "Known rejection stays distinct from an uncertain accepted command")
}

@MainActor
private func delayedSnapshotCannotRollBackAcceptedCommand() async throws {
    let service = MockService()
    service.sendReplies = [.value(Fixture.snapshot(revision: 12, submitted: true))]
    service.snapshotReplies = [.deferred]
    let store = await boot(service, snapshot: Fixture.snapshot(revision: 10))
    let read = Task { await store.refresh() }
    try await waitUntil { service.snapshotSuspended }
    await store.perform(.submit, answer: "B")
    service.finishSnapshot(.value(Fixture.snapshot(revision: 11)))
    await read.value
    try expect(store.snapshot?.revision == 12 && store.viewer?.submitted == true, "A stale poll may not roll back an accepted command")
}

@MainActor
private func delayedReceiptCannotRollBackNewerSnapshot() async throws {
    let service = MockService()
    service.sendReplies = [.deferred]
    service.snapshotReplies = [.value(Fixture.snapshot(revision: 12, submitted: true))]
    let store = await boot(service, snapshot: Fixture.snapshot(revision: 10))
    let send = Task { await store.perform(.submit, answer: "B") }
    try await waitUntil { service.sendSuspended }
    await store.refresh()
    service.finishSend(.value(Fixture.snapshot(revision: 11, submitted: true)))
    await send.value
    try expect(store.snapshot?.revision == 12 && store.pending == nil && !store.isBusy, "An old receipt must settle pending without rolling state backward")
}

@MainActor
private func pendingCommandSurvivesProcessRestart() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("duel-store-restart-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("ActiveDuel.json")
    let firstService = MockService()
    firstService.sendReplies = [.disconnected]
    let original = await boot(firstService, file: file)
    await original.perform(.submit, answer: "B")
    let pending = original.pending
    let newService = MockService()
    newService.sendReplies = [.value(Fixture.snapshot(revision: 10, submitted: true))]
    let restored = DuelStore(service: newService, persistenceURL: file)
    try expect(restored.pending == pending && restored.snapshot == original.snapshot && restored.isOffline, "Disk restore must retain the exact pending payload and last confirmed state")
    await restored.retry()
    try expect(newService.commands.first == pending && restored.pending == nil, "Restart retry must use the original command UUID")
    let freshService = MockService()
    freshService.snapshotReplies = [.value(Fixture.snapshot(revision: 10, submitted: true))]
    let confirmed = DuelStore(service: freshService, persistenceURL: file)
    try expect(confirmed.pending == nil && confirmed.snapshot?.revision == 10 && confirmed.isOffline, "Confirmed restore waits for server verification")
    await confirmed.refresh()
    try expect(!confirmed.isOffline && confirmed.canAct, "Successful verification enables the restored room")
}

@MainActor
private func successfulLeaveClearsActivePersistence() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("duel-store-leave-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("ActiveDuel.json")
    let service = MockService()
    service.sendReplies = [.value(Fixture.snapshot(revision: 10, phase: .incomplete))]
    let store = await boot(service, file: file)
    await store.perform(.leave)
    try expect(store.snapshot == nil && store.pending == nil && !store.isOffline && !store.isBusy, "Leave must clear the active room")
    let restored = DuelStore(service: MockService(), persistenceURL: file)
    try expect(restored.snapshot == nil && restored.pending == nil, "A left room cannot return after restart")
}

@MainActor
private func leavingStillSucceedsWhenTheOpponentAdvancesTheRound() async throws {
    let service = MockService()
    service.sendReplies = [
        .failure(Fixture.stale),
        .value(Fixture.snapshot(revision: 11, phase: .incomplete, round: 1))
    ]
    service.snapshotReplies = [.value(Fixture.snapshot(revision: 10, round: 1))]
    let store = await boot(service, snapshot: Fixture.snapshot(phase: .reveal, continued: true))
    await store.perform(.leave)
    try expect(service.commands.count == 3, "Leaving remains valid when the opponent moves to the next round")
    try expect(service.commands[2].action == .leave && service.commands[2].revision == 10,
               "Reissue leave against the refreshed revision, regardless of round")
    try expect(store.snapshot == nil && store.pending == nil && !store.isBusy,
               "The user must leave rather than silently remain in the advanced round")
}

@MainActor
private func oldRoomFailureCannotClearNewRoom() async throws {
    let service = MockService()
    let newID = UUID()
    service.snapshotReplies = [.deferred]
    service.sendReplies = [.value(Fixture.snapshot(id: newID, revision: 1, phase: .lobby))]
    let store = await boot(service, snapshot: Fixture.snapshot(phase: .finished))
    let oldRead = Task { await store.refresh() }
    try await waitUntil { service.snapshotSuspended }
    store.closeResult()
    await store.create(nickname: "Host", algorithm: .dijkstra)
    service.finishSnapshot(.failure(Fixture.unavailable))
    await oldRead.value
    try expect(store.snapshot?.id == newID && store.error == nil, "A failure from a departed room must not clear a new room or surface an old error")
}

@MainActor
private func staleActionCannotReissueAfterClosingAndRejoiningTheSameRoom() async throws {
    let service = MockService()
    let rejoined = Fixture.snapshot(revision: 11, phase: .finished)
    service.sendReplies = [
        .failure(Fixture.stale),
        .value(rejoined),
        .value(Fixture.snapshot(revision: 12, phase: .lobby))
    ]
    service.snapshotReplies = [.deferred]
    let store = await boot(service, snapshot: Fixture.snapshot(phase: .finished))
    let oldRematch = Task { await store.perform(.rematch) }
    try await waitUntil { service.snapshotSuspended }
    store.closeResult()
    await store.join(nickname: "Host", code: "TST123")
    service.finishSnapshot(.value(Fixture.snapshot(revision: 10, phase: .finished)))
    await oldRematch.value
    try expect(service.commands.count == 3, "A stale action from a closed result must not reissue after rejoining the same room")
    try expect(store.snapshot == rejoined, "Old rematch intent must not alter the newly joined session")
}

@MainActor
private func lateRematchReceiptCannotResurrectClosedRoom() async throws {
    let service = MockService()
    service.sendReplies = [.deferred]
    let store = await boot(service, snapshot: Fixture.snapshot(phase: .finished))
    let rematch = Task { await store.perform(.rematch) }
    try await waitUntil { service.sendSuspended }
    store.closeResult()
    service.finishSend(.value(Fixture.snapshot(revision: 10, phase: .lobby)))
    await rematch.value
    try expect(store.snapshot == nil && store.pending == nil && !store.isBusy, "A closed result must not reopen when an old rematch request completes")
}

@MainActor
private func concurrentTapsAndCancellationKeepOnePendingCommand() async throws {
    let service = MockService()
    service.sendReplies = [.deferred, .value(Fixture.snapshot(revision: 10, submitted: true))]
    let store = await boot(service)
    let first = Task { await store.perform(.submit, answer: "B") }
    try await waitUntil { service.sendSuspended }
    await store.perform(.submit, answer: "A")
    try expect(service.commands.count == 2, "Rapid taps cannot send a second payload")
    service.finishSend(.cancelled)
    await first.value
    let pending = store.pending
    try expect(pending?.answerNodeID == "B", "Cancellation is uncertain; preserve the first answer")
    await store.retry()
    try expect(service.commands.last == pending && store.pending == nil, "A cancelled request must retry idempotently")
}

@MainActor
private func closingPendingRematchAllowsNewRoomWithoutOldBusyCleanup() async throws {
    // Each outcome must be ignored once its room has been closed, including the
    // busy flag: a newer request can already be using that flag by then.
    for oldReply in [MockService.Reply.value(Fixture.snapshot(revision: 10, phase: .lobby)),
                     .failure(Fixture.unavailable), .disconnected] {
        let service = MockService()
        service.sendReplies = [.deferred]
        let store = await boot(service, snapshot: Fixture.snapshot(phase: .finished))
        let rematch = Task { await store.perform(.rematch) }
        try await waitUntil { service.sendSuspended }
        store.closeResult()
        try expect(store.canAct, "Closing a result must release controls even while its old request is unresolved")

        // Retain the old continuation before suspending the next request.
        let completeOld = service.takeSendCompletion()
        service.sendReplies = [.deferred]
        let create = Task { await store.create(nickname: "Host", algorithm: .dijkstra) }
        try await waitUntil { service.sendSuspended }
        completeOld(oldReply)
        await rematch.value
        try expect(store.isBusy && store.pending?.action == .create && store.error == nil,
                   "An obsolete response must not clear the new request's busy state or pending command")
        let newRoom = Fixture.snapshot(id: UUID(), revision: 1, phase: .lobby)
        service.finishSend(.value(newRoom))
        await create.value
        try expect(store.snapshot == newRoom && store.canAct, "The new room must settle normally")
    }
}

@main
private enum DuelStoreTests {
    @MainActor
    static func main() async {
        let tests: [(String, @MainActor () async throws -> Void)] = [
            ("closed rematch cannot block or unlock a new request", closingPendingRematchAllowsNewRoomWithoutOldBusyCleanup),
            ("lost receipt retries exact UUID and payload", lostReceiptRetriesTheExactCommand),
            ("stale revision reissues only valid same-round command", staleRevisionReissuesOnlyTheSameValidRound),
            ("failed refresh does not reissue stale state", failedRefreshCannotReissueFromStaleLocalState),
            ("delayed poll cannot roll state backward", delayedSnapshotCannotRollBackAcceptedCommand),
            ("delayed receipt cannot roll state backward", delayedReceiptCannotRollBackNewerSnapshot),
            ("pending command survives process restart", pendingCommandSurvivesProcessRestart),
            ("leave clears active persisted state", successfulLeaveClearsActivePersistence),
            ("leave survives opponent advancing the round", leavingStillSucceedsWhenTheOpponentAdvancesTheRound),
            ("old room error cannot clear new room", oldRoomFailureCannotClearNewRoom),
            ("stale action cannot affect rejoined same room", staleActionCannotReissueAfterClosingAndRejoiningTheSameRoom),
            ("late rematch receipt cannot resurrect closed result", lateRematchReceiptCannotResurrectClosedRoom),
            ("concurrent taps and cancellation preserve one payload", concurrentTapsAndCancellationKeepOnePendingCommand)
        ]
        var failures = 0
        for (name, test) in tests {
            do {
                try await test()
                print("PASS \(name)")
            } catch {
                failures += 1
                print("FAIL \(name): \(error)")
            }
        }
        print("\(tests.count - failures)/\(tests.count) DuelStore recovery checks passed")
        if failures > 0 { exit(1) }
    }
}
