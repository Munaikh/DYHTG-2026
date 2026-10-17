import AlgorithmArenaCore
import AlgorithmArenaFixtures
import Foundation
import Testing

@Test(arguments: SearchFixtures.scenarios, AlgorithmKind.allCases)
func searchGoldenOutcomes(scenario: GraphScenario, algorithm: AlgorithmKind) throws {
  let trace = try SearchEngine.search(scenario, algorithm: algorithm)
  let suffix = scenario.id.rawValue
  let expected: SearchOutcome
  if suffix.contains("unreachable") {
    expected = .unreachable
  } else if suffix.contains("source-is-goal") {
    expected = .route(nodeIDs: ["S"], cost: 0)
  } else if suffix.contains("relaxation") {
    expected = .route(nodeIDs: ["S", "B", "A", "G"], cost: 4)
  } else if suffix.contains("different-optimal") {
    expected = .route(nodeIDs: ["S", algorithm == .dijkstra ? "A" : "B", "G"], cost: 4)
  } else {
    let cost =
      suffix.contains("priority")
      ? 5 : suffix.contains("ties") ? 3 : suffix.contains("parallel") ? 2 : 1
    expected = .route(nodeIDs: ["S", "A", "G"], cost: cost)
  }
  #expect(trace.outcome == expected)
  #expect(trace.steps.first?.event == .initial)
  #expect(trace.steps.map(\.index) == Array(trace.steps.indices))
  #expect(
    trace.steps.last?.event
      == (expected == .unreachable ? .unreachable : .reachedGoal(nodeID: scenario.goal)))
  for step in trace.steps {
    #expect(step.state.costs.map(\.nodeID) == scenario.nodes.map(\.id).sorted())
    #expect(Set(step.state.frontier).isDisjoint(with: step.state.settled))
    #expect(Set(step.state.settled).count == step.state.settled.count)
  }
  let shuffled = GraphScenario(
    id: scenario.id, nodes: scenario.nodes.reversed(), edges: scenario.edges.reversed(),
    source: scenario.source, goal: scenario.goal)
  #expect(try SearchEngine.search(shuffled, algorithm: algorithm) == trace)
  #expect(
    try ContractJSON.decoder().decode(SearchTrace.self, from: ContractJSON.encoder().encode(trace))
      == trace)
}

@Test(arguments: AlgorithmKind.allCases)
func relaxationAndEqualCostRejectionAreExplained(algorithm: AlgorithmKind) throws {
  let replacement = try SearchEngine.search(SearchFixtures.scenarios[0], algorithm: algorithm)
  #expect(
    replacement.steps.contains {
      $0.event == .relax(from: "B", to: "A", previousCost: 8, candidateCost: 3, accepted: true)
    })
  let ties = try SearchEngine.search(SearchFixtures.scenarios[1], algorithm: algorithm)
  let rejected = try #require(
    ties.steps.first {
      $0.event == .relax(from: "B", to: "G", previousCost: 3, candidateCost: 3, accepted: false)
    })
  #expect(rejected.state.costs.first { $0.nodeID == "G" }?.predecessor == "A")
  #expect(ties.steps.last?.state.settled == ["S", "A", "B", "G"])
  let zero = try SearchEngine.search(SearchFixtures.scenarios[2], algorithm: algorithm)
  #expect(
    zero.steps.contains {
      $0.event == .relax(from: "B", to: "A", previousCost: 0, candidateCost: 0, accepted: false)
    })
}

@Test func aStarUsesGPlusHAndCanChooseAnotherOptimalRoute() throws {
  let scenario = SearchFixtures.scenarios[4]
  let trace = try SearchEngine.search(scenario, algorithm: .aStar)
  #expect(
    trace.steps.compactMap { step -> NodeID? in
      if case .expand(let id) = step.event { return id }
      return nil
    } == ["S", "A", "G"])
  let initialFrontier = try #require(trace.steps.first { $0.state.frontier.count == 2 })
  #expect(initialFrontier.state.frontier == ["A", "B"])
  #expect(
    scenario.nodes.first { $0.id == "B" }!.heuristic
      < scenario.nodes.first { $0.id == "A" }!.heuristic)
  let tied = SearchFixtures.scenarios[5]
  #expect(
    try SearchEngine.search(tied, algorithm: .dijkstra).outcome
      == .route(nodeIDs: ["S", "A", "G"], cost: 4))
  #expect(
    try SearchEngine.search(tied, algorithm: .aStar).outcome
      == .route(nodeIDs: ["S", "B", "G"], cost: 4))
}

