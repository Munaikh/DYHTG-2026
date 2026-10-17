import AlgorithmArenaCore
import Foundation

/// Immutable authored bank for server/authoring tools. No app target dependency.
public enum LearningCatalog {
  public static let contentVersion = "2026-10-17.1"

  public static func challenges(algorithm: AlgorithmKind) throws -> [LearningChallenge] {
    try ChallengeSlot.allCases.map { try challenge($0, algorithm: algorithm) }
  }

  /// Branch selection can replace only the middle question. Shared questions take
  /// no branch, course position or player input, so both players receive identical content.
  public static func matchChallenges(algorithm: AlgorithmKind, branch: RouteBranch) throws
    -> [ChallengeDefinition]
  {
    try [.first, branch == .standard ? ChallengeSlot.standardMiddle : .bonusMiddle, .third].map {
      try challenge($0, algorithm: algorithm).definition
    }
  }

  public static func challenge(_ slot: ChallengeSlot, algorithm: AlgorithmKind) throws
    -> LearningChallenge
  {
    let graph = scenario(slot, algorithm)
    let trace = try SearchEngine.search(graph, algorithm: algorithm)
    let aStar = algorithm == .aStar
    let rule =
      aStar
      ? "g is cost so far; h estimates the remaining cost; f = g + h is the selection priority. Expand the frontier node with the lowest f. h is not a confirmed walking cost."
      : "g is the tentative distance from the start. Expand the unsettled frontier node with the lowest g, regardless of closeness to the goal."
    var prompt: String
    let action: ChallengeAction
    let answer: SubmittedAnswer
    let questionIndex: Int
    var explanation = rule
    var worked: [(String, [Int])] = []
    var routes: [String: [NodeID]] = [:]

    func index(of event: SearchEvent) throws -> Int {
      guard let index = trace.steps.firstIndex(where: { $0.event == event }) else {
        throw LearningContentError.invalidAuthoredContent("Missing event: \(event)")
      }
      return index
    }
    func cost(_ node: NodeID, at index: Int) throws -> NodeCost {
      guard let cost = trace.steps[index].state.costs.first(where: { $0.nodeID == node }),
        cost.g != nil
      else { throw LearningContentError.invalidAuthoredContent("Undiscovered node \(node)") }
      return cost
    }
    func routeCost(_ nodes: [NodeID]) throws -> Int {
      try zip(nodes, nodes.dropFirst()).reduce(0) { total, pair in
        guard let edge = graph.edges.first(where: { $0.from == pair.0 && $0.to == pair.1 }) else {
          throw LearningContentError.invalidAuthoredContent("Missing route edge")
        }
        return total + edge.cost
      }
    }

    switch slot {
    case .practice, .first, .learningCheck:
      let selected: NodeID
      let options: [NodeID]
      if slot == .learningCheck {
        selected = aStar ? "R" : "W"
        options = aStar ? ["Q", "R", "T"] : ["Y", "Z", "W"]
      } else {
        selected = graph.nodes[1].id
        options =
          slot == .practice
          ? [graph.nodes[1].id, graph.nodes[2].id] : [graph.nodes[2].id, graph.nodes[1].id]
      }
      let expandedIndex = try index(of: .expand(nodeID: selected))
      questionIndex = expandedIndex - 1
      if slot == .learningCheck {
        let reasons: [AnswerOption] =
          aStar
          ? [
            .init(id: "cost-only", text: "It has the lowest g alone."),
            .init(id: "goal-distance", text: "It has the lowest h alone."),
            .init(id: "frontier-priority", text: "It has the lowest f = g + h in the frontier."),
            .init(id: "already-settled", text: "It was already expanded."),
          ]
          : [
            .init(id: "goal-distance", text: "It is closest to the goal."),
            .init(id: "frontier-priority", text: "It has the lowest tentative g in the frontier."),
            .init(id: "already-settled", text: "It was already expanded."),
            .init(id: "fewest-edges", text: "It uses the fewest edges from the start."),
          ]
        action = .transfer(nodeOptions: options, reasons: reasons)
        answer = .transfer(nodeID: selected, reasonID: "frontier-priority")
        prompt =
          "This unfamiliar graph is partway through a search. Which frontier node expands next, and why? Your first attempt is recorded separately and earns no match points."
      } else {
        action = .selectNode(options: options)
        answer = .node(nodeID: selected)
        prompt = "Which frontier node expands next?"
        if !aStar {
          prompt =
            "\(graph.nodes[2].label) is drawn closer to the goal. Which frontier node expands next?"
        }
        if slot == .practice { prompt = rule + " " + prompt + " This prediction is unscored." }
      }
      for node in trace.steps[questionIndex].state.frontier {
        let value = try cost(node, at: questionIndex)
        let text =
          aStar
          ? "\(node.rawValue): g = \(value.g!), h = \(value.h), f = \(value.g!) + \(value.h) = \(value.g! + value.h)."
          : "\(node.rawValue): tentative g = \(value.g!)."
        worked.append((text, [questionIndex]))
      }
      worked.append(
        (
          "Expand \(selected.rawValue), the frontier node with the smallest priority value.",
          [expandedIndex]
        ))
      if !aStar && slot != .learningCheck {
        explanation +=
          " \(graph.nodes[2].label) is nearer on the diagram, but its path from the start costs more. Diagram distances are not edge costs."
      }

    case .standardMiddle, .bonusMiddle:
      let bonus = slot == .bonusMiddle
      let from = graph.nodes[bonus ? 2 : 1].id
      let target = graph.nodes[bonus ? 3 : 2].id
      let previous = bonus ? (aStar ? 12 : 9) : (aStar ? 9 : 7)
      let candidate = bonus ? (aStar ? 8 : 5) : 5
      let event = SearchEvent.relax(
        from: from, to: target, previousCost: previous, candidateCost: candidate, accepted: true)
      let updateIndex = try index(of: event)
      let earlier = graph.nodes[1].id
      let earlierIndex =
        bonus ? try relaxationIndex(trace: trace, from: earlier, to: from) : updateIndex
      questionIndex = earlierIndex - 1
      action = .enterCost(nodeID: target)
      answer = .cost(value: candidate)
      prompt =
        bonus
        ? "Starting at \(earlier.rawValue), relax \(earlier.rawValue) → \(from.rawValue), then use that updated g to relax \(from.rawValue) → \(target.rawValue). After both updates, what g(\(target.rawValue)) should be kept?"
        : "Relax \(from.rawValue) → \(target.rawValue). Add the cost so far to the edge cost and compare with the existing tentative cost. What updated g(\(target.rawValue)) should be kept?"
      explanation =
        "Relaxation adds the current node's g to the outgoing edge cost. Replace a tentative cost only when this candidate is cheaper."
      if bonus {
        let earlierCost = try cost(earlier, at: earlierIndex)
        let oldFromCost = try cost(from, at: questionIndex)
        let fromCost = try cost(from, at: earlierIndex)
        let edge = graph.edges.first { $0.from == earlier && $0.to == from }!
        worked.append(
          (
            "First, g(\(from.rawValue)) = g(\(earlier.rawValue)) + cost(\(earlier.rawValue), \(from.rawValue)) = \(earlierCost.g!) + \(edge.cost) = \(fromCost.g!).",
            [earlierIndex]
          ))
        worked.append(
          (
            "\(fromCost.g!) < \(oldFromCost.g!): replace \(oldFromCost.g!) with \(fromCost.g!) before the next calculation.",
            [earlierIndex]
          ))
      }
      let fromCost = try cost(from, at: updateIndex - 1)
      let edge = graph.edges.first { $0.from == from && $0.to == target }!
      worked.append(
        (
          "Candidate g(\(target.rawValue)) = \(fromCost.g!) + \(edge.cost) = \(candidate).",
          [updateIndex - 1, updateIndex]
        ))
      worked.append(
        (
          "\(candidate) < \(previous): replace \(previous) with \(candidate), using predecessor \(from.rawValue).",
          [updateIndex]
        ))
      if aStar {
        let h = graph.nodes.first { $0.id == target }!.heuristic
        explanation += " A* uses the same relaxation for g; h is added only for selection priority."
        worked.append(
          (
            "g(\(target.rawValue)) = \(candidate); h = \(h); f = \(candidate) + \(h) = \(candidate + h). The requested cost is g, not f.",
            [updateIndex]
          ))
      }

    case .third:
      let s = graph.source
      let a = graph.nodes[1].id
      let b = graph.nodes[2].id
      let c = graph.nodes[3].id
      let goal = graph.goal
      routes = ["via-middle": [s, a, c, goal], "via-side": [s, b, goal]]
      let options = ["via-side", "via-middle"].map { id in
        AnswerOption(id: id, text: routes[id]!.map(\.rawValue).joined(separator: " → "))
      }
      questionIndex = 0
      action = .selectRoute(options: options)
      answer = .route(optionID: "via-middle")
      prompt =
        "Which of these routes has the lower total edge cost? The search may expand nodes that are absent from the final route."
      explanation =
        "The final route follows the goal's predecessor chain. Search expansion and the route you walk are different: expanding \(b.rawValue) does not require visiting it on the final route."
      for id in ["via-side", "via-middle"] {
        let nodes = routes[id]!
        let terms = zip(nodes, nodes.dropFirst()).map { from, to in
          String(graph.edges.first { $0.from == from && $0.to == to }!.cost)
        }.joined(separator: " + ")
        worked.append(
          (
            "\(nodes.map(\.rawValue).joined(separator: " → ")): \(terms) = \(try routeCost(nodes)).",
            try zip(nodes, nodes.dropFirst()).map { from, to in
              try relaxationIndex(trace: trace, from: from, to: to)
            }
          ))
      }
      worked.append(
        (
          "\(try routeCost(routes["via-middle"]!)) < \(try routeCost(routes["via-side"]!)): choose the route through \(c.rawValue). \(b.rawValue) is expanded but is not on that route.",
          [try index(of: .expand(nodeID: b)), trace.steps.count - 1]
        ))
      if aStar {
        explanation +=
          " Sum the actual edge costs, not the f estimates. A* does not always expand fewer nodes."
      }
    }

    let points = slot == .practice || slot == .learningCheck ? 0 : slot == .bonusMiddle ? 40 : 20
    let definition = ChallengeDefinition(
      id: .init(rawValue: "learning-\(algorithm.rawValue)-\(slot.rawValue)-v1"),
      contentVersion: contentVersion, algorithm: algorithm, slot: slot, scenario: graph,
      presentedState: trace.steps[questionIndex].state, prompt: prompt, action: action,
      maximumPoints: points,
      feedbackGate: slot == .first || slot == .third ? .afterBothSubmissions : .immediate)
    return .init(
      definition: definition, presentedStepIndex: questionIndex, correctAnswer: answer,
      explanation: explanation, workedSteps: worked.map(\.0),
      workedStepTraceIndices: worked.map(\.1), trace: trace, routes: routes)
  }

