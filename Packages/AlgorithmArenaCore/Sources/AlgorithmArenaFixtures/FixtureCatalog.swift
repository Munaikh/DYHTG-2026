import AlgorithmArenaCore
import Foundation

public enum FixtureCatalog {
  /// Canonical synthetic fixture source. Exported JSON is checked in for other languages.
  public static func documents() throws -> [String: Data] {
    var documents: [String: Data] = [:]
    func add<T: Encodable>(_ path: String, _ value: T) throws {
      documents[path] = try ContractJSON.encoder().encode(value) + Data([0x0A])
    }
    try add("course.json", ArenaFixtures.course)
    for algorithm in AlgorithmKind.allCases {
      let prefix = algorithm.rawValue
      try add("\(prefix)/trace.json", ArenaFixtures.trace(algorithm))
      try add("\(prefix)/transfer-trace.json", ArenaFixtures.trace(algorithm, slot: .learningCheck))
      for slot in ChallengeSlot.allCases {
        try add(
          "\(prefix)/challenges/\(slot.rawValue).json", ArenaFixtures.challenge(slot, algorithm))
      }
      for fixture in MatchFixture.allCases {
        try add(
          "\(prefix)/snapshots/\(fixture.rawValue).json",
          ArenaFixtures.snapshot(fixture, algorithm: algorithm))
      }
      try add("\(prefix)/reconnect.json", ArenaFixtures.reconnect(algorithm))
      try add("\(prefix)/submit-command.json", ArenaFixtures.submissionCommand(algorithm))
      try add(
        "\(prefix)/submit-receipt.json",
        CommandReceipt(
          commandID: ArenaFixtures.submissionCommandID, acceptedRevision: 9,
          snapshot: ArenaFixtures.snapshot(.routeChoice, algorithm: algorithm)))
      try add(
        "\(prefix)/public-pending.json",
        ArenaFixtures.snapshot(.pendingFeedback, algorithm: algorithm).room)
    }
    for (index, action) in commandExamples.enumerated() {
      let entry: Bool =
        switch action {
        case .createRoom, .joinRoom: true
        default: false
        }
      let command = MatchCommand(
        id: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", 100 + index))!,
        scope: entry
          ? .roomEntry
          : .match(
            matchID: ArenaFixtures.matchID, course: ArenaFixtures.courseReference,
            expectedRevision: 1),
        action: action)
      try add("commands/\(index + 1).json", command)
    }
    try add("invalidation.json", SnapshotInvalidation(matchID: ArenaFixtures.matchID, revision: 10))
    try add(
      "stale-revision-error.json",
      MatchServiceError(code: .staleRevision, message: "Refetch the snapshot.", currentRevision: 10)
    )
    return documents
  }

  public static let commandExamples: [MatchAction] = [
    .createRoom(nickname: "Alex", course: ArenaFixtures.courseReference, algorithm: .dijkstra),
    .joinRoom(code: "ARENA1", nickname: "Sam"),
    .selectAlgorithm(algorithm: .aStar),
    .confirmAlgorithm(algorithm: .aStar),
    .setReady(ready: true), .start,
    .confirmArrival(
      nodeID: "start",
      evidence: .location(
        fix: .init(
          coordinate: .init(latitude: 0, longitude: 0), capturedAt: ArenaFixtures.timestamp,
          horizontalAccuracyMetres: 8))),
    .chooseRoute(branch: .bonus),
    .submitAnswer(
      challengeID: ArenaFixtures.challengeID(.first, .dijkstra), answer: .node(nodeID: "B")),
    .finish(evidence: .organiserApproval(approvalID: "synthetic-single-use-approval")),
    .leave,
  ]
}
