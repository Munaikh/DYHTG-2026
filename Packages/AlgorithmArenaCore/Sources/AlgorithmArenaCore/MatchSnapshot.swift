import Foundation

public enum MatchPhase: String, Codable, CaseIterable, Sendable {
  case lobby, practice, active, awaitingFinish, finished, incomplete
}

public enum PlayerStage: Codable, Equatable, Sendable {
  case atStart
  case practice
  case walking(target: NodeID)
  case challenge(challengeID: ChallengeID)
  case choosingRoute
  case finished
  case departed
}

public enum PlayerConnection: String, Codable, Sendable { case online, disconnected }
public enum ArrivalMethod: String, Codable, Sendable { case location, organiserApproval }

public struct ConfirmedArrival: Codable, Equatable, Sendable {
  public let nodeID: NodeID
  public let method: ArrivalMethod
  public init(nodeID: NodeID, method: ArrivalMethod) {
    self.nodeID = nodeID
    self.method = method
  }
}

/// Room-visible progress. Contains no answers, location fixes, or unreleased rewards.
public struct PlayerProgress: Codable, Equatable, Sendable, Identifiable {
  public let id: PlayerID
  public let nickname: String
  public let algorithmConfirmed: Bool
  public let ready: Bool
  public let connection: PlayerConnection
  public let stage: PlayerStage
  public let routeChoice: RouteBranch?
  public let arrivals: [ConfirmedArrival]
  public let completedChallengeIDs: [ChallengeID]
  public let releasedScore: Int
  public let pendingRewardMaximum: Int
  public let remainingAvailablePoints: Int
  public init(
    id: PlayerID, nickname: String, algorithmConfirmed: Bool, ready: Bool,
    connection: PlayerConnection, stage: PlayerStage, routeChoice: RouteBranch?,
    arrivals: [ConfirmedArrival], completedChallengeIDs: [ChallengeID], releasedScore: Int,
    pendingRewardMaximum: Int, remainingAvailablePoints: Int
  ) {
    self.id = id
    self.nickname = nickname
    self.algorithmConfirmed = algorithmConfirmed
    self.ready = ready
    self.connection = connection
    self.stage = stage
    self.routeChoice = routeChoice
    self.arrivals = arrivals
    self.completedChallengeIDs = completedChallengeIDs
    self.releasedScore = releasedScore
    self.pendingRewardMaximum = pendingRewardMaximum
    self.remainingAvailablePoints = remainingAvailablePoints
  }
}

public struct ScoreAward: Codable, Equatable, Sendable {
  public let slot: ChallengeSlot?
  /// nil slot identifies the finish reward; only released, authoritative values.
  public let points: Int
  public init(slot: ChallengeSlot?, points: Int) {
    self.slot = slot
    self.points = points
  }
}

public struct Standing: Codable, Equatable, Sendable {
  public let playerID: PlayerID
  public let routeChoice: RouteBranch?
  public let score: Int
  public let awards: [ScoreAward]
  public init(playerID: PlayerID, routeChoice: RouteBranch?, score: Int, awards: [ScoreAward]) {
    self.playerID = playerID
    self.routeChoice = routeChoice
    self.score = score
    self.awards = awards
  }
}

public enum MatchResult: Codable, Equatable, Sendable {
  case winner(playerID: PlayerID, standings: [Standing])
  case draw(standings: [Standing])
  case incomplete(departedPlayerID: PlayerID, standings: [Standing])
}

public struct PublicMatchState: Codable, Equatable, Sendable {
  public let matchID: MatchID
  public let roomCode: String
  public let creatorID: PlayerID
  public let course: CourseReference
  /// Shared selection; mutable only in the lobby. Changes clear both confirmations/readiness.
  public let algorithm: AlgorithmKind
  public let phase: MatchPhase
  public let players: [PlayerProgress]
  public let result: MatchResult?
  public init(
    matchID: MatchID, roomCode: String, creatorID: PlayerID, course: CourseReference,
    algorithm: AlgorithmKind, phase: MatchPhase, players: [PlayerProgress], result: MatchResult?
  ) {
    self.matchID = matchID
    self.roomCode = roomCode
    self.creatorID = creatorID
    self.course = course
    self.algorithm = algorithm
    self.phase = phase
    self.players = players
    self.result = result
  }
}

public struct NavigationState: Codable, Equatable, Sendable {
  public let nextStop: NodeID
  public let edgeIDs: [EdgeID]
  public init(nextStop: NodeID, edgeIDs: [EdgeID]) {
    self.nextStop = nextStop
    self.edgeIDs = edgeIDs
  }
}

/// Delivered only to this authenticated player, not to a room subscription.
public struct PrivatePlayerState: Codable, Equatable, Sendable {
  public let playerID: PlayerID
  public let submissions: [PrivateSubmission]
  public let feedback: [FeedbackAvailability]
  /// Only currently unlocked questions. Middle questions appear after route lock + arrival.
  public let availableChallenges: [ChallengeDefinition]
  public let navigation: NavigationState?
  public let learningCheck: LearningCheckRecord?
  public init(
    playerID: PlayerID, submissions: [PrivateSubmission], feedback: [FeedbackAvailability],
    availableChallenges: [ChallengeDefinition], navigation: NavigationState?,
    learningCheck: LearningCheckRecord?
  ) {
    self.playerID = playerID
    self.submissions = submissions
    self.feedback = feedback
    self.availableChallenges = availableChallenges
    self.navigation = navigation
    self.learningCheck = learningCheck
  }
}

public struct MatchSnapshot: Codable, Equatable, Sendable {
  public let contractVersion: ContractVersion
  /// Monotonically increasing per match, including viewer-private changes.
  public let revision: Int
  public let serverTime: Date
  public let room: PublicMatchState
  public let viewer: PrivatePlayerState
  public init(
    contractVersion: ContractVersion = .v1, revision: Int, serverTime: Date,
    room: PublicMatchState, viewer: PrivatePlayerState
  ) {
    self.contractVersion = contractVersion
    self.revision = revision
    self.serverTime = serverTime
    self.room = room
    self.viewer = viewer
  }

  public func supersedes(_ previous: MatchSnapshot) -> Bool {
    room.matchID == previous.room.matchID && viewer.playerID == previous.viewer.playerID
      && revision > previous.revision
  }
}
