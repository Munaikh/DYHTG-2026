import AlgorithmArenaCore
import Foundation
import Testing

private struct ServerWire: Decodable {
  let receipts: [CommandReceipt]
  let snapshots: [MatchSnapshot]
  let errors: [MatchServiceError]
  let reconnects: [ReconnectState]
}

// The backend CI job generates this corpus from actual REST responses. Ordinary
// package tests require no running database; setting the path makes parity mandatory.
@Test(.enabled(if: ProcessInfo.processInfo.environment["ARENA_MATCH_WIRE_OUTPUT"] != nil))
func serverResponsesMatchSwiftContract() throws {
  let path = try #require(ProcessInfo.processInfo.environment["ARENA_MATCH_WIRE_OUTPUT"])
  let wire = try ContractJSON.decoder().decode(
    ServerWire.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
  #expect(!wire.receipts.isEmpty)
  #expect(!wire.snapshots.isEmpty)
  #expect(!wire.errors.isEmpty)
  #expect(wire.reconnects.count == 2)
  let snapshots = wire.snapshots + wire.receipts.map(\.snapshot)
  #expect(Set(snapshots.map { $0.room.algorithm }) == Set(AlgorithmKind.allCases))
  #expect(snapshots.contains { $0.room.phase == .finished })
  #expect(snapshots.contains { $0.room.phase == .incomplete })
  #expect(snapshots.contains { $0.viewer.feedback.contains { if case .pending = $0 { true } else { false } } })
  #expect(snapshots.contains { $0.viewer.learningCheck != nil })
  for receipt in wire.receipts {
    #expect(receipt.acceptedRevision == receipt.snapshot.revision)
  }
  for reconnect in wire.reconnects {
    let pending = try #require(reconnect.pendingCommand)
    let receipt = try #require(wire.receipts.first { $0.commandID == pending.id })
    #expect(receipt.snapshot.supersedes(reconnect.lastConfirmedSnapshot))
    #expect(receipt.snapshot.viewer.submissions.contains { $0.commandID == pending.id })
  }
  for snapshot in snapshots {
    #expect(snapshot.room.players.count == 2 || snapshot.room.phase == .lobby)
    #expect(snapshot.room.players.contains { $0.id == snapshot.viewer.playerID })
    #expect(snapshot.viewer.availableChallenges.allSatisfy { $0.algorithm == snapshot.room.algorithm })
    let decoded = try ContractJSON.decoder().decode(
      MatchSnapshot.self, from: ContractJSON.encoder().encode(snapshot))
    #expect(decoded == snapshot)
  }
  #expect(wire.errors.contains { $0.code == .staleRevision && $0.currentRevision != nil })
  #expect(wire.errors.contains { $0.code == .notMember && $0.currentRevision == nil })
  #expect(wire.errors.contains { $0.code == .incompatibleCourse })
}
