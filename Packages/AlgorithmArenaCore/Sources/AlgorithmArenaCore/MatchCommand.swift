import Foundation

public struct LocationFix: Codable, Equatable, Sendable {
  public let coordinate: Coordinate
  public let capturedAt: Date
  public let horizontalAccuracyMetres: Double
  public init(coordinate: Coordinate, capturedAt: Date, horizontalAccuracyMetres: Double) {
    self.coordinate = coordinate
    self.capturedAt = capturedAt
    self.horizontalAccuracyMetres = horizontalAccuracyMetres
  }
}

public enum ArrivalEvidence: Codable, Equatable, Sendable {
  case location(fix: LocationFix)
  /// Opaque, short-lived server-issued proof. Never an organiser secret or local bypass.
  case organiserApproval(approvalID: String)
}

public enum CommandScope: Codable, Equatable, Sendable {
  case roomEntry
  case match(matchID: MatchID, course: CourseReference, expectedRevision: Int)
}

public enum MatchAction: Codable, Equatable, Sendable {
  case createRoom(nickname: String, course: CourseReference, algorithm: AlgorithmKind)
  case joinRoom(code: String, nickname: String)
  case selectAlgorithm(algorithm: AlgorithmKind)
  case confirmAlgorithm(algorithm: AlgorithmKind)
  case setReady(ready: Bool)
  case start
  case confirmArrival(nodeID: NodeID, evidence: ArrivalEvidence)
  case chooseRoute(branch: RouteBranch)
  case submitAnswer(challengeID: ChallengeID, answer: SubmittedAnswer)
  case finish(evidence: ArrivalEvidence)
  case leave
}

/// Identity comes from the authenticated service session, never a client player ID.
public struct MatchCommand: Codable, Equatable, Sendable, Identifiable {
  public let contractVersion: ContractVersion
  public let id: UUID
  public let scope: CommandScope
  public let action: MatchAction
  public init(
    contractVersion: ContractVersion = .v1, id: UUID, scope: CommandScope, action: MatchAction
  ) {
    self.contractVersion = contractVersion
    self.id = id
    self.scope = scope
    self.action = action
  }
}

public enum MatchErrorCode: String, Codable, CaseIterable, Sendable {
  case unauthenticated, notMember, roomNotFound, roomFull, invalidCommand, invalidPhase
  case incompatibleContract, incompatibleCourse, staleRevision, idempotencyConflict
  case algorithmNotConfirmed, arrivalRequired, staleLocation, inaccurateLocation,
    outsideArrivalRadius
  case invalidApproval, routeAlreadyLocked, challengeUnavailable, alreadySubmitted, rateLimited
  case disconnected, serviceUnavailable
}

public struct MatchServiceError: Error, Codable, Equatable, Sendable {
  public let code: MatchErrorCode
  public let message: String
  public let currentRevision: Int?
  public let retryAfterSeconds: Int?
  public init(
    code: MatchErrorCode, message: String, currentRevision: Int? = nil,
    retryAfterSeconds: Int? = nil
  ) {
    self.code = code
    self.message = message
    self.currentRevision = currentRevision
    self.retryAfterSeconds = retryAfterSeconds
  }
}
