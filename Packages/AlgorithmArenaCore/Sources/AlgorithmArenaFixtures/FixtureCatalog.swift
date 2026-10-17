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
    // Additive engine/course examples preserve the original v1 mock contract documents.
    for scenario in SearchFixtures.scenarios {
      let prefix = "search/\(scenario.id.rawValue)"
      try add("\(prefix)/scenario.json", scenario)
      for algorithm in AlgorithmKind.allCases {
        try add(
          "\(prefix)/\(algorithm.rawValue).json",
          SearchEngine.search(scenario, algorithm: algorithm))
      }
    }
    let candidate = try GilmorehillCourse.candidate()
    let navigator = try CourseNavigator(
      course: candidate, expected: GilmorehillCourse.candidateReference)
    let prefix = "courses/\(candidate.reference.id.rawValue)/\(candidate.reference.version)"
    try add("\(prefix)/course.json", candidate)
    let network = CampusPathNetwork(course: candidate)
    let router = try CampusRouter(network: network, expected: candidate.reference)
    try add("\(prefix)/network.json", network)
    let selections: [(String, Coordinate, Coordinate)] = [
      (
        "interior-points", .init(latitude: 55.87370, longitude: -4.29350),
        .init(latitude: 55.87340, longitude: -4.28875)
      ),
      (
        "same-path-reverse", .init(latitude: 55.87380, longitude: -4.29344),
        .init(latitude: 55.87330, longitude: -4.29367)
      ),
    ]
    for (id, source, goal) in selections {
      let graph = try router.graph(from: source, to: goal)
      let requestPrefix = "\(prefix)/requests/\(id)"
      try add("\(requestPrefix)/graph.json", graph)
      for algorithm in AlgorithmKind.allCases {
        let result = try graph.search(algorithm: algorithm)
        try add("\(requestPrefix)/\(algorithm.rawValue)-trace.json", result.trace)
        try add("\(requestPrefix)/\(algorithm.rawValue)-route.json", result.route)
      }
    }
    try add(
      "\(prefix)/heuristics.json",
      candidate.nodes.sorted { $0.id < $1.id }.map { try navigator.heuristics(to: $0.id) })
    for branch in RouteBranch.allCases {
      try add("\(prefix)/\(branch.rawValue)-route.json", navigator.route(for: branch))
    }
    for algorithm in AlgorithmKind.allCases {
      try add(
        "\(prefix)/\(algorithm.rawValue)-trace.json",
        navigator.search(
          from: candidate.stops.start, to: candidate.stops.finish, algorithm: algorithm
        ).trace)
    }
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