@Test(arguments: AlgorithmKind.allCases, ChallengeSlot.allCases)
func engineMatchesIndependentAuthoredExamples(algorithm: AlgorithmKind, slot: ChallengeSlot) throws
{
  let actual = try SearchEngine.search(ArenaFixtures.scenario(for: slot), algorithm: algorithm)
  let authored = ArenaFixtures.trace(algorithm, slot: slot)
  #expect(actual.outcome == authored.outcome)
  #expect(actual.steps.map(\.event) == authored.steps.map(\.event))
  #expect(actual.steps.map(\.state.frontier) == authored.steps.map(\.state.frontier))
  #expect(actual.steps.map(\.state.settled) == authored.steps.map(\.state.settled))
  #expect(
    actual.steps.map(\.state.costs)
      == authored.steps.map { $0.state.costs.sorted { $0.nodeID < $1.nodeID } })
}

private func smallGraph(
  nodes: [(NodeID, Int)] = [("S", 0), ("G", 0)],
  edges: [ScenarioEdge] = [.init(from: "S", to: "G", cost: 1, bidirectional: false)],
  source: NodeID = "S", goal: NodeID = "G"
) -> GraphScenario {
  .init(
    id: "validation", nodes: nodes.map { .init(id: $0.0, label: $0.0.rawValue, heuristic: $0.1) },
    edges: edges, source: source, goal: goal)
}

@Test func invalidGraphsFailWithoutTrapping() throws {
  #expect(throws: SearchError.duplicateNode("S")) {
    try SearchEngine.search(
      smallGraph(nodes: [("S", 0), ("S", 0), ("G", 0)]), algorithm: .dijkstra)
  }
  #expect(throws: SearchError.invalidNodeID("é")) {
    try SearchEngine.search(
      smallGraph(nodes: [("S", 0), ("G", 0), ("é", 0)]), algorithm: .dijkstra)
  }
  #expect(throws: SearchError.invalidNodeID("")) {
    try SearchEngine.search(smallGraph(nodes: [("S", 0), ("G", 0), ("", 0)]), algorithm: .dijkstra)
  }
  #expect(throws: SearchError.unknownNode("missing")) {
    try SearchEngine.search(smallGraph(source: "missing"), algorithm: .dijkstra)
  }
  #expect(throws: SearchError.unknownNode("missing")) {
    try SearchEngine.search(smallGraph(goal: "missing"), algorithm: .aStar)
  }
  #expect(throws: SearchError.unknownNode("missing")) {
    try SearchEngine.search(
      smallGraph(edges: [.init(from: "S", to: "missing", cost: 1, bidirectional: false)]),
      algorithm: .dijkstra)
  }
  #expect(throws: SearchError.invalidCost(from: "S", to: "G")) {
    try SearchEngine.search(
      smallGraph(edges: [.init(from: "S", to: "G", cost: -1, bidirectional: false)]),
      algorithm: .dijkstra)
  }
  #expect(throws: SearchError.invalidHeuristic("S")) {
    try SearchEngine.validateHeuristics(in: smallGraph(nodes: [("S", -1), ("G", 0)]))
  }
  #expect(throws: SearchError.nonzeroGoalHeuristic("G")) {
    try SearchEngine.validateHeuristics(in: smallGraph(nodes: [("S", 1), ("G", 1)]))
  }
  #expect(throws: SearchError.inconsistentHeuristic(from: "S", to: "G")) {
    try SearchEngine.search(smallGraph(nodes: [("S", 2), ("G", 0)]), algorithm: .aStar)
  }
  // Dijkstra's selection rule ignores an otherwise nonnegative h.
  #expect(
    try SearchEngine.search(smallGraph(nodes: [("S", 2), ("G", 0)]), algorithm: .dijkstra).outcome
      == .route(nodeIDs: ["S", "G"], cost: 1))
  #expect(throws: SearchError.inconsistentHeuristic(from: "G", to: "S")) {
    try SearchEngine.validateHeuristics(
      in: smallGraph(
        nodes: [("S", 0), ("G", 2)],
        edges: [.init(from: "S", to: "G", cost: 1, bidirectional: true)], goal: "S"))
  }
}

