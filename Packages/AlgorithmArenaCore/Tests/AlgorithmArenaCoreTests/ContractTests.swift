import AlgorithmArenaCore
import AlgorithmArenaFixtures
import Foundation
import Testing

private func roundTrip<T: Codable & Equatable>(_ value: T) throws {
  let data = try ContractJSON.encoder().encode(value)
  #expect(try ContractJSON.decoder().decode(T.self, from: data) == value)
}

private func keys(in value: Any) -> Set<String> {
  if let object = value as? [String: Any] {
    return object.values.reduce(into: Set(object.keys)) { $0.formUnion(keys(in: $1)) }
  }
  if let array = value as? [Any] {
    return array.reduce(into: Set<String>()) { $0.formUnion(keys(in: $1)) }
  }
  return []
}

private func jsonKeys<T: Encodable>(_ value: T) throws -> Set<String> {
  keys(in: try JSONSerialization.jsonObject(with: ContractJSON.encoder().encode(value)))
}

@Test(arguments: AlgorithmKind.allCases, MatchFixture.allCases)
func snapshotsRoundTrip(algorithm: AlgorithmKind, fixture: MatchFixture) throws {
  let snapshot = ArenaFixtures.snapshot(fixture, algorithm: algorithm)
  try roundTrip(snapshot)
  #expect(snapshot.room.algorithm == algorithm)
  #expect(snapshot.room.course == ArenaFixtures.courseReference)
  #expect(snapshot.room.players.count == 2)
  #expect(Set(snapshot.room.players.map(\.id)).count == 2)
  #expect(snapshot.viewer.playerID == ArenaFixtures.playerID)
  #expect(snapshot.viewer.availableChallenges.allSatisfy { $0.algorithm == algorithm })
  let earlierScenarios = snapshot.viewer.feedback.compactMap { feedback -> ScenarioID? in
    if case .released(let content) = feedback { return content.trace.scenarioID }
    return nil
  }
  #expect(
    snapshot.viewer.availableChallenges.allSatisfy { !earlierScenarios.contains($0.scenario.id) })
  for progress in snapshot.room.players {
    #expect(progress.releasedScore >= 0)
    #expect(progress.pendingRewardMaximum >= 0)
    #expect(progress.remainingAvailablePoints >= 0)
  }
}

@Test(arguments: AlgorithmKind.allCases, ChallengeSlot.allCases)
func challengesHaveNoAnswerKey(algorithm: AlgorithmKind, slot: ChallengeSlot) throws {
  let challenge = ArenaFixtures.challenge(slot, algorithm)
  try roundTrip(challenge)
  let forbidden: Set<String> = [
    "correctAnswer", "isCorrect", "explanation", "workedSteps", "trace", "awardedPoints",
  ]
  #expect(try jsonKeys(challenge).isDisjoint(with: forbidden))
  #expect(
    challenge.feedbackGate
      == (slot == .first || slot == .third ? .afterBothSubmissions : .immediate))
  #expect(
    challenge.maximumPoints
      == (slot == .practice || slot == .learningCheck ? 0 : slot == .bonusMiddle ? 40 : 20))
}

@Test func courseHasTwoCompleteBranchesAndConfigurableArrivalThresholds() throws {
  let course = ArenaFixtures.course
  try roundTrip(course)
  #expect(course.readiness == .synthetic)
  #expect(course.arrivalPolicy.radiusMetres == 25)
  #expect(course.arrivalPolicy.maximumFixAgeSeconds == 10)
  #expect(course.arrivalPolicy.maximumHorizontalAccuracyMetres == 20)
  #expect(Set(course.nodes.map(\.id)).count == course.nodes.count)
  #expect(Set(course.edges.map(\.id)).count == course.edges.count)
  #expect(Set(course.routes.map(\.branch)) == Set(RouteBranch.allCases))
  for route in course.routes {
    var visited = [course.stops.start]
    var sum = 0
    for edgeID in route.edgeIDs {
      let edge = try #require(course.edges.first { $0.id == edgeID })
      let from = try #require(course.nodes.first { $0.id == edge.from })
      let to = try #require(course.nodes.first { $0.id == edge.to })
      #expect(edge.from == visited.last)
      #expect(edge.polyline.first == from.coordinate)
      #expect(edge.polyline.last == to.coordinate)
      #expect(edge.costMetres >= 0)
      visited.append(edge.to)
      sum += edge.costMetres
    }
    #expect(
      visited == [
        course.stops.start, course.stops.first,
        route.branch == .standard ? course.stops.standardMiddle : course.stops.bonusMiddle,
        course.stops.third, course.stops.finish,
      ])
    #expect(sum == route.distanceMetres)
    #expect((500...800).contains(sum))
  }
  #expect(course.routes[1].distanceMetres - course.routes[0].distanceMetres == 75)
}

