import AlgorithmArenaCore
import Foundation

public struct MockTransition: Sendable {
  public let action: MatchAction
  public let snapshot: MatchSnapshot
  public init(action: MatchAction, snapshot: MatchSnapshot) {
    self.action = action
    self.snapshot = snapshot
  }
}

/// A deterministic adapter for previews/tests, not an authoritative rules engine.
/// It applies only explicitly scripted actions; unsupported actions fail visibly.
public actor ScriptedMatchService: MatchService {
  private var current: MatchSnapshot?
  private var transitions: [MockTransition]
  private var receipts: [UUID: (MatchCommand, CommandReceipt)] = [:]
  private var subscribers:
    [UUID: AsyncThrowingStream<SnapshotInvalidation, any Error>.Continuation] = [:]

  public init(initial: MatchSnapshot? = nil, transitions: [MockTransition] = []) {
    current = initial
    self.transitions = transitions
  }

  public func send(_ command: MatchCommand) async throws -> CommandReceipt {
    try Task.checkCancellation()
    if let (original, receipt) = receipts[command.id] {
      guard original == command else {
        throw MatchServiceError(
          code: .idempotencyConflict,
          message: "The command ID was already used with another payload.")
      }
      return receipt
    }
    switch command.scope {
    case .roomEntry:
      guard current == nil else {
        throw MatchServiceError(
          code: .invalidPhase, message: "This mock already has a room; start a new fixture session."
        )
      }
      switch command.action {
      case .createRoom, .joinRoom: break
      default:
        throw MatchServiceError(
          code: .invalidCommand, message: "Room entry requires create or join.")
      }
    case .match(let matchID, let course, let expectedRevision):
      let current = try requireMatch(matchID)
      guard course == current.room.course else {
        throw MatchServiceError(
          code: .incompatibleCourse, message: "Refresh the course before continuing.")
      }
      guard expectedRevision == current.revision else {
        throw MatchServiceError(
          code: .staleRevision, message: "Refetch the snapshot.", currentRevision: current.revision)
      }
      switch command.action {
      case .createRoom, .joinRoom:
        throw MatchServiceError(
          code: .invalidCommand, message: "Create/join requires roomEntry scope.")
      default: break
      }
    }
    guard let next = transitions.first, next.action == command.action else {
      throw MatchServiceError(
        code: .invalidCommand, message: "This action has no scripted fixture transition.")
    }
    if let current {
      guard next.snapshot.supersedes(current), next.snapshot.room.course == current.room.course,
        current.room.phase == .lobby || next.snapshot.room.algorithm == current.room.algorithm
      else {
        throw MatchServiceError(
          code: .invalidCommand,
          message:
            "The fixture transition violates match identity, revision, course, or algorithm lock.")
      }
    } else {
      guard next.snapshot.revision >= 1, next.snapshot.room.phase == .lobby else {
        throw MatchServiceError(
          code: .invalidCommand, message: "Room entry must produce a lobby snapshot.")
      }
    }
    transitions.removeFirst()
    current = next.snapshot
    let receipt = CommandReceipt(
      commandID: command.id, acceptedRevision: next.snapshot.revision, snapshot: next.snapshot)
    receipts[command.id] = (command, receipt)
    let invalidation = SnapshotInvalidation(
      matchID: next.snapshot.room.matchID, revision: next.snapshot.revision)
    for subscriber in subscribers.values { subscriber.yield(invalidation) }
    return receipt
  }

  public func snapshot(for matchID: MatchID) async throws -> MatchSnapshot {
    try Task.checkCancellation()
    return try requireMatch(matchID)
  }

  public func invalidations(for matchID: MatchID) async throws -> AsyncThrowingStream<
    SnapshotInvalidation, any Error
  > {
    try Task.checkCancellation()
    let current = try requireMatch(matchID)
    let id = UUID()
    let pair = AsyncThrowingStream<SnapshotInvalidation, any Error>.makeStream(
      bufferingPolicy: .bufferingNewest(1))
    subscribers[id] = pair.continuation
    pair.continuation.onTermination = { [weak self] _ in
      Task { await self?.removeSubscriber(id) }
    }
    pair.continuation.yield(.init(matchID: matchID, revision: current.revision))
    return pair.stream
  }

  /// Call when a preview/test ends; consumers should also cancel their observing task.
  public func finish() {
    for subscriber in subscribers.values { subscriber.finish() }
    subscribers.removeAll()
  }

  private func removeSubscriber(_ id: UUID) { subscribers[id] = nil }
  private func requireMatch(_ id: MatchID) throws -> MatchSnapshot {
    guard let current, id == current.room.matchID else {
      throw MatchServiceError(
        code: .notMember, message: "The fixture session does not belong to this match.")
    }
    return current
  }
}