  private static func relaxationIndex(trace: SearchTrace, from: NodeID, to: NodeID) throws -> Int {
    guard
      let step = trace.steps.first(where: {
        if case .relax(let a, let b, _, _, true) = $0.event { return a == from && b == to }
        return false
      })
    else { throw LearningContentError.invalidAuthoredContent("Missing cheaper path") }
    return step.index
  }

  private static func scenario(_ slot: ChallengeSlot, _ algorithm: AlgorithmKind) -> GraphScenario {
    let aStar = algorithm == .aStar
    let ids: [NodeID]
    let h: [Int]
    let edges: [(Int, Int, Int)]
    switch slot {
    case .practice:
      ids = ["P", "Q", "R", "T"]
      h = aStar ? [6, 1, 6, 0] : [6, 5, 1, 0]
      let c = aStar ? [6, 2, 2, 8] : [4, 7, 6, 1]
      edges = [(0, 1, c[0]), (0, 2, c[1]), (1, 3, c[2]), (2, 3, c[3])]
    case .first:
      ids = aStar ? ["S", "A", "B", "G"] : ["L", "M", "N", "Z"]
      h = aStar ? [5, 4, 1, 0] : [5, 6, 1, 0]
      let c = aStar ? [3, 8, 5, 2] : [3, 6, 8, 2]
      edges = [(0, 1, c[0]), (0, 2, c[1]), (1, 3, c[2]), (2, 3, c[3])]
    case .standardMiddle:
      ids = aStar ? ["C", "D", "E", "H"] : ["U", "V", "W", "Z"]
      h = aStar ? [5, 4, 3, 0] : [4, 3, 2, 0]
      edges =
        aStar
        ? [(0, 1, 3), (0, 2, 9), (1, 2, 2), (2, 3, 3), (1, 3, 11)]
        : [(0, 1, 2), (0, 2, 7), (1, 2, 3), (2, 3, 2), (1, 3, 10)]
    case .bonusMiddle:
      ids = aStar ? ["C", "D", "E", "F", "H"] : ["J", "K", "L", "M", "Z"]
      h = aStar ? [7, 6, 4, 2, 0] : [6, 5, 4, 2, 0]
      edges =
        aStar
        ? [
          (0, 1, 3), (0, 2, 8), (0, 3, 12), (1, 2, 2), (1, 3, 10), (2, 3, 3), (3, 4, 2), (2, 4, 11),
        ]
        : [(0, 1, 2), (0, 2, 6), (0, 3, 9), (1, 2, 1), (1, 3, 8), (2, 3, 2), (3, 4, 2), (2, 4, 10)]
    case .third:
      ids = aStar ? ["J", "K", "L", "M", "Z"] : ["S", "A", "B", "C", "G"]
      h = aStar ? [3, 4, 1, 2, 0] : [2, 3, 1, 2, 0]
      edges =
        aStar
        ? [(0, 1, 3), (0, 2, 2), (1, 3, 2), (2, 4, 11), (3, 4, 3), (1, 4, 9)]
        : [(0, 1, 2), (0, 2, 1), (1, 3, 2), (2, 4, 10), (3, 4, 3), (1, 4, 9)]
    case .learningCheck:
      ids = aStar ? ["X", "P", "Q", "R", "T"] : ["X", "V", "W", "Y", "Z"]
      h = aStar ? [4, 3, 5, 1, 0] : [3, 3, 2, 1, 0]
      edges =
        aStar
        ? [(0, 1, 1), (0, 2, 5), (0, 4, 12), (1, 2, 3), (1, 3, 6), (2, 3, 4), (2, 4, 5), (3, 4, 1)]
        : [(0, 1, 1), (0, 3, 6), (1, 2, 3), (1, 4, 8), (2, 3, 1), (2, 4, 2), (3, 4, 1)]
    }
    let positions: [ScenarioPosition] =
      ids.count == 4
      ? [
        .init(x: 0.05, y: 0.5), .init(x: 0.35, y: 0.15), .init(x: 0.8, y: 0.7),
        .init(x: 0.95, y: 0.5),
      ]
      : [
        .init(x: 0.05, y: 0.5), .init(x: 0.3, y: 0.15), .init(x: 0.4, y: 0.8),
        .init(x: 0.7, y: 0.2), .init(x: 0.95, y: 0.5),
      ]
    return .init(
      id: .init(rawValue: "learning-\(algorithm.rawValue)-\(slot.rawValue)-graph-v1"),
      nodes: ids.indices.map {
        .init(id: ids[$0], label: ids[$0].rawValue, heuristic: h[$0], position: positions[$0])
      },
      edges: edges.map { .init(from: ids[$0.0], to: ids[$0.1], cost: $0.2, bidirectional: false) },
      source: ids[0], goal: ids[ids.count - 1])
  }
}
