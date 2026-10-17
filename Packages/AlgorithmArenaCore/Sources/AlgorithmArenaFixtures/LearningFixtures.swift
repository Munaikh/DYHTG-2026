import AlgorithmArenaCore
import Foundation

extension ArenaFixtures {
  public static func challengeID(_ slot: ChallengeSlot, _ algorithm: AlgorithmKind) -> ChallengeID {
    .init(rawValue: "fixture-\(algorithm.rawValue)-\(slot.rawValue)-v1")
  }

  public static func scenario(for slot: ChallengeSlot = .first) -> GraphScenario {
    // Different graphs prevent an earlier released replay from disclosing a later question.
    let (ids, costs): ([NodeID], [Int]) =
      switch slot {
      case .practice: (["P", "Q", "R", "U"], [3, 1, 4, 7])
      case .first: (["S", "A", "B", "G"], [2, 1, 3, 8])
      case .standardMiddle: (["M", "N", "O", "V"], [4, 2, 5, 9])
      case .bonusMiddle: (["J", "K", "L", "W"], [3, 2, 4, 10])
      case .third: (["D", "E", "F", "H"], [5, 2, 4, 11])
      case .learningCheck: (["X", "Y", "Z", "T"], [4, 2, 3, 9])
      }
    let total = costs[0] + costs[2]
    let h = [total - 1, costs[2], total, 0]
    return .init(
      id: .init(rawValue: "fixture-scenario-\(slot.rawValue)-v1"),
      nodes: zip(ids, h).map { .init(id: $0.0, label: $0.0.rawValue, heuristic: $0.1) },
      edges: [
        .init(from: ids[0], to: ids[1], cost: costs[0], bidirectional: false),
        .init(from: ids[0], to: ids[2], cost: costs[1], bidirectional: false),
        .init(from: ids[1], to: ids[3], cost: costs[2], bidirectional: false),
        .init(from: ids[2], to: ids[3], cost: costs[3], bidirectional: false),
      ], source: ids[0], goal: ids[3]
    )
  }

  /// Hand-authored deterministic trace, not the search engine planned in #4.
  public static func trace(_ algorithm: AlgorithmKind, slot: ChallengeSlot = .first) -> SearchTrace
  {
    let graph = scenario(for: slot)
    let s = graph.nodes[0].id
    let a = graph.nodes[1].id
    let b = graph.nodes[2].id
    let g = graph.nodes[3].id
    let aCost = graph.edges[0].cost
    let bCost = graph.edges[1].cost
    let viaB = bCost + graph.edges[3].cost
    let viaA = aCost + graph.edges[2].cost
    var costs = graph.nodes.map {
      NodeCost(nodeID: $0.id, g: $0.id == s ? 0 : nil, h: $0.heuristic, predecessor: nil)
    }
    var frontier: [NodeID] = [s]
    var settled: [NodeID] = []
    var steps: [SearchStep] = []
    func record(_ event: SearchEvent) {
      steps.append(
        .init(
          index: steps.count, event: event,
          state: .init(frontier: frontier, settled: settled, costs: costs)))
    }
    func expand(_ node: NodeID) {
      frontier.removeAll { $0 == node }
      settled.append(node)
      record(.expand(nodeID: node))
    }
    func relax(_ from: NodeID, _ to: NodeID, _ value: Int) {
      let index = costs.firstIndex { $0.nodeID == to }!
      let old = costs[index]
      costs[index] = .init(nodeID: to, g: value, h: old.h, predecessor: from)
      if !frontier.contains(to) { frontier.append(to) }
      frontier.sort { left, right in
        let l = costs.first { $0.nodeID == left }!
        let r = costs.first { $0.nodeID == right }!
        let lp = l.g! + (algorithm == .aStar ? l.h : 0)
        let rp = r.g! + (algorithm == .aStar ? r.h : 0)
        return lp == rp ? left < right : lp < rp
      }
      record(.relax(from: from, to: to, previousCost: old.g, candidateCost: value, accepted: true))
    }
    record(.initial)
    expand(s)
    relax(s, a, aCost)
    relax(s, b, bCost)
    if algorithm == .dijkstra {
      expand(b)
      relax(b, g, viaB)
    }
    expand(a)
    relax(a, g, viaA)
    expand(g)
    record(.reachedGoal(nodeID: g))
    return .init(
      scenarioID: graph.id, algorithm: algorithm, steps: steps,
      outcome: .route(nodeIDs: [s, a, g], cost: viaA))
  }