@Test(arguments: AlgorithmKind.allCases)
func pendingFeedbackCannotRevealSharedAnswerOrReward(algorithm: AlgorithmKind) throws {
  let pending = ArenaFixtures.snapshot(.pendingFeedback, algorithm: algorithm)
  let forbidden: Set<String> = [
    "answer", "answers", "correctAnswer", "isCorrect", "awardedPoints", "trace",
    "explanation", "workedSteps", "coordinate", "horizontalAccuracyMetres", "submissions",
  ]
  #expect(try jsonKeys(pending.room).isDisjoint(with: forbidden))
  #expect(pending.room.players.allSatisfy { $0.releasedScore == 0 })
  #expect(pending.room.players[0].pendingRewardMaximum == 20)
  #expect(
    pending.room.players[0].completedChallengeIDs == [ArenaFixtures.challengeID(.first, algorithm)])
  #expect(pending.viewer.availableChallenges.isEmpty)
  let shared = try #require(pending.viewer.feedback.last)
  guard case .pending(let challengeID) = shared else {
    Issue.record("Expected withheld feedback")
    return
  }
  #expect(challengeID == ArenaFixtures.challengeID(.first, algorithm))
  #expect(try jsonKeys(shared) == ["pending", "challengeID"])
  #expect(pending.viewer.submissions.last?.answer == ArenaFixtures.correctAnswer(.first, algorithm))
  let released = ArenaFixtures.snapshot(.middleStandard, algorithm: algorithm)
  guard case .released(let feedback) = try #require(released.viewer.feedback.last) else {
    Issue.record("Expected both submissions to unlock shared feedback")
    return
  }
  #expect(feedback.answers.count == 2)
  #expect(feedback.answers[1].isCorrect == false)
  #expect(feedback.answers[1].awardedPoints == 0)
  #expect(released.room.players[1].completedChallengeIDs.contains(challengeID))
  #expect(released.room.players[0].releasedScore == 20)
}

@Test(arguments: AlgorithmKind.allCases)
func sharedThirdScenarioDoesNotDependOnEarlierBranch(algorithm: AlgorithmKind) throws {
  let standard = ArenaFixtures.snapshot(.sharedThirdStandard, algorithm: algorithm)
  let bonus = ArenaFixtures.snapshot(.sharedThirdBonus, algorithm: algorithm)
  #expect(standard.room.players[0].routeChoice != bonus.room.players[0].routeChoice)
  #expect(standard.viewer.availableChallenges == bonus.viewer.availableChallenges)
  #expect(
    standard.viewer.availableChallenges.first?.scenario == ArenaFixtures.scenario(for: .third))
}

@Test(arguments: AlgorithmKind.allCases)
func resultsAndUnscoredLearningCheckAreConsistent(algorithm: AlgorithmKind) throws {
  for fixture in [MatchFixture.finished, .draw, .incomplete] {
    let snapshot = ArenaFixtures.snapshot(fixture, algorithm: algorithm)
    let result = try #require(snapshot.room.result)
    if fixture != .incomplete {
      #expect(snapshot.viewer.availableChallenges.first?.slot == .learningCheck)
    }
    let standings: [Standing]
    switch result {
    case .winner(let player, let values):
      #expect(player == ArenaFixtures.playerID)
      #expect(values[0].score > values[1].score)
      standings = values
    case .draw(let values):
      #expect(values[0].score == values[1].score)
      standings = values
    case .incomplete(let departed, let values):
      #expect(departed == ArenaFixtures.opponentID)
      #expect(snapshot.room.phase == .incomplete)
      standings = values
    }
    for standing in standings {
      #expect(standing.score == standing.awards.reduce(0) { $0 + $1.points })
      #expect(
        standing.score == snapshot.room.players.first { $0.id == standing.playerID }?.releasedScore)
    }
  }
  let before = ArenaFixtures.snapshot(.learningCheck, algorithm: algorithm)
  let after = ArenaFixtures.snapshot(.learningCheckAnswered, algorithm: algorithm)
  #expect(before.room == after.room)
  #expect(before.room.result == nil)  // The other player is still walking.
  #expect(after.viewer.learningCheck != nil)
  #expect(after.room.players[0].releasedScore == 80)
  #expect(before.viewer.availableChallenges.first?.scenario.id != ArenaFixtures.scenario().id)
  #expect(before.viewer.availableChallenges.first?.maximumPoints == 0)
}

