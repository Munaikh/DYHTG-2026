import AlgorithmArenaCore

/// Public synthetic algorithm cases for Swift/server parity; no live challenge answers.
public enum SearchFixtures {
  public static let scenarios: [GraphScenario] = [
    graph(
      "relaxation", ["S", "A", "B", "G"], [0, 0, 0, 0],
      [
        edge("S", "A", 8), edge("S", "B", 1), edge("B", "A", 2), edge("A", "G", 1),
        edge("B", "G", 9),
      ]),
    graph(
      "ties", ["S", "A", "B", "G"], [0, 0, 0, 0],
      [
        edge("S", "B", 1), edge("S", "A", 1), edge("B", "G", 2), edge("A", "G", 2),
      ]),
    graph(
      "zero-cycle", ["S", "A", "B", "G"], [0, 0, 0, 0],
      [
        edge("S", "B", 0), edge("S", "A", 0), edge("A", "B", 0, both: true),
        edge("A", "G", 1), edge("B", "G", 1), edge("A", "A", 0),
      ]),
    graph(
      "unreachable", ["S", "A", "B", "G"], [0, 0, 0, 0],
      [
        edge("S", "A", 1, both: true), edge("G", "B", 1),
      ]),
    graph(
      "priority", ["S", "A", "B", "G"], [4, 4, 3, 0],
      [
        edge("S", "A", 1), edge("S", "B", 3), edge("A", "G", 4), edge("B", "G", 3),
      ]),
    // Both routes cost 4; A* validly chooses a different optimal route to Dijkstra.
    graph(
      "different-optimal-routes", ["S", "A", "B", "G"], [2, 3, 0, 0],
      [
        edge("S", "A", 1), edge("S", "B", 2), edge("A", "G", 3), edge("B", "G", 2),
      ]),
    graph(
      "parallel", ["S", "A", "G"], [2, 1, 0],
      [
        edge("S", "A", 5), edge("S", "A", 1), edge("A", "G", 1),
      ]),
    .init(
      id: "fixture-search-source-is-goal-v1", nodes: [.init(id: "S", label: "S", heuristic: 0)],
      edges: [], source: "S", goal: "S"),
  ]

  private static func graph(_ id: String, _ ids: [NodeID], _ h: [Int], _ edges: [ScenarioEdge])
    -> GraphScenario
  {
    .init(
      id: .init(rawValue: "fixture-search-\(id)-v1"),
      nodes: zip(ids, h).map { .init(id: $0.0, label: $0.0.rawValue, heuristic: $0.1) },
      edges: edges, source: "S", goal: "G")
  }

  private static func edge(_ from: NodeID, _ to: NodeID, _ cost: Int, both: Bool = false)
    -> ScenarioEdge
  {
    .init(from: from, to: to, cost: cost, bidirectional: both)
  }
}