  public static func challenge(_ slot: ChallengeSlot, _ algorithm: AlgorithmKind)
    -> ChallengeDefinition
  {
    let graph = scenario(for: slot)
    let s = graph.source.rawValue
    let a = graph.nodes[1].id
    let b = graph.nodes[2].id
    let g = graph.goal
    let aCost = graph.edges[0].cost
    let bCost = graph.edges[1].cost
    let aEdge = graph.edges[2].cost
    let bEdge = graph.edges[3].cost
    let action: ChallengeAction
    let prompt: String
    switch slot {
    case .practice, .first:
      action = .selectNode(options: [a, b])
      prompt = "Which frontier node is expanded next?"
    case .standardMiddle:
      action = .enterCost(nodeID: g)
      prompt =
        "Via \(b.rawValue), g = \(bCost) and the edge to \(g.rawValue) costs \(bEdge). What is the candidate cost to \(g.rawValue)?"
    case .bonusMiddle:
      action = .enterCost(nodeID: g)
      prompt =
        "Via \(b.rawValue) the candidate cost to \(g.rawValue) is \(bCost + bEdge). Via \(a.rawValue), g = \(aCost) and the edge to \(g.rawValue) costs \(aEdge). Which lower cost should be kept?"
    case .third:
      action = .selectRoute(options: [
        .init(id: "via-a", text: "\(s) → \(a.rawValue) → \(g.rawValue)"),
        .init(id: "via-b", text: "\(s) → \(b.rawValue) → \(g.rawValue)"),
      ])
      prompt = "Which route has the lower total cost?"
    case .learningCheck:
      action = .transfer(
        nodeOptions: [a, b],
        reasons: [
          .init(
            id: "priority",
            text: algorithm == .aStar
              ? "It has the smallest g + h." : "It has the smallest tentative cost g."),
          .init(id: "heuristic-only", text: "It has the smallest h alone."),
        ])
      prompt =
        "On this new graph, choose the next node and explain why. This does not affect your score."
    }
    let points =
      switch slot {
      case .practice, .learningCheck: 0
      case .bonusMiddle: 40
      default: 20
      }
    return .init(
      id: challengeID(slot, algorithm), contentVersion: "fixture-1", algorithm: algorithm,
      slot: slot,
      scenario: graph, presentedState: trace(algorithm, slot: slot).steps[3].state,
      prompt: prompt, action: action, maximumPoints: points,
      feedbackGate: slot == .first || slot == .third ? .afterBothSubmissions : .immediate)
  }

  public static func correctAnswer(_ slot: ChallengeSlot, _ algorithm: AlgorithmKind)
    -> SubmittedAnswer
  {
    let graph = scenario(for: slot)
    return switch slot {
    case .practice, .first: .node(nodeID: graph.nodes[algorithm == .aStar ? 1 : 2].id)
    case .standardMiddle: .cost(value: graph.edges[1].cost + graph.edges[3].cost)
    case .bonusMiddle: .cost(value: graph.edges[0].cost + graph.edges[2].cost)
    case .third: .route(optionID: "via-a")
    case .learningCheck:
      .transfer(nodeID: graph.nodes[algorithm == .aStar ? 1 : 2].id, reasonID: "priority")
    }
  }

  public static func feedback(_ slot: ChallengeSlot, _ algorithm: AlgorithmKind) -> ReleasedFeedback
  {
    let definition = challenge(slot, algorithm)
    let graph = definition.scenario
    let a = graph.nodes[1]
    let b = graph.nodes[2]
    let aCost = graph.edges[0].cost
    let bCost = graph.edges[1].cost
    let aEdge = graph.edges[2].cost
    let bEdge = graph.edges[3].cost
    let explanation: String
    let worked: [String]
    switch slot {
    case .practice, .first, .learningCheck:
      explanation =
        algorithm == .aStar
        ? "Use the smallest g + h, not h alone. The estimate h is not a confirmed walking cost."
        : "Use the smallest tentative distance from the source, not closeness to the goal."
      worked =
        algorithm == .aStar
        ? [
          "\(a.label): \(aCost) + \(a.heuristic) = \(aCost + a.heuristic)",
          "\(b.label): \(bCost) + \(b.heuristic) = \(bCost + b.heuristic)", "Expand \(a.label).",
        ] : ["g(\(a.label)) = \(aCost)", "g(\(b.label)) = \(bCost)", "Expand \(b.label)."]
    case .standardMiddle:
      explanation = "Add the cost so far to the outgoing edge cost."
      worked = [
        "g(\(b.label)) + cost(\(b.label), \(graph.goal.rawValue)) = \(bCost) + \(bEdge) = \(bCost + bEdge)"
      ]
    case .bonusMiddle:
      explanation = "Replace the tentative cost only when the new path is cheaper."
      worked = [
        "Via \(a.label): \(aCost) + \(aEdge) = \(aCost + aEdge)",
        "\(aCost + aEdge) < \(bCost + bEdge), so keep \(aCost + aEdge) via \(a.label).",
      ]
    case .third:
      explanation =
        "The final route uses \(a.label). Search exploration and the route you walk are different."
      worked = [
        "Via \(a.label): \(aCost) + \(aEdge) = \(aCost + aEdge)",
        "Via \(b.label): \(bCost) + \(bEdge) = \(bCost + bEdge)",
        "\(aCost + aEdge) < \(bCost + bEdge)",
      ]
    }
    let answer = correctAnswer(slot, algorithm)
    var answers = [
      ReleasedAnswer(
        playerID: playerID, answer: answer, isCorrect: true, awardedPoints: definition.maximumPoints
      )
    ]
    if definition.feedbackGate == .afterBothSubmissions {
      answers.append(
        .init(
          playerID: opponentID,
          answer: slot == .third
            ? .route(optionID: "via-b") : .node(nodeID: algorithm == .aStar ? b.id : a.id),
          isCorrect: false, awardedPoints: 0))
    }
    return .init(
      challengeID: definition.id, correctAnswer: answer, explanation: explanation,
      workedSteps: worked,
      trace: trace(algorithm, slot: slot), answers: answers)
  }
}
