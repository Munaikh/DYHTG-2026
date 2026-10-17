import AlgorithmArenaCore
import AlgorithmArenaLearning
import Foundation
import Testing

private let players: [PlayerID] = ["alex", "sam"]
private let timestamp = Date(timeIntervalSince1970: 1_792_238_400)

private func submission(
  _ challenge: LearningChallenge, _ player: PlayerID, _ answer: SubmittedAnswer
)
  -> LearningSubmission
{
  .init(playerID: player, challengeID: challenge.definition.id, answer: answer)
}

private func wrongAnswer(_ challenge: LearningChallenge) -> SubmittedAnswer {
  switch challenge.definition.action {
  case .selectNode(let options):
    .node(nodeID: options.first { .node(nodeID: $0) != challenge.correctAnswer }!)
  case .enterCost: .cost(value: 999)
  case .selectRoute(let options):
    .route(optionID: options.first { .route(optionID: $0.id) != challenge.correctAnswer }!.id)
  case .transfer(let nodes, _):
    .transfer(nodeID: nodes[0], reasonID: "goal-distance")
  }
}

private func released(_ value: FeedbackAvailability?) throws -> ReleasedFeedback {
  guard case .released(let feedback) = value else {
    throw LearningContentError.invalidAuthoredContent("Expected released feedback")
  }
  return feedback
}

private func allKeys(_ value: Any) -> Set<String> {
  if let dictionary = value as? [String: Any] {
    return dictionary.values.reduce(into: Set(dictionary.keys)) { $0.formUnion(allKeys($1)) }
  }
  if let array = value as? [Any] {
    return array.reduce(into: Set<String>()) { $0.formUnion(allKeys($1)) }
  }
  return []
}

@Test(arguments: AlgorithmKind.allCases, ChallengeSlot.allCases)
func questionsAndWorkedReplayReferencesAgreeWithEngine(
  algorithm: AlgorithmKind, slot: ChallengeSlot
) throws {
  let challenge = try LearningCatalog.challenge(slot, algorithm: algorithm)
  let definition = challenge.definition
  #expect(challenge.accepts(challenge.correctAnswer))
  #expect(challenge.accepts(wrongAnswer(challenge)))
  #expect(challenge.trace == (try SearchEngine.search(definition.scenario, algorithm: algorithm)))
  try SearchEngine.validateHeuristics(in: definition.scenario)
  #expect(definition.presentedState == challenge.trace.steps[challenge.presentedStepIndex].state)
  #expect(!challenge.explanation.isEmpty && !challenge.workedSteps.isEmpty)
  #expect(challenge.workedSteps.count == challenge.workedStepTraceIndices.count)
  for indices in challenge.workedStepTraceIndices {
    #expect(!indices.isEmpty)
    #expect(indices.allSatisfy { challenge.trace.steps.indices.contains($0) })
  }
  #expect(
    try ContractJSON.decoder().decode(
      LearningChallenge.self, from: ContractJSON.encoder().encode(challenge)) == challenge)

  // Independently derive the solution from the question's state/edges, not its stored key.
  switch (definition.action, challenge.correctAnswer) {
  case (.selectNode(let options), .node(let selected)),
    (.transfer(let options, _), .transfer(let selected, _)):
    let costs = definition.presentedState.costs.filter {
      definition.presentedState.frontier.contains($0.nodeID)
    }
    let next = costs.min {
      let l = $0.g! + (algorithm == .aStar ? $0.h : 0)
      let r = $1.g! + (algorithm == .aStar ? $1.h : 0)
      return l == r ? $0.nodeID < $1.nodeID : l < r
    }
    #expect(selected == next?.nodeID)
    #expect(Set(options) == Set(definition.presentedState.frontier))
    #expect(
      challenge.trace.steps[challenge.presentedStepIndex + 1].event == .expand(nodeID: selected))
  case (.enterCost(let target), .cost(let answer)):
    let state = definition.presentedState
    let current = try #require(state.settled.last)
    let g = try #require(state.costs.first { $0.nodeID == current }?.g)
    let old = try #require(state.costs.first { $0.nodeID == target }?.g)
    if slot == .bonusMiddle {
      // Neither of the two required cheaper-path replacements has happened yet.
      let future = challenge.trace.steps.dropFirst(challenge.presentedStepIndex + 1)
      let targetUpdate = try #require(
        future.first {
          if case .relax(let from, let to, _, _, true) = $0.event {
            return to == target && from != current
          }
          return false
        })
      guard case .relax(let intermediate, _, _, _, _) = targetUpdate.event else {
        throw LearningContentError.invalidAnswer
      }
      let firstEdge = try #require(
        definition.scenario.edges.first { $0.from == current && $0.to == intermediate })
      let secondEdge = try #require(
        definition.scenario.edges.first { $0.from == intermediate && $0.to == target })
      #expect(answer == min(old, g + firstEdge.cost + secondEdge.cost))
      #expect(try #require(state.costs.first { $0.nodeID == intermediate }?.g) > g + firstEdge.cost)
      #expect(
        challenge.workedStepTraceIndices.allSatisfy {
          $0.allSatisfy { $0 > challenge.presentedStepIndex }
        })
    } else {
      let edge = try #require(
        definition.scenario.edges.first { $0.from == current && $0.to == target })
      #expect(answer == min(old, g + edge.cost))
      #expect(
        challenge.trace.steps[challenge.presentedStepIndex + 1].event
          == .relax(
            from: current, to: target, previousCost: old, candidateCost: answer, accepted: true))
    }
    #expect(answer < old)
  case (.selectRoute(let options), .route(let selected)):
    var totals: [String: Int] = [:]
    for option in options {
      let nodes = try #require(challenge.routes[option.id])
      var sum = 0
      for (from, to) in zip(nodes, nodes.dropFirst()) {
        sum += try #require(definition.scenario.edges.first { $0.from == from && $0.to == to }).cost
      }
      totals[option.id] = sum
    }
    #expect(totals[selected] == totals.values.min())
    guard case .route(let finalNodes, let finalCost) = challenge.trace.outcome else {
      Issue.record("Expected a reachable goal")
      return
    }
    #expect(challenge.routes[selected] == finalNodes)
    #expect(totals[selected] == finalCost)
    let explored = Set(try #require(challenge.trace.steps.last).state.settled)
    #expect(!explored.subtracting(finalNodes).isEmpty)
  default: Issue.record("Incorrect solution shape")
  }
}

