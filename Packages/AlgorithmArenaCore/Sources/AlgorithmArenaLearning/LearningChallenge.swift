import AlgorithmArenaCore
import Foundation

/// Server-private authoring data. Only `definition` is safe to deliver before release.
public struct LearningChallenge: Codable, Equatable, Sendable {
  public let definition: ChallengeDefinition
  public let presentedStepIndex: Int
  public let correctAnswer: SubmittedAnswer
  public let explanation: String
  public let workedSteps: [String]
  public let workedStepTraceIndices: [[Int]]
  public let trace: SearchTrace

  /// Node sequences correspond to selectRoute option IDs; empty for other actions.
  public let routes: [String: [NodeID]]
}

public struct LearningSubmission: Equatable, Sendable {
  public let playerID: PlayerID
  public let challengeID: ChallengeID
  public let answer: SubmittedAnswer

  public init(playerID: PlayerID, challengeID: ChallengeID, answer: SubmittedAnswer) {
    self.playerID = playerID
    self.challengeID = challengeID
    self.answer = answer
  }
}

public enum LearningContentError: Error, Equatable, Sendable {
  case invalidAnswer
  case invalidParticipants
  case invalidSubmissions
  case notLearningCheck
  case mismatchedFirstAttempt
  case invalidAuthoredContent(String)
}

extension LearningChallenge {
  /// Validate the answer shape and offered options before an authoritative write.
  /// A well-formed wrong answer is accepted; it still unlocks progression in #7.
  public func accepts(_ answer: SubmittedAnswer) -> Bool {
    switch (definition.action, answer) {
    case (.selectNode(let options), .node(let node)): options.contains(node)
    case (.enterCost, .cost(let value)): (0...SearchEngine.maximumCost).contains(value)
    case (.selectRoute(let options), .route(let option)): options.contains { $0.id == option }
    case (.transfer(let nodes, let reasons), .transfer(let node, let reason)):
      nodes.contains(node) && reasons.contains { $0.id == reason }
    default: false
    }
  }

  /// Projects already accepted, persisted submissions for one authenticated viewer.
  /// Membership, arrival, unlocking, unique writes and atomic awards belong to #7.
  /// Pending shared feedback contains only its challenge ID, regardless of correctness.
  public func feedback(
    for viewer: PlayerID, participants: [PlayerID], submissions: [LearningSubmission]
  ) throws -> FeedbackAvailability? {
    guard participants.count == 2, Set(participants).count == 2,
      participants.allSatisfy({ !$0.rawValue.isEmpty }), participants.contains(viewer)
    else { throw LearningContentError.invalidParticipants }
    guard Set(submissions.map(\.playerID)).count == submissions.count,
      submissions.allSatisfy({
        participants.contains($0.playerID) && $0.challengeID == definition.id
      })
    else { throw LearningContentError.invalidSubmissions }
    guard submissions.allSatisfy({ accepts($0.answer) }) else {
      throw LearningContentError.invalidAnswer
    }
    guard let own = submissions.first(where: { $0.playerID == viewer }) else { return nil }
    if definition.feedbackGate == .afterBothSubmissions && submissions.count < 2 {
      return .pending(challengeID: definition.id)
    }
    let visible =
      definition.feedbackGate == .afterBothSubmissions
      ? submissions.sorted { $0.playerID < $1.playerID } : [own]
    let answers = visible.map {
      let correct = $0.answer == correctAnswer
      return ReleasedAnswer(
        playerID: $0.playerID, answer: $0.answer, isCorrect: correct,
        awardedPoints: correct ? definition.maximumPoints : 0)
    }
    return .released(
      feedback: .init(
        challengeID: definition.id, correctAnswer: correctAnswer,
        explanation: responseExplanation(for: own.answer), workedSteps: workedSteps,
        trace: trace, answers: answers, workedStepTraceIndices: workedStepTraceIndices))
  }

  /// Preserve the original private attempt, including its timestamp and partial result.
  /// The server must persist this once, transactionally, independently of match points.
  public func learningCheckRecord(
    answer: SubmittedAnswer, answeredAt: Date, firstAttempt: LearningCheckRecord? = nil
  ) throws -> LearningCheckRecord {
    guard definition.slot == .learningCheck else { throw LearningContentError.notLearningCheck }
    if let firstAttempt {
      guard firstAttempt.challengeID == definition.id else {
        throw LearningContentError.mismatchedFirstAttempt
      }
      return firstAttempt
    }
    guard accepts(answer), case .transfer(let node, let reason) = answer,
      case .transfer(let correctNode, let correctReason) = correctAnswer
    else { throw LearningContentError.invalidAnswer }
    return .init(
      challengeID: definition.id, firstAnswer: answer, answeredAt: answeredAt,
      nodeCorrect: node == correctNode, reasonCorrect: reason == correctReason)
  }

  private func responseExplanation(for answer: SubmittedAnswer) -> String {
    if answer == correctAnswer { return "Correct. " + explanation }
    let response: String
    switch answer {
    case .node(let node):
      response = "\(node.rawValue) does not have the lowest frontier priority."
    case .cost(let value):
      response = "\(value) is not the updated cost g. Use the edge costs in the worked steps."
    case .route:
      response = "That route has a higher total edge cost."
    case .transfer(let node, let reason):
      guard case .transfer(let correctNode, let correctReason) = correctAnswer else {
        return explanation
      }
      let selection =
        node == correctNode
        ? "Your node choice is correct."
        : "Your node choice does not have the lowest frontier priority."
      let reasoning =
        reason == correctReason
        ? "Your selection rule is correct. Apply it to the current frontier."
        : "Your reason is incorrect. "
          + (definition.algorithm == .aStar
            ? "Neither h alone nor g alone is A*'s priority."
            : "Distance to the goal and settled nodes do not determine Dijkstra's next choice.")
      response = selection + " " + reasoning
    }
    return response + " " + explanation
  }
}
