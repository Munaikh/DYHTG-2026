import AlgorithmArenaCore
import Foundation

/// Synthetic development data only. Never enable this product in a live match.
public enum ArenaFixtures {
  public static let courseReference = CourseReference(id: "synthetic-course", version: "fixture-1")
  public static let matchID: MatchID = "fixture-match"
  public static let playerID: PlayerID = "player-one"
  public static let opponentID: PlayerID = "player-two"
  public static let timestamp = Date(timeIntervalSince1970: 1_792_238_400)
  public static let submissionCommandID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!

  public static let course: CourseGraph = {
    let nodes: [CourseNode] = [
      .init(
        id: "start", name: "Demo start", coordinate: .init(latitude: 0, longitude: 0),
        stoppingNote: "Synthetic; not a real stopping area."),
      .init(
        id: "first", name: "Checkpoint one", coordinate: .init(latitude: 0.0009, longitude: 0),
        stoppingNote: "Synthetic."),
      .init(
        id: "standard", name: "Standard middle",
        coordinate: .init(latitude: 0.0018, longitude: 0.0006), stoppingNote: "Synthetic."),
      .init(
        id: "bonus", name: "Bonus middle", coordinate: .init(latitude: 0.0018, longitude: -0.001),
        stoppingNote: "Synthetic."),
      .init(
        id: "third", name: "Checkpoint three", coordinate: .init(latitude: 0.0027, longitude: 0),
        stoppingNote: "Synthetic."),
      .init(
        id: "finish", name: "Demo finish", coordinate: .init(latitude: 0.004, longitude: 0),
        stoppingNote: "Synthetic."),
    ]
    let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.coordinate) })
    func edge(_ id: EdgeID, _ from: NodeID, _ to: NodeID, _ cost: Int) -> CourseEdge {
      // Both IDs are defined in the closed fixture above.
      .init(
        id: id, from: from, to: to, bidirectional: true, costMetres: cost,
        polyline: [byID[from]!, byID[to]!])
    }
    return CourseGraph(
      reference: courseReference, name: "Synthetic branch course — not for navigation",
      readiness: .synthetic,
      nodes: nodes,
      edges: [
        edge("start-first", "start", "first", 100),
        edge("first-standard", "first", "standard", 120),
        edge("standard-third", "standard", "third", 130),
        edge("first-bonus", "first", "bonus", 155),
        edge("bonus-third", "bonus", "third", 170), edge("third-finish", "third", "finish", 150),
      ],
      stops: .init(
        start: "start", first: "first", standardMiddle: "standard", bonusMiddle: "bonus",
        third: "third", finish: "finish"),
      routes: [
        .init(
          branch: .standard,
          edgeIDs: ["start-first", "first-standard", "standard-third", "third-finish"],
          distanceMetres: 500, difficulty: "One cost update", middleRewardPoints: 20),
        .init(
          branch: .bonus, edgeIDs: ["start-first", "first-bonus", "bonus-third", "third-finish"],
          distanceMetres: 575, difficulty: "Compare and replace a tentative cost",
          middleRewardPoints: 40),
      ],
      arrivalPolicy: .init(
        radiusMetres: 25, maximumFixAgeSeconds: 10, maximumHorizontalAccuracyMetres: 20)
    )
  }()
}