@Test func costsStayWithinCrossLanguageIntegerRange() throws {
  let maximum = SearchEngine.maximumCost
  let graph = smallGraph(edges: [.init(from: "S", to: "G", cost: maximum, bidirectional: false)])
  #expect(
    try SearchEngine.search(graph, algorithm: .dijkstra).outcome
      == .route(nodeIDs: ["S", "G"], cost: maximum))
  #expect(throws: SearchError.invalidCost(from: "S", to: "G")) {
    try SearchEngine.search(
      smallGraph(edges: [.init(from: "S", to: "G", cost: Int.max, bidirectional: false)]),
      algorithm: .dijkstra)
  }
  #expect(throws: SearchError.costOverflow) {
    try SearchEngine.search(
      smallGraph(
        nodes: [("S", 0), ("A", 0), ("G", 0)],
        edges: [
          .init(from: "S", to: "A", cost: maximum, bidirectional: false),
          .init(from: "A", to: "G", cost: 1, bidirectional: false),
        ]), algorithm: .dijkstra)
  }
  #expect(throws: SearchError.costOverflow) {
    try SearchEngine.search(
      smallGraph(
        nodes: [("S", 0), ("A", maximum), ("G", 0)],
        edges: [.init(from: "S", to: "A", cost: 1, bidirectional: false)]), algorithm: .aStar)
  }
}

/// Independent Floyd–Warshall oracle, including disconnected/directed/zero-cost cases.
@Test func generatedGraphsAgreeWithAllPairsOracle() throws {
  let ids: [NodeID] = ["A", "B", "C", "D", "G"]
  for seed in 0..<128 {
    var costs = Array(repeating: Array(repeating: 1_000_000, count: ids.count), count: ids.count)
    var edges: [ScenarioEdge] = []
    for i in ids.indices {
      costs[i][i] = 0
      for j in ids.indices where i != j {
        let value = (seed * 17 + i * 13 + j * 7 + seed / (i + j + 1)) % 11
        if value < 6 {
          costs[i][j] = value
          edges.append(.init(from: ids[i], to: ids[j], cost: value, bidirectional: false))
        }
      }
    }
    for k in ids.indices {
      for i in ids.indices {
        for j in ids.indices { costs[i][j] = min(costs[i][j], costs[i][k] + costs[k][j]) }
      }
    }
    for goal in ids.indices {
      let maximumFinite = costs.map { $0[goal] }.filter { $0 < 1_000_000 }.max()!
      let nodes = ids.indices.map { i in
        ScenarioNode(
          id: ids[i], label: ids[i].rawValue,
          heuristic: costs[i][goal] == 1_000_000 ? maximumFinite : costs[i][goal])
      }
      for source in ids.indices {
        let graph = GraphScenario(
          id: "oracle", nodes: nodes, edges: edges, source: ids[source], goal: ids[goal])
        for algorithm in AlgorithmKind.allCases {
          let outcome = try SearchEngine.search(graph, algorithm: algorithm).outcome
          switch outcome {
          case .unreachable: #expect(costs[source][goal] == 1_000_000)
          case .route(let route, let cost):
            #expect(cost == costs[source][goal])
            #expect(route.first == ids[source] && route.last == ids[goal])
            #expect(Set(route).count == route.count)
          }
        }
      }
    }
  }
}
