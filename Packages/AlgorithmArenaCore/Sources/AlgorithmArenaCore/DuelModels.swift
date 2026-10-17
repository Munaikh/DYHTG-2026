import Foundation

/// Indoor, two-player prediction duel. Wire keys use the property names verbatim.
public enum DuelAction: String, Codable, Sendable {
  case create, join, ready, start, submit, advance, leave, rematch
}
public enum DuelPhase: String, Codable, Sendable {
  case lobby, answering, reveal, finished, incomplete
}
public struct DuelCommand: Codable, Equatable, Sendable {
  public let id: UUID
  public let action: DuelAction
  public let matchID: UUID?
  public let revision: Int?
  public let nickname: String?
  public let code: String?
  public let algorithm: StudyAlgorithm?
  public let answerNodeID: NodeID?
  public init(id: UUID = UUID(), action: DuelAction, matchID: UUID? = nil,
    revision: Int? = nil, nickname: String? = nil, code: String? = nil,
    algorithm: StudyAlgorithm? = nil, answerNodeID: NodeID? = nil) {
    self.id = id; self.action = action; self.matchID = matchID; self.revision = revision
    self.nickname = nickname; self.code = code; self.algorithm = algorithm
    self.answerNodeID = answerNodeID
  }
}
public struct DuelPlayer: Codable, Equatable, Sendable, Identifiable {
  public let id: UUID
  public let nickname: String
  public let ready: Bool
  public let score: Int
  public let submitted: Bool
  public let hasContinued: Bool
  public init(id: UUID, nickname: String, ready: Bool, score: Int,
    submitted: Bool, hasContinued: Bool) {
    self.id = id; self.nickname = nickname; self.ready = ready; self.score = score
    self.submitted = submitted; self.hasContinued = hasContinued
  }
}
public enum DuelQuestionKind: String, Codable, CaseIterable, Sendable {
  case nextExpansion, predecessor, routeHop, goalPredecessor
  public var title: String {
    switch self {
    case .nextExpansion: "Choose the next move"
    case .predecessor: "Trace a discovery"
    case .routeHop: "Build the route"
    case .goalPredecessor: "Find the final connection"
    }
  }
}
public struct DuelTrace: Codable, Equatable, Sendable {
  public let scenarioID: ScenarioID
  public let algorithm: StudyAlgorithm
  public let steps: [SearchStep]
  public let outcome: SearchOutcome
  public init(_ trace: StudyTrace) {
    scenarioID = trace.scenario.id; algorithm = trace.algorithm; steps = trace.steps; outcome = trace.outcome
  }
  public init(_ trace: SearchTrace) {
    scenarioID = trace.scenarioID; algorithm = trace.algorithm == .aStar ? .aStar : .dijkstra
    steps = trace.steps; outcome = trace.outcome
  }
}
public struct DuelRound: Codable, Equatable, Sendable {
  public let title: String
  public let questionID: String?
  public let questionKind: DuelQuestionKind?
  public let focusNodeID: NodeID?
  public let prompt: String
  public let twist: String?
  public let scenario: GraphScenario
  /// The decision boundary, without future search steps or an answer key.
  public let presentedState: SearchState
  /// Deliberately shuffled independently of frontier priority.
  public let choices: [NodeID]
  public let previousScenario: GraphScenario?
  public init(title: String, prompt: String, twist: String? = nil,
    scenario: GraphScenario, presentedState: SearchState, choices: [NodeID],
    previousScenario: GraphScenario? = nil, questionID: String? = nil,
    questionKind: DuelQuestionKind? = nil, focusNodeID: NodeID? = nil) {
    self.questionID = questionID; self.questionKind = questionKind; self.focusNodeID = focusNodeID
    self.title = title; self.prompt = prompt; self.twist = twist; self.scenario = scenario
    self.presentedState = presentedState; self.choices = choices
    self.previousScenario = previousScenario
  }
}
public struct DuelAnswer: Codable, Equatable, Sendable, Identifiable {
  public var id: UUID { playerID }
  public let playerID: UUID
  public let answerNodeID: NodeID
  public let correct: Bool
  public let points: Int
  public init(playerID: UUID, answerNodeID: NodeID, correct: Bool, points: Int) {
    self.playerID = playerID; self.answerNodeID = answerNodeID
    self.correct = correct; self.points = points
  }
}
public struct DuelReveal: Codable, Equatable, Sendable {
  public let correctNodeID: NodeID
  public let explanation: String
  public let trace: DuelTrace
  public let answers: [DuelAnswer]
  public init(correctNodeID: NodeID, explanation: String, trace: DuelTrace,
    answers: [DuelAnswer]) {
    self.correctNodeID = correctNodeID; self.explanation = explanation
    self.trace = trace; self.answers = answers
  }
  public init(correctNodeID: NodeID, explanation: String, trace: SearchTrace, answers: [DuelAnswer]) {
    self.init(correctNodeID: correctNodeID, explanation: explanation, trace: DuelTrace(trace), answers: answers)
  }
}
public struct DuelSnapshot: Codable, Equatable, Sendable, Identifiable {
  public let id: UUID
  public let roomCode: String
  public let creatorID: UUID
  public let viewerID: UUID
  public let revision: Int
  public let phase: DuelPhase
  /// Zero-based; 0...2 for the three authored rounds.
  public let roundIndex: Int
  public let roundCount: Int
  public let algorithm: StudyAlgorithm
  public let players: [DuelPlayer]
  public let currentRound: DuelRound?
  /// Present only after both players submit, including the final result.
  public let reveal: DuelReveal?
  public init(id: UUID, roomCode: String, creatorID: UUID, viewerID: UUID,
    revision: Int, phase: DuelPhase, roundIndex: Int, roundCount: Int,
    algorithm: StudyAlgorithm, players: [DuelPlayer], currentRound: DuelRound? = nil,
    reveal: DuelReveal? = nil) {
    self.id = id; self.roomCode = roomCode; self.creatorID = creatorID
    self.viewerID = viewerID; self.revision = revision; self.phase = phase
    self.roundIndex = roundIndex; self.roundCount = roundCount; self.algorithm = algorithm
    self.players = players; self.currentRound = currentRound; self.reveal = reveal
  }
}