@Test(arguments: AlgorithmKind.allCases)
func misconceptionsAndTransferAreObservable(algorithm: AlgorithmKind) throws {
  let bank = try LearningCatalog.challenges(algorithm: algorithm)
  #expect(bank.count == 6)
  #expect(Set(bank.map { $0.definition.scenario.id }).count == 6)
  for (index, question) in bank.enumerated() {
    #expect(
      bank.dropFirst(index + 1).allSatisfy {
        $0.definition.scenario.edges != question.definition.scenario.edges
      })
  }
  let prediction = try LearningCatalog.challenge(.first, algorithm: algorithm)
  let correctNode: NodeID = algorithm == .aStar ? "A" : "M"
  let misleadingNode: NodeID = algorithm == .aStar ? "B" : "N"
  let goal = try #require(prediction.definition.scenario.nodes.last?.position)
  let correct = try #require(prediction.definition.scenario.nodes.first { $0.id == correctNode })
  let misleading = try #require(
    prediction.definition.scenario.nodes.first { $0.id == misleadingNode })
  let correctPosition = try #require(correct.position)
  let misleadingPosition = try #require(misleading.position)
  #expect(
    hypot(misleadingPosition.x - goal.x, misleadingPosition.y - goal.y)
      < hypot(correctPosition.x - goal.x, correctPosition.y - goal.y))
  #expect(misleading.heuristic < correct.heuristic)
  #expect(prediction.correctAnswer == .node(nodeID: correctNode))
  if algorithm == .aStar {
    #expect(prediction.explanation.contains("g + h"))
    #expect(prediction.explanation.contains("not a confirmed walking cost"))
    let transfer = try LearningCatalog.challenge(.learningCheck, algorithm: algorithm)
    let costs = transfer.definition.presentedState.costs.filter { $0.g != nil }
    #expect(transfer.correctAnswer == .transfer(nodeID: "R", reasonID: "frontier-priority"))
    // Q minimises g; T minimises h; R minimises f. Neither shortcut passes.
    #expect(costs.first { $0.nodeID == "Q" }?.g == 4)
    #expect(costs.first { $0.nodeID == "R" }?.g == 7)
    #expect(costs.first { $0.nodeID == "T" }?.h == 0)
    #expect(transfer.definition.scenario.nodes.count == 5)
  }
}

@Test(arguments: AlgorithmKind.allCases)
func routeChoiceReplacesMiddleWithoutChangingSharedContent(algorithm: AlgorithmKind) throws {
  let standard = try LearningCatalog.matchChallenges(algorithm: algorithm, branch: .standard)
  let bonus = try LearningCatalog.matchChallenges(algorithm: algorithm, branch: .bonus)
  #expect(standard.map(\.slot) == [.first, .standardMiddle, .third])
  #expect(bonus.map(\.slot) == [.first, .bonusMiddle, .third])
  #expect(standard[0] == bonus[0] && standard[2] == bonus[2])
  #expect(standard[1].maximumPoints == 20 && bonus[1].maximumPoints == 40)
  #expect(standard.reduce(20) { $0 + $1.maximumPoints } == 80)
  #expect(bonus.reduce(20) { $0 + $1.maximumPoints } == 100)
  #expect((standard + bonus).allSatisfy { $0.algorithm == algorithm })
}

