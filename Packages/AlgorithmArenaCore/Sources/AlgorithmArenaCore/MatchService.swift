import Foundation

public struct CommandReceipt: Codable, Equatable, Sendable {
  public let commandID: UUID
  /// Revision at the original successful commit, retained on duplicate delivery.
  public let acceptedRevision: Int
  public let snapshot: MatchSnapshot
  public init(commandID: UUID, acceptedRevision: Int, snapshot: MatchSnapshot) {
    self.commandID = commandID
    self.acceptedRevision = acceptedRevision
    self.snapshot = snapshot
  }
}

/// Realtime is an invalidation signal only, with no private or scored content.
public struct SnapshotInvalidation: Codable, Equatable, Sendable {
  public let matchID: MatchID
  public let revision: Int
  public init(matchID: MatchID, revision: Int) {
    self.matchID = matchID
    self.revision = revision
  }
}

/// One instance is bound to one authenticated player session. Session persistence
/// and transport authentication belong to the adapter, outside this package.
public protocol MatchService: Sendable {
  func send(_ command: MatchCommand) async throws -> CommandReceipt
  func snapshot(for matchID: MatchID) async throws -> MatchSnapshot
  func invalidations(for matchID: MatchID) async throws -> AsyncThrowingStream<
    SnapshotInvalidation, any Error
  >
}

/// Local persistence model, never a room payload. Keep the entire command unchanged
/// while its outcome is uncertain, including the original revision and identifier.
public struct ReconnectState: Codable, Equatable, Sendable {
  public let lastConfirmedSnapshot: MatchSnapshot
  public let pendingCommand: MatchCommand?
  public init(lastConfirmedSnapshot: MatchSnapshot, pendingCommand: MatchCommand?) {
    self.lastConfirmedSnapshot = lastConfirmedSnapshot
    self.pendingCommand = pendingCommand
  }
}
