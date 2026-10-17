import AlgorithmArenaCore
import AlgorithmArenaFixtures
import Foundation
import Testing

@Test(arguments: [false, true]) func homeCanCreateOrJoinRoom(join: Bool) async throws {
  let action: MatchAction =
    join
    ? .joinRoom(code: "ARENA1", nickname: "Alex")
    : .createRoom(nickname: "Alex", course: ArenaFixtures.courseReference, algorithm: .dijkstra)
  let service: any MatchService = ScriptedMatchService(transitions: [
    .init(action: action, snapshot: ArenaFixtures.snapshot(.lobby, algorithm: .dijkstra))
  ])
  await #expect(throws: MatchServiceError.self) {
    try await service.snapshot(for: ArenaFixtures.matchID)
  }
  let command = MatchCommand(id: UUID(), scope: .roomEntry, action: action)
  let receipt = try await service.send(command)
  #expect(receipt.snapshot.room.phase == .lobby)
  #expect(try await service.send(command) == receipt)
  #expect(try await service.snapshot(for: ArenaFixtures.matchID) == receipt.snapshot)
}

@Test(arguments: AlgorithmKind.allCases)
func uncertainSubmissionRetriesExactlyOnceWithoutRewinding(algorithm: AlgorithmKind) async throws {
  let original = ArenaFixtures.submissionCommand(algorithm)
  let route = MatchCommand(
    id: UUID(),
    scope: .match(
      matchID: ArenaFixtures.matchID, course: ArenaFixtures.courseReference, expectedRevision: 9),
    action: .chooseRoute(branch: .standard))
  let concrete = ScriptedMatchService(
    initial: ArenaFixtures.snapshot(.active, algorithm: algorithm),
    transitions: [
      .init(
        action: original.action,
        snapshot: ArenaFixtures.snapshot(.routeChoice, algorithm: algorithm)),
      .init(
        action: route.action,
        snapshot: ArenaFixtures.snapshot(.pendingFeedback, algorithm: algorithm)),
    ])
  let service: any MatchService = concrete  // Same existential the live adapter will satisfy.
  let accepted = try await service.send(original)
  #expect(accepted.acceptedRevision == 9)
  let latest = try await service.send(route)
  let retried = try await service.send(original)
  #expect(retried == accepted)
  #expect(try await service.snapshot(for: ArenaFixtures.matchID) == latest.snapshot)
  #expect(!retried.snapshot.supersedes(latest.snapshot))
  let conflict = MatchCommand(id: original.id, scope: original.scope, action: .leave)
  await #expect(
    throws: MatchServiceError(
      code: .idempotencyConflict, message: "The command ID was already used with another payload.")
  ) {
    try await service.send(conflict)
  }
  let stale = MatchCommand(id: UUID(), scope: original.scope, action: original.action)
  await #expect(
    throws: MatchServiceError(
      code: .staleRevision, message: "Refetch the snapshot.", currentRevision: 10)
  ) {
    try await service.send(stale)
  }
}

@Test func serviceRejectsWrongMatchCourseAndUnscriptedActions() async throws {
  let service: any MatchService = ScriptedMatchService(
    initial: ArenaFixtures.snapshot(.active, algorithm: .dijkstra))
  await #expect(throws: MatchServiceError.self) { try await service.snapshot(for: "another-match") }
  await #expect(throws: MatchServiceError.self) {
    try await service.invalidations(for: "another-match")
  }
  let incompatible = MatchCommand(
    id: UUID(),
    scope: .match(
      matchID: ArenaFixtures.matchID,
      course: .init(id: ArenaFixtures.courseReference.id, version: "outdated"), expectedRevision: 8),
    action: .leave)
  await #expect(
    throws: MatchServiceError(
      code: .incompatibleCourse, message: "Refresh the course before continuing.")
  ) {
    try await service.send(incompatible)
  }
  await #expect(throws: MatchServiceError.self) {
    try await service.send(ArenaFixtures.submissionCommand(.dijkstra))
  }
}

@Test func mockRejectsMidMatchAlgorithmChanges() async throws {
  let command = ArenaFixtures.submissionCommand(.dijkstra)
  let service = ScriptedMatchService(
    initial: ArenaFixtures.snapshot(.active, algorithm: .dijkstra),
    transitions: [
      .init(
        action: command.action, snapshot: ArenaFixtures.snapshot(.routeChoice, algorithm: .aStar))
    ])
  await #expect(throws: MatchServiceError.self) { try await service.send(command) }
  #expect(try await service.snapshot(for: ArenaFixtures.matchID).room.algorithm == .dijkstra)
}

@Test(.timeLimit(.minutes(1))) func invalidationsPromptRefetchAndEndCleanly() async throws {
  let command = ArenaFixtures.submissionCommand(.dijkstra)
  let service = ScriptedMatchService(
    initial: ArenaFixtures.snapshot(.active, algorithm: .dijkstra),
    transitions: [
      .init(
        action: command.action, snapshot: ArenaFixtures.snapshot(.routeChoice, algorithm: .dijkstra)
      )
    ])
  var iterator = try await service.invalidations(for: ArenaFixtures.matchID).makeAsyncIterator()
  #expect(try await iterator.next()?.revision == 8)
  _ = try await service.send(command)
  #expect(
    try await iterator.next() == SnapshotInvalidation(matchID: ArenaFixtures.matchID, revision: 9))
  #expect(try await service.snapshot(for: ArenaFixtures.matchID).revision == 9)
  await service.finish()
  #expect(try await iterator.next() == nil)
}