@Test(arguments: AlgorithmKind.allCases, ChallengeSlot.allCases)
func promptPrivacyAndFeedbackForEveryLegalOption(algorithm: AlgorithmKind, slot: ChallengeSlot)
  throws
{
  let challenge = try LearningCatalog.challenge(slot, algorithm: algorithm)
  let data = try ContractJSON.encoder().encode(challenge.definition)
  let keys = allKeys(try JSONSerialization.jsonObject(with: data))
  #expect(
    keys.isDisjoint(with: [
      "correctAnswer", "isCorrect", "explanation", "workedSteps", "workedStepTraceIndices",
      "trace", "answers", "awardedPoints", "presentedStepIndex", "routes",
    ]))
  #expect(
    challenge.definition.maximumPoints
      == (slot == .practice || slot == .learningCheck
        ? 0 : slot == .bonusMiddle ? 40 : 20))
  let possible: [SubmittedAnswer]
  switch challenge.definition.action {
  case .selectNode(let options): possible = options.map { .node(nodeID: $0) }
  case .enterCost: possible = [challenge.correctAnswer, .cost(value: 0), .cost(value: 999)]
  case .selectRoute(let options): possible = options.map { .route(optionID: $0.id) }
  case .transfer(let nodes, let reasons):
    possible = nodes.flatMap { node in reasons.map { .transfer(nodeID: node, reasonID: $0.id) } }
  }
  for answer in possible {
    let submissions = [submission(challenge, players[0], answer)]
    let feedback = try released(
      challenge.feedback(
        for: players[0], participants: players,
        submissions: challenge.definition.feedbackGate == .immediate
          ? submissions
          : submissions + [submission(challenge, players[1], wrongAnswer(challenge))]))
    let own = try #require(feedback.answers.first { $0.playerID == players[0] })
    #expect(own.answer == answer)
    #expect(own.isCorrect == (answer == challenge.correctAnswer))
    #expect(own.awardedPoints == (own.isCorrect ? challenge.definition.maximumPoints : 0))
    #expect(feedback.workedSteps == challenge.workedSteps)
    #expect(feedback.workedStepTraceIndices == challenge.workedStepTraceIndices)
    #expect(feedback.trace == challenge.trace)
    #expect(!feedback.explanation.isEmpty)
    #expect(
      try ContractJSON.decoder().decode(
        ReleasedFeedback.self, from: ContractJSON.encoder().encode(feedback)) == feedback)
    if challenge.definition.feedbackGate == .immediate { #expect(feedback.answers.count == 1) }
  }
}

@Test(arguments: AlgorithmKind.allCases, [ChallengeSlot.first, .third])
func sharedGateReleasesBothAnswersOnlyAfterBothSubmit(algorithm: AlgorithmKind, slot: ChallengeSlot)
  throws
{
  let challenge = try LearningCatalog.challenge(slot, algorithm: algorithm)
  #expect(challenge.definition.feedbackGate == .afterBothSubmissions)
  for answer in [challenge.correctAnswer, wrongAnswer(challenge)] {
    let own = submission(challenge, players[0], answer)
    let pending = try challenge.feedback(for: players[0], participants: players, submissions: [own])
    #expect(pending == .pending(challengeID: challenge.definition.id))
    let pendingJSON = try ContractJSON.encoder().encode(pending)
    #expect(
      allKeys(try JSONSerialization.jsonObject(with: pendingJSON)) == ["pending", "challengeID"])
    #expect(
      try challenge.feedback(for: players[1], participants: players, submissions: [own]) == nil)
    let both = [own, submission(challenge, players[1], wrongAnswer(challenge))]
    let feedback = try released(
      challenge.feedback(for: players[0], participants: players, submissions: both))
    #expect(feedback.answers.map(\.playerID) == players)
    #expect(feedback.answers[0].isCorrect == (answer == challenge.correctAnswer))
    #expect(feedback.answers[1].isCorrect == false)
    #expect(feedback.answers[1].awardedPoints == 0)
    #expect(
      try challenge.feedback(for: players[0], participants: players, submissions: both.reversed())
        == .released(feedback: feedback))
  }
}