@Test(arguments: AlgorithmKind.allCases, ChallengeSlot.allCases)
func authoredTraceReferencesAndPrioritiesAreConsistent(
  algorithm: AlgorithmKind, slot: ChallengeSlot
) throws {
  let trace = ArenaFixtures.trace(algorithm, slot: slot)
  let graph = ArenaFixtures.scenario(for: slot)
  try roundTrip(trace)
  #expect(trace.scenarioID == graph.id)
  #expect(trace.steps.map(\.index) == Array(trace.steps.indices))
  #expect(graph.nodes.first { $0.id == graph.goal }?.heuristic == 0)
  for edge in graph.edges {
    let from = try #require(graph.nodes.first { $0.id == edge.from })
    let to = try #require(graph.nodes.first { $0.id == edge.to })
    #expect(from.heuristic <= edge.cost + to.heuristic)
  }
  for step in trace.steps {
    #expect(Set(step.state.frontier).isDisjoint(with: step.state.settled))
    let costs = Dictionary(uniqueKeysWithValues: step.state.costs.map { ($0.nodeID, $0) })
    let sorted = step.state.frontier.sorted {
      let left = costs[$0]!
      let right = costs[$1]!
      let l = left.g! + (algorithm == .aStar ? left.h : 0)
      let r = right.g! + (algorithm == .aStar ? right.h : 0)
      return l == r ? $0 < $1 : l < r
    }
    #expect(step.state.frontier == sorted)
    if case .relax(let from, let to, let old, let candidate, let accepted) = step.event {
      let edge = try #require(graph.edges.first { $0.from == from && $0.to == to })
      #expect(candidate == costs[from]!.g! + edge.cost)
      #expect(accepted == (old == nil || candidate < old!))
      #expect(costs[to]?.predecessor == from)
    }
  }
  guard case .route(let nodes, let cost) = trace.outcome else {
    Issue.record("Expected a route")
    return
  }
  #expect(cost == graph.edges[0].cost + graph.edges[2].cost)
  #expect(nodes.first == graph.source && nodes.last == graph.goal)
  if algorithm == .dijkstra {
    let explored = try #require(trace.steps.last).state.settled
    #expect(explored.contains(graph.nodes[2].id))
    #expect(!nodes.contains(graph.nodes[2].id))
  }
}

@Test func wireExamplesAndRecoveryRoundTrip() throws {
  for action in FixtureCatalog.commandExamples { try roundTrip(action) }
  for algorithm in AlgorithmKind.allCases {
    let reconnect = ArenaFixtures.reconnect(algorithm)
    try roundTrip(reconnect)
    #expect(reconnect.pendingCommand == ArenaFixtures.submissionCommand(algorithm))
    #expect(reconnect.lastConfirmedSnapshot.viewer.navigation != nil)
  }
  let snapshot = ArenaFixtures.snapshot(.active, algorithm: .dijkstra)
  #expect(!snapshot.supersedes(snapshot))
  #expect(ArenaFixtures.snapshot(.routeChoice, algorithm: .dijkstra).supersedes(snapshot))
  let invalidVersion = try ContractJSON.encoder().encode(snapshot)
  let text = String(decoding: invalidVersion, as: UTF8.self).replacingOccurrences(
    of: "\"contractVersion\" : 1", with: "\"contractVersion\" : 2")
  #expect(throws: DecodingError.self) {
    try ContractJSON.decoder().decode(MatchSnapshot.self, from: Data(text.utf8))
  }
  #expect(throws: DecodingError.self) {
    try ContractJSON.decoder().decode(AlgorithmKind.self, from: Data("\"bfs\"".utf8))
  }
  #expect(
    try jsonKeys(SnapshotInvalidation(matchID: ArenaFixtures.matchID, revision: 9)) == [
      "matchID", "revision",
    ])
}

@Test func committedJSONMatchesCanonicalSwiftFixtures() throws {
  let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("contracts/v1", isDirectory: true)
  let documents = try FixtureCatalog.documents()
  for (path, expected) in documents {
    let actual = try Data(contentsOf: root.appendingPathComponent(path))
    #expect(actual == expected, "Fixture drift: \(path). Run export-contract-fixtures.")
  }
  let enumerator = try #require(
    FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
  let files = enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "json" }
  #expect(files.count == documents.count)  // Detect stale exports as well as missing files.
}
