import AlgorithmArenaCore
import Foundation

public enum ActivityMode: String, Codable, Sendable { case lesson, practice }

public struct StudyActivity: Identifiable, Equatable, Sendable {
  public let id: String
  public let algorithm: StudyAlgorithm
  public let mode: ActivityMode
  public let ordinal: Int
  public let trace: StudyTrace
  public let presentedStepIndex: Int
  public let correct: NodeID
  public var title: String {
    if mode == .practice { return "Puzzle \(ordinal + 1)" }
    return ["Meet the graph", "Choose the next point", "Follow the search"][ordinal]
  }
  public var introduction: String {
    if ordinal == 0 && mode == .lesson {
      return
        "A graph is a group of points joined by lines. The numbers on the lines are the costs. \(algorithm.rule)"
    }
    return algorithm.rule
  }
  public var state: SearchState { trace.steps[presentedStepIndex].state }
  public var choices: [NodeID] { state.frontier.sorted() }
  public var reward: Int { mode == .lesson ? 50 : 20 }
  public var explanation: String {
    switch algorithm {
    case .bfs:
      return
        "\(correct.rawValue) was added to the queue first, so it is visited next. The other points wait their turn."
    case .dfs:
      return
        "\(correct.rawValue) is on top of the stack. Visit it next to keep following this branch."
    case .dijkstra:
      return
        "\(correct.rawValue) has the smallest known cost: \(state.costs.first { $0.nodeID == correct }?.g ?? 0). Costs, not the point's position in the picture, determine the choice."
    case .aStar:
      let cost = state.costs.first { $0.nodeID == correct }!
      return
        "\(correct.rawValue): g = \(cost.g!), h = \(cost.h), so f = \(cost.g! + cost.h). This is the smallest available f. Choosing h alone would be Greedy, not A*."
    case .greedy:
      return
        "\(correct.rawValue) has the lowest estimated cost left: h = \(state.costs.first { $0.nodeID == correct }!.h). Greedy ignores cost so far when choosing."
    }
  }
  public var hints: [String] {
    ["Look at the available points with dashed outlines.", algorithm.rule, explanation]
  }
}

public enum StudyCatalog {
  public static let contentVersion = "indoor-v1"
  public static func activities(for algorithm: StudyAlgorithm, mode: ActivityMode) throws
    -> [StudyActivity]
  {
    try (0..<3).map { try activity(algorithm: algorithm, mode: mode, ordinal: $0) }
  }
  public static func activity(algorithm: StudyAlgorithm, mode: ActivityMode, ordinal: Int) throws
    -> StudyActivity
  {
    guard (0..<3).contains(ordinal) else { throw StudyError.unknownActivity }
    let variant = mode == .lesson ? 0 : ordinal + 1
    let graph = try scenario(unitCosts: algorithm == .bfs || algorithm == .dfs, variant: variant)
    let trace = try StudySearch.run(graph, algorithm: algorithm)
    let candidates = trace.steps.indices.filter { i in
      guard i > 0, trace.steps[i - 1].state.frontier.count >= 2 else { return false }
      if case .expand = trace.steps[i].event { return true }
      return false
    }
    guard !candidates.isEmpty else { throw StudyError.noQuestion }
    let next = candidates[ordinal % candidates.count]
    guard case .expand(let correct) = trace.steps[next].event else { throw StudyError.noQuestion }
    return StudyActivity(
      id: "\(contentVersion).\(algorithm.rawValue).\(mode.rawValue).\(ordinal)",
      algorithm: algorithm, mode: mode, ordinal: ordinal, trace: trace,
      presentedStepIndex: next - 1, correct: correct)
  }
  public static func activity(id: String) throws -> StudyActivity {
    let parts = id.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 4, parts[0] == Substring(contentVersion),
      let algorithm = StudyAlgorithm(rawValue: String(parts[1])),
      let mode = ActivityMode(rawValue: String(parts[2])),
      let ordinal = Int(parts[3])
    else { throw StudyError.unknownActivity }
    let activity = try activity(algorithm: algorithm, mode: mode, ordinal: ordinal)
    guard activity.id == id else { throw StudyError.unknownActivity }
    return activity
  }
  public static func scenario(unitCosts: Bool = false, variant: Int = 0) throws -> GraphScenario {
    let raw: [(String, String, Int)] = [
      ("A", "B", 4 + variant), ("A", "C", 2), ("B", "C", 1), ("B", "D", 5), ("C", "D", 8 + variant),
      ("C", "E", 10), ("D", "E", 2), ("D", "F", 6), ("E", "F", 3),
    ]
    let edges = raw.enumerated().compactMap { index, e -> ScenarioEdge? in
      if unitCosts && variant == 2 && index == 2 { return nil }
      if unitCosts && variant == 3 && index == 6 { return nil }
      return ScenarioEdge(
        from: NodeID(rawValue: e.0), to: NodeID(rawValue: e.1), cost: unitCosts ? 1 : e.2,
        bidirectional: true)
    }
    let positions: [(Double, Double)] = [
      (0.08, 0.5), (0.35, 0.15), (0.35, 0.85), (0.66, 0.15), (0.66, 0.85), (0.94, 0.5),
    ]
    let ids = ["A", "B", "C", "D", "E", "F"].map { NodeID(rawValue: $0) }
    let nodes = ids.enumerated().map { i, id in
      ScenarioNode(
        id: id, label: id.rawValue, heuristic: 0,
        position: ScenarioPosition(x: positions[i].0, y: positions[i].1))
    }
    let neutral = GraphScenario(
      id: ScenarioID(rawValue: "indoor-graph-\(unitCosts)-\(variant)"), nodes: nodes, edges: edges,
      source: "A", goal: "F")
    let estimated = try nodes.map { node -> ScenarioNode in
      let from = GraphScenario(
        id: neutral.id, nodes: nodes, edges: edges, source: node.id, goal: "F")
      let outcome = try SearchEngine.search(from, algorithm: .dijkstra).outcome
      guard case .route(_, let cost) = outcome else { throw StudyError.noQuestion }
      return ScenarioNode(id: node.id, label: node.label, heuristic: cost, position: node.position)
    }
    return GraphScenario(id: neutral.id, nodes: estimated, edges: edges, source: "A", goal: "F")
  }
}
public enum StudyError: Error, Equatable {
  case unknownActivity, noQuestion, invalidAnswer, alreadyCompleted, ineligibleReward, lockedTitle,
    invalidProfile, unsupportedVersion
}