@Test(arguments: AlgorithmKind.allCases)
func firstLearningAttemptPreservesPartialUnderstandingAndAwardsNothing(algorithm: AlgorithmKind)
  throws
{
  let challenge = try LearningCatalog.challenge(.learningCheck, algorithm: algorithm)
  guard case .transfer(let correctNode, let correctReason) = challenge.correctAnswer,
    case .transfer(let nodes, _) = challenge.definition.action
  else { throw LearningContentError.invalidAnswer }
  let wrongNode = try #require(nodes.first { $0 != correctNode })
  for (node, reason, nodeCorrect, reasonCorrect) in [
    (correctNode, correctReason, true, true),
    (correctNode, "goal-distance", true, false),
    (wrongNode, correctReason, false, true),
    (wrongNode, "goal-distance", false, false),
  ] {
    let answer = SubmittedAnswer.transfer(nodeID: node, reasonID: reason)
    let first = try challenge.learningCheckRecord(answer: answer, answeredAt: timestamp)
    #expect(first.nodeCorrect == nodeCorrect && first.reasonCorrect == reasonCorrect)
    #expect(first.firstAnswer == answer && first.answeredAt == timestamp)
    let retry = try challenge.learningCheckRecord(
      answer: challenge.correctAnswer, answeredAt: timestamp.addingTimeInterval(60),
      firstAttempt: first)
    #expect(retry == first)
    let feedback = try released(
      challenge.feedback(
        for: players[0], participants: players,
        submissions: [submission(challenge, players[0], answer)]))
    #expect(feedback.answers[0].awardedPoints == 0)
  }
  let practice = try LearningCatalog.challenge(.practice, algorithm: algorithm)
  #expect(throws: LearningContentError.notLearningCheck) {
    try practice.learningCheckRecord(answer: practice.correctAnswer, answeredAt: timestamp)
  }
  let foreign = LearningCheckRecord(
    challengeID: "another-challenge", firstAnswer: challenge.correctAnswer, answeredAt: timestamp,
    nodeCorrect: true, reasonCorrect: true)
  #expect(throws: LearningContentError.mismatchedFirstAttempt) {
    try challenge.learningCheckRecord(
      answer: challenge.correctAnswer, answeredAt: timestamp, firstAttempt: foreign)
  }
}

@Test func malformedSubmissionsCannotProduceFeedback() throws {
  let challenge = try LearningCatalog.challenge(.first, algorithm: .dijkstra)
  let own = submission(challenge, players[0], challenge.correctAnswer)
  #expect(!challenge.accepts(.cost(value: 3)))
  #expect(!challenge.accepts(.node(nodeID: "missing")))
  #expect(throws: LearningContentError.invalidParticipants) {
    try challenge.feedback(
      for: players[0], participants: [players[0], players[0]], submissions: [own])
  }
  #expect(throws: LearningContentError.invalidParticipants) {
    try challenge.feedback(for: "outsider", participants: players, submissions: [own])
  }
  #expect(throws: LearningContentError.invalidSubmissions) {
    try challenge.feedback(for: players[0], participants: players, submissions: [own, own])
  }
  #expect(throws: LearningContentError.invalidSubmissions) {
    try challenge.feedback(
      for: players[0], participants: players,
      submissions: [
        .init(playerID: players[0], challengeID: "wrong-challenge", answer: challenge.correctAnswer)
      ])
  }
  #expect(throws: LearningContentError.invalidAnswer) {
    try challenge.feedback(
      for: players[0], participants: players,
      submissions: [submission(challenge, players[0], .cost(value: 3))])
  }
  let middle = try LearningCatalog.challenge(.standardMiddle, algorithm: .aStar)
  #expect(!middle.accepts(.cost(value: -1)))
  #expect(!middle.accepts(.cost(value: Int.max)))
  #expect(middle.accepts(.cost(value: SearchEngine.maximumCost)))
  let transfer = try LearningCatalog.challenge(.learningCheck, algorithm: .aStar)
  #expect(!transfer.accepts(.transfer(nodeID: "R", reasonID: "missing")))
  #expect(!transfer.accepts(.transfer(nodeID: "missing", reasonID: "frontier-priority")))
  let comparison = try LearningCatalog.challenge(.third, algorithm: .dijkstra)
  #expect(!comparison.accepts(.route(optionID: "missing")))
  // Immediate projection stays self-only even when another accepted answer is supplied.
  let feedback = try released(
    middle.feedback(
      for: players[0], participants: players,
      submissions: [
        submission(middle, players[0], middle.correctAnswer),
        submission(middle, players[1], wrongAnswer(middle)),
      ]))
  #expect(feedback.answers.map(\.playerID) == [players[0]])
}

@Test func authoredJSONMatchesExports() throws {
  let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  let output = root.appendingPathComponent("content/learning/v1")
  let documents = try LearningDocuments.documents()
  #expect(documents.count == 24)
  for (path, data) in documents {
    #expect(
      try Data(contentsOf: output.appendingPathComponent(path)) == data,
      "Learning export drift: \(path)")
  }
  let enumerator = try #require(
    FileManager.default.enumerator(at: output, includingPropertiesForKeys: nil))
  #expect(
    enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "json" }.count
      == documents.count)
}
