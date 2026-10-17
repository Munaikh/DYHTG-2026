import Foundation

public enum SearchError: Error, Equatable, Sendable {
  case invalidNodeID(NodeID)
  case duplicateNode(NodeID)
  case unknownNode(NodeID)
  case invalidCost(from: NodeID, to: NodeID)
  case invalidHeuristic(NodeID)
  case nonzeroGoalHeuristic(NodeID)
  case inadmissibleHeuristic(NodeID)
  case inconsistentHeuristic(from: NodeID, to: NodeID)
  case costOverflow
}

/// Synchronous, Foundation-only searches for the small prepared course/learning graphs.
/// All replay arrays have a canonical order independent of input array/dictionary order.
public enum SearchEngine {
  /// Costs and priorities must also be exact integers in JavaScript server implementations.
  public static let maximumCost = 9_007_199_254_740_991

  public static func search(_ scenario: GraphScenario, algorithm: AlgorithmKind) throws
    -> SearchTrace
  {
    let graph = try SearchGraph(scenario)
    if algorithm == .aStar { try graph.validateHeuristics(goal: scenario.goal) }
    var distances: [NodeID: Int] = [scenario.source: 0]
    var predecessors: [NodeID: NodeID] = [:]
    var frontier: Set<NodeID> = [scenario.source]
    var settled: [NodeID] = []
    var settledSet: Set<NodeID> = []
    var steps: [SearchStep] = []

    func priority(_ id: NodeID) throws -> Int {
      // Only discovered nodes enter the frontier.
      try checkedCost(distances[id]!, algorithm == .aStar ? graph.heuristics[id]! : 0)
    }
    func orderedFrontier() throws -> [NodeID] {
      let priorities = try Dictionary(uniqueKeysWithValues: frontier.map { ($0, try priority($0)) })
      return frontier.sorted {
        priorities[$0]! == priorities[$1]! ? $0 < $1 : priorities[$0]! < priorities[$1]!
      }
    }
    func record(_ event: SearchEvent) throws {
      steps.append(
        .init(
          index: steps.count, event: event,
          state: .init(
            frontier: try orderedFrontier(), settled: settled,
            costs: graph.nodeIDs.map {
              .init(
                nodeID: $0, g: distances[$0], h: graph.heuristics[$0]!,
                predecessor: predecessors[$0])
            })))
    }

    try record(.initial)
    while let current = try orderedFrontier().first {
      frontier.remove(current)
      settled.append(current)
      settledSet.insert(current)
      try record(.expand(nodeID: current))
      if current == scenario.goal {
        var route = [current]
        while let predecessor = predecessors[route.last!] { route.append(predecessor) }
        try record(.reachedGoal(nodeID: current))
        return .init(
          scenarioID: scenario.id, algorithm: algorithm, steps: steps,
          outcome: .route(nodeIDs: route.reversed(), cost: distances[current]!))
      }
      for edge in graph.adjacency[current, default: []] {
        let candidate = try checkedCost(distances[current]!, edge.cost)
        let previous = distances[edge.to]
        let accepted = !settledSet.contains(edge.to) && (previous == nil || candidate < previous!)
        if accepted {
          distances[edge.to] = candidate
          predecessors[edge.to] = current
          frontier.insert(edge.to)
        }
        // Include rejected, equal-cost and back-edge attempts for explanatory replay.
        try record(
          .relax(
            from: current, to: edge.to, previousCost: previous,
            candidateCost: candidate, accepted: accepted))
      }
    }
    try record(.unreachable)
    return .init(scenarioID: scenario.id, algorithm: algorithm, steps: steps, outcome: .unreachable)
  }

  public static func validateHeuristics(in scenario: GraphScenario) throws {
    try SearchGraph(scenario).validateHeuristics(goal: scenario.goal)
  }
}

func checkedCost(_ left: Int, _ right: Int) throws -> Int {
  let (sum, overflow) = left.addingReportingOverflow(right)
  guard !overflow, sum <= SearchEngine.maximumCost else { throw SearchError.costOverflow }
  return sum
}

/// Canonical adjacency is shared by search and independent reverse-distance validation.
private struct SearchGraph {
  struct Arc {
    let to: NodeID
    let cost: Int
  }
  let nodeIDs: [NodeID]
  let heuristics: [NodeID: Int]
  let adjacency: [NodeID: [Arc]]

  init(_ scenario: GraphScenario) throws {
    var values: [NodeID: Int] = [:]
    for node in scenario.nodes {
      guard isASCIIIdentifier(node.id.rawValue) else { throw SearchError.invalidNodeID(node.id) }
      guard values[node.id] == nil else { throw SearchError.duplicateNode(node.id) }
      guard (0...SearchEngine.maximumCost).contains(node.heuristic) else {
        throw SearchError.invalidHeuristic(node.id)
      }
      values[node.id] = node.heuristic
    }
    for id in [scenario.source, scenario.goal] where values[id] == nil {
      throw SearchError.unknownNode(id)
    }
    var adjacency: [NodeID: [Arc]] = [:]
    for edge in scenario.edges {
      for id in [edge.from, edge.to] where values[id] == nil { throw SearchError.unknownNode(id) }
      guard (0...SearchEngine.maximumCost).contains(edge.cost) else {
        throw SearchError.invalidCost(from: edge.from, to: edge.to)
      }
      adjacency[edge.from, default: []].append(.init(to: edge.to, cost: edge.cost))
      if edge.bidirectional && edge.from != edge.to {
        adjacency[edge.to, default: []].append(.init(to: edge.from, cost: edge.cost))
      }
    }
    self.nodeIDs = values.keys.sorted()
    self.heuristics = values
    self.adjacency = adjacency.mapValues {
      $0.sorted { $0.to == $1.to ? $0.cost < $1.cost : $0.to < $1.to }
    }
  }

  func validateHeuristics(goal: NodeID) throws {
    guard heuristics[goal] == 0 else { throw SearchError.nonzeroGoalHeuristic(goal) }
    // Reverse Dijkstra computes exact distance TO the goal, including on directed graphs.
    var reverse: [NodeID: [Arc]] = [:]
    for from in nodeIDs {
      for edge in adjacency[from, default: []] {
        reverse[edge.to, default: []].append(.init(to: from, cost: edge.cost))
        // Avoid overflowing cost+h: if it exceeds the safe range, consistency holds.
        if heuristics[from]! > edge.cost && heuristics[from]! - edge.cost > heuristics[edge.to]! {
          throw SearchError.inconsistentHeuristic(from: from, to: edge.to)
        }
      }
    }
    var distances: [NodeID: Int] = [goal: 0]
    var remaining: Set<NodeID> = [goal]
    var visited: Set<NodeID> = []
    while let current = remaining.min(by: {
      distances[$0]! == distances[$1]! ? $0 < $1 : distances[$0]! < distances[$1]!
    }) {
      remaining.remove(current)
      visited.insert(current)
      for edge in reverse[current, default: []] where !visited.contains(edge.to) {
        let (candidate, overflow) = distances[current]!.addingReportingOverflow(edge.cost)
        // A distance above the safe range cannot disprove a representable h.
        guard !overflow, candidate <= SearchEngine.maximumCost else { continue }
        if distances[edge.to] == nil || candidate < distances[edge.to]! {
          distances[edge.to] = candidate
          remaining.insert(edge.to)
        }
      }
    }
    for id in nodeIDs {
      if let distance = distances[id], heuristics[id]! > distance {
        throw SearchError.inadmissibleHeuristic(id)
      }
    }
  }
}
