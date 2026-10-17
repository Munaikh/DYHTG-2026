import Foundation

/// A learning graph is independent of the player's physical course and branch.
public struct ScenarioNode: Codable, Equatable, Sendable, Identifiable {
  public let id: NodeID
  public let label: String
  public let heuristic: Int
  public init(id: NodeID, label: String, heuristic: Int) {
    self.id = id
    self.label = label
    self.heuristic = heuristic
  }
}

public struct ScenarioEdge: Codable, Equatable, Sendable {
  public let from: NodeID
  public let to: NodeID
  public let cost: Int
  public let bidirectional: Bool
  public init(from: NodeID, to: NodeID, cost: Int, bidirectional: Bool) {
    self.from = from
    self.to = to
    self.cost = cost
    self.bidirectional = bidirectional
  }
}

public struct GraphScenario: Codable, Equatable, Sendable, Identifiable {
  public let id: ScenarioID
  public let nodes: [ScenarioNode]
  public let edges: [ScenarioEdge]
  public let source: NodeID
  public let goal: NodeID
  public init(
    id: ScenarioID, nodes: [ScenarioNode], edges: [ScenarioEdge], source: NodeID, goal: NodeID
  ) {
    self.id = id
    self.nodes = nodes
    self.edges = edges
    self.source = source
    self.goal = goal
  }
}

public struct NodeCost: Codable, Equatable, Sendable {
  public let nodeID: NodeID
  /// nil means undiscovered/infinite, never zero.
  public let g: Int?
  public let h: Int
  public let predecessor: NodeID?
  public init(nodeID: NodeID, g: Int?, h: Int, predecessor: NodeID?) {
    self.nodeID = nodeID
    self.g = g
    self.h = h
    self.predecessor = predecessor
  }
}

public struct SearchState: Codable, Equatable, Sendable {
  /// Ordered by priority (g for Dijkstra, g+h for A*), then node ID.
  public let frontier: [NodeID]
  public let settled: [NodeID]
  public let costs: [NodeCost]
  public init(frontier: [NodeID], settled: [NodeID], costs: [NodeCost]) {
    self.frontier = frontier
    self.settled = settled
    self.costs = costs
  }
}

public enum SearchEvent: Codable, Equatable, Sendable {
  case initial
  case expand(nodeID: NodeID)
  case relax(from: NodeID, to: NodeID, previousCost: Int?, candidateCost: Int, accepted: Bool)
  case reachedGoal(nodeID: NodeID)
  case unreachable
}

public struct SearchStep: Codable, Equatable, Sendable {
  public let index: Int
  public let event: SearchEvent
  /// State immediately after the event; index zero is the initial state.
  public let state: SearchState
  public init(index: Int, event: SearchEvent, state: SearchState) {
    self.index = index
    self.event = event
    self.state = state
  }
}

public enum SearchOutcome: Codable, Equatable, Sendable {
  case route(nodeIDs: [NodeID], cost: Int)
  case unreachable
}

public struct SearchTrace: Codable, Equatable, Sendable {
  public let scenarioID: ScenarioID
  public let algorithm: AlgorithmKind
  public let steps: [SearchStep]
  public let outcome: SearchOutcome
  public init(
    scenarioID: ScenarioID, algorithm: AlgorithmKind, steps: [SearchStep], outcome: SearchOutcome
  ) {
    self.scenarioID = scenarioID
    self.algorithm = algorithm
    self.steps = steps
    self.outcome = outcome
  }
}
