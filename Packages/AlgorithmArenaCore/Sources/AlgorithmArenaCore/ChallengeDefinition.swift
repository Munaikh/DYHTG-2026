import Foundation

public enum ChallengeSlot: String, Codable, CaseIterable, Sendable {
  case practice, first, standardMiddle, bonusMiddle, third, learningCheck
}

public enum FeedbackGate: String, Codable, Sendable { case immediate, afterBothSubmissions }

public struct AnswerOption: Codable, Equatable, Sendable, Identifiable {
  public let id: String
  public let text: String
  public init(id: String, text: String) {
    self.id = id
    self.text = text
  }
}

public enum ChallengeAction: Codable, Equatable, Sendable {
  case selectNode(options: [NodeID])
  case enterCost(nodeID: NodeID)
  case selectRoute(options: [AnswerOption])
  case transfer(nodeOptions: [NodeID], reasons: [AnswerOption])
}

public enum SubmittedAnswer: Codable, Equatable, Sendable {
  case node(nodeID: NodeID)
  case cost(value: Int)
  case route(optionID: String)
  case transfer(nodeID: NodeID, reasonID: String)
}

/// Client-safe question only. Solutions, explanation and future trace steps belong
/// to server-private content until released as feedback for this viewer.
public struct ChallengeDefinition: Codable, Equatable, Sendable, Identifiable {
  public let id: ChallengeID
  public let contentVersion: String
  public let algorithm: AlgorithmKind
  public let slot: ChallengeSlot
  public let scenario: GraphScenario
  public let presentedState: SearchState
  public let prompt: String
  public let action: ChallengeAction
  public let maximumPoints: Int
  public let feedbackGate: FeedbackGate
  public init(
    id: ChallengeID, contentVersion: String, algorithm: AlgorithmKind, slot: ChallengeSlot,
    scenario: GraphScenario, presentedState: SearchState, prompt: String, action: ChallengeAction,
    maximumPoints: Int, feedbackGate: FeedbackGate
  ) {
    self.id = id
    self.contentVersion = contentVersion
    self.algorithm = algorithm
    self.slot = slot
    self.scenario = scenario
    self.presentedState = presentedState
    self.prompt = prompt
    self.action = action
    self.maximumPoints = maximumPoints
    self.feedbackGate = feedbackGate
  }
}

public struct PrivateSubmission: Codable, Equatable, Sendable {
  public let challengeID: ChallengeID
  public let commandID: UUID
  public let answer: SubmittedAnswer
  public let acceptedAt: Date
  public init(challengeID: ChallengeID, commandID: UUID, answer: SubmittedAnswer, acceptedAt: Date)
  {
    self.challengeID = challengeID
    self.commandID = commandID
    self.answer = answer
    self.acceptedAt = acceptedAt
  }
}

public struct ReleasedAnswer: Codable, Equatable, Sendable {
  public let playerID: PlayerID
  public let answer: SubmittedAnswer
  public let isCorrect: Bool
  public let awardedPoints: Int
  public init(playerID: PlayerID, answer: SubmittedAnswer, isCorrect: Bool, awardedPoints: Int) {
    self.playerID = playerID
    self.answer = answer
    self.isCorrect = isCorrect
    self.awardedPoints = awardedPoints
  }
}

public struct ReleasedFeedback: Codable, Equatable, Sendable {
  public let challengeID: ChallengeID
  public let correctAnswer: SubmittedAnswer
  public let explanation: String
  public let workedSteps: [String]
  public let trace: SearchTrace
  /// Only answers authorised for this viewer; middle/practice/check are self-only.
  public let answers: [ReleasedAnswer]
  public init(
    challengeID: ChallengeID, correctAnswer: SubmittedAnswer, explanation: String,
    workedSteps: [String], trace: SearchTrace, answers: [ReleasedAnswer]
  ) {
    self.challengeID = challengeID
    self.correctAnswer = correctAnswer
    self.explanation = explanation
    self.workedSteps = workedSteps
    self.trace = trace
    self.answers = answers
  }
}

public enum FeedbackAvailability: Codable, Equatable, Sendable {
  /// Deliberately carries no correctness, reward, answer key, or replay.
  case pending(challengeID: ChallengeID)
  case released(feedback: ReleasedFeedback)
}

public struct LearningCheckRecord: Codable, Equatable, Sendable {
  public let challengeID: ChallengeID
  public let firstAnswer: SubmittedAnswer
  public let answeredAt: Date
  public let nodeCorrect: Bool
  public let reasonCorrect: Bool
  public init(
    challengeID: ChallengeID, firstAnswer: SubmittedAnswer, answeredAt: Date, nodeCorrect: Bool,
    reasonCorrect: Bool
  ) {
    self.challengeID = challengeID
    self.firstAnswer = firstAnswer
    self.answeredAt = answeredAt
    self.nodeCorrect = nodeCorrect
    self.reasonCorrect = reasonCorrect
  }
}
