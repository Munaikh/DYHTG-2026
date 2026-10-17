import Foundation

/// Shared indoor algorithms for lessons, practice and Plot Twist Duel. The outdoor AlgorithmKind contract stays unchanged.
public enum StudyAlgorithm: String, Codable, CaseIterable, Identifiable, Sendable {
  case bfs, dfs, dijkstra, aStar, greedy
  public var id: String { rawValue }
  public var title: String { name }
  /// Rendering adapter only; execution always uses StudySearch for this algorithm.
  public var graphDisplayAlgorithm: AlgorithmKind { self == .aStar ? .aStar : .dijkstra }
  public var tieRule: String {
    switch self {
    case .bfs: "Queue: first in, first out. Discover neighbours in node ID order."
    case .dfs: "Stack: follow the lowest-ID unvisited neighbour first; backtrack when needed."
    case .greedy: "Choose the lowest h. Equal estimates use node ID order."
    case .dijkstra, .aStar: "Equal priorities use node ID order."
    }
  }
  public var name: String {
    switch self {
    case .bfs: "Breadth-first search"
    case .dfs: "Depth-first search"
    case .dijkstra: "Dijkstra"
    case .aStar: "A* search"
    case .greedy: "Greedy best-first"
    }
  }
  public var shortName: String {
    switch self {
    case .bfs: "BFS"
    case .dfs: "DFS"
    case .dijkstra: "Dijkstra"
    case .aStar: "A*"
    case .greedy: "Greedy"
    }
  }
  public var symbol: String {
    switch self {
    case .bfs: "water.waves"
    case .dfs: "arrow.down.right.and.arrow.up.left"
    case .dijkstra: "point.topleft.down.to.point.bottomright.curvepath"
    case .aStar: "sparkles"
    case .greedy: "scope"
    }
  }
  public var rule: String {
    switch self {
    case .bfs: "Visit nearby points first. Use the first point added to the queue."
    case .dfs: "Follow one branch deeply. Use the next point on top of the stack."
    case .dijkstra: "Choose the available point with the lowest cost from the start."
    case .aStar: "Choose the lowest total: cost so far (g) + estimated cost left (h)."
    case .greedy: "Choose the point with the lowest estimate of the cost left (h)."
    }
  }
  public var caveat: String {
    switch self {
    case .bfs:
      "BFS finds a shortest path by number of edges in an unweighted graph. It ignores weighted costs."
    case .dfs: "DFS explores deeply, but does not generally find a shortest path."
    case .dijkstra: "Dijkstra finds lowest-cost paths when all edge costs are non-negative."
    case .aStar:
      "This graph uses a consistent, admissible estimate. These assumptions let A* find a lowest-cost path. It does not always visit fewer points."
    case .greedy:
      "The smallest estimate is tempting, but Greedy does not generally guarantee the cheapest path."
    }
  }
}

public struct StudyTrace: Equatable, Sendable {
  public let algorithm: StudyAlgorithm
  public let scenario: GraphScenario
  public let steps: [SearchStep]
  public let outcome: SearchOutcome
}

public enum StudySearch {
  public static func run(_ scenario: GraphScenario, algorithm: StudyAlgorithm) throws -> StudyTrace
  {
    // Reuse the team's tested implementations and validation; never extend AlgorithmKind.
    let reference = try SearchEngine.search(
      scenario, algorithm: algorithm == .aStar ? .aStar : .dijkstra)
    if algorithm == .dijkstra || algorithm == .aStar {
      return StudyTrace(
        algorithm: algorithm, scenario: scenario, steps: reference.steps, outcome: reference.outcome
      )
    }
    struct Arc {
      let to: NodeID
      let cost: Int
    }
    var adjacency: [NodeID: [Arc]] = [:]
    for e in scenario.edges {
      adjacency[e.from, default: []].append(Arc(to: e.to, cost: e.cost))
      if e.bidirectional && e.from != e.to {
        adjacency[e.to, default: []].append(Arc(to: e.from, cost: e.cost))
      }
    }
    adjacency = adjacency.mapValues {
      $0.sorted { $0.to == $1.to ? $0.cost < $1.cost : $0.to < $1.to }
    }
    let ids = scenario.nodes.map(\.id).sorted()
    let h = Dictionary(uniqueKeysWithValues: scenario.nodes.map { ($0.id, $0.heuristic) })
    var frontier = [scenario.source]
    var visited: [NodeID] = []
    var costs: [NodeID: Int] = [scenario.source: 0]
    var parents: [NodeID: NodeID] = [:]
    var steps: [SearchStep] = []
    func record(_ event: SearchEvent) {
      steps.append(
        SearchStep(
          index: steps.count, event: event,
          state: SearchState(
            frontier: frontier, settled: visited,
            costs: ids.map {
              NodeCost(nodeID: $0, g: costs[$0], h: h[$0]!, predecessor: parents[$0])
            })))
    }
    record(.initial)
    while !frontier.isEmpty {
      if algorithm == .greedy { frontier.sort { h[$0]! == h[$1]! ? $0 < $1 : h[$0]! < h[$1]! } }
      let current = frontier.removeFirst()
      visited.append(current)
      record(.expand(nodeID: current))
      if current == scenario.goal {
        var path = [current]
        while let parent = parents[path.last!] { path.append(parent) }
        record(.reachedGoal(nodeID: current))
        return StudyTrace(
          algorithm: algorithm, scenario: scenario, steps: steps,
          outcome: .route(nodeIDs: path.reversed(), cost: costs[current]!))
      }
      let arcs = adjacency[current, default: []]
      let ordered = algorithm == .dfs ? Array(arcs.reversed()) : arcs
      for arc in ordered {
        let old = costs[arc.to]
        let (candidate, overflow) = costs[current]!.addingReportingOverflow(arc.cost)
        guard !overflow, candidate <= SearchEngine.maximumCost else {
          throw SearchError.costOverflow
        }
        // DFS may encounter a pending node through the current deeper branch.
        // Move it to the stack top and record that branch as its parent.
        // Settled parents stay fixed, so paths cannot form a cycle.
        let accepted = algorithm == .dfs ? !visited.contains(arc.to) : old == nil
        if accepted {
          costs[arc.to] = candidate
          parents[arc.to] = current
          if algorithm == .dfs {
            frontier.removeAll { $0 == arc.to }
            frontier.insert(arc.to, at: 0)
          } else {
            frontier.append(arc.to)
          }
          if algorithm == .greedy { frontier.sort { h[$0]! == h[$1]! ? $0 < $1 : h[$0]! < h[$1]! } }
        }
        record(
          .relax(
            from: current, to: arc.to, previousCost: old, candidateCost: candidate,
            accepted: accepted))
      }
    }
    record(.unreachable)
    return StudyTrace(algorithm: algorithm, scenario: scenario, steps: steps, outcome: .unreachable)
  }
}
