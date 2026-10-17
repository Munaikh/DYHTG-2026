import Foundation

/// Deliberately public, offline teaching material. These graphs and answers are
/// separate from competitive room questions and may be shipped to every client.
public struct PublicLesson: Sendable, Identifiable {
  public var id: String { algorithm.rawValue }
  public let algorithm: AlgorithmKind
  public let title: String
  public let subtitle: String
  public let rule: String
  public let recap: String
  public let scenario: GraphScenario
  public let trace: SearchTrace
  /// Two guided questions, followed by one transfer question on a new graph.
  public let questions: [PublicLessonQuestion]
}

public struct PublicLessonOption: Sendable, Identifiable, Equatable {
  public let id: String
  public let title: String
  public let nodeID: NodeID?
}

public struct PublicLessonQuestion: Sendable, Identifiable {
  public let id: String
  public let title: String
  public let prompt: String
  public let hint: String
  public let explanation: String
  public let scenario: GraphScenario
  public let trace: SearchTrace
  public let beforeStepIndex: Int
  public let revealStepIndex: Int
  public let options: [PublicLessonOption]
  public let correctOptionID: String

  public var before: SearchStep { trace.steps[beforeStepIndex] }
  public var reveal: SearchStep { trace.steps[revealStepIndex] }
  public func isCorrect(_ optionID: String) -> Bool { optionID == correctOptionID }
}

public enum LessonContentError: Error { case missingTeachingEvent }

public enum LessonCatalog {
  public static func lesson(for algorithm: AlgorithmKind) throws -> PublicLesson {
    switch algorithm {
    case .dijkstra: try dijkstra()
    case .aStar: try aStar()
    }
  }

  private static func dijkstra() throws -> PublicLesson {
    let graph = scenario(
      id: "public-lesson-dijkstra-v1",
      nodes: [("S", 0, 0.06, 0.5), ("A", 0, 0.38, 0.15),
              ("B", 0, 0.38, 0.85), ("C", 0, 0.69, 0.5), ("G", 0, 0.95, 0.5)],
      edges: [("S", "A", 7), ("S", "B", 2), ("B", "A", 2),
              ("A", "C", 1), ("B", "C", 6), ("C", "G", 3), ("A", "G", 8)])
    let trace = try SearchEngine.search(graph, algorithm: .dijkstra)
    let choose = try index(in: trace) { $0 == .expand(nodeID: "B") }
    let update = try index(in: trace) {
      $0 == .relax(from: "B", to: "A", previousCost: 7, candidateCost: 4, accepted: true)
    }
    let transfer = scenario(
      id: "public-lesson-dijkstra-transfer-v1",
      nodes: [("S", 0, 0.06, 0.5), ("X", 0, 0.5, 0.15),
              ("Y", 0, 0.5, 0.85), ("G", 0, 0.95, 0.5)],
      edges: [("S", "X", 4), ("S", "Y", 1), ("Y", "X", 1), ("X", "G", 2), ("Y", "G", 8)])
    let transferTrace = try SearchEngine.search(transfer, algorithm: .dijkstra)
    let transferIndex = try index(in: transferTrace) { $0 == .expand(nodeID: "X") }
    return PublicLesson(
      algorithm: .dijkstra, title: "Dijkstra", subtitle: "Find the cheapest way.",
      rule: "Choose the frontier node with the lowest cost so far, g.",
      recap: "Choose the lowest g. Update a cost when a cheaper route appears. Stop when the goal is selected.",
      scenario: graph, trace: trace,
      questions: [
        .init(id: "frontier", title: "Every good route starts small.",
              prompt: "Start S has been explored. Which node comes next?",
              hint: "The frontier contains discovered nodes we have not explored yet. Compare their g values.",
              explanation: "B has g = 2; A has g = 7. Dijkstra picks B because 2 is the lowest cost on the frontier. The destination can wait.",
              scenario: graph, trace: trace, beforeStepIndex: choose - 1, revealStepIndex: choose,
              options: [node("A"), node("B")], correctOptionID: "B"),
        .init(id: "update", title: "A better route changes everything.",
              prompt: "B costs 2 to reach. B → A costs 2. What should A's new g be?",
              hint: "Add the cost so far to the next edge. Keep the result only if it beats A's current 7.",
              explanation: "2 + 2 = 4. That beats A's old cost of 7, so replace it with 4 and remember B as the previous node. This update is called relaxation.",
              scenario: graph, trace: trace, beforeStepIndex: update - 1, revealStepIndex: update,
              options: [number(2), number(4), number(7)], correctOptionID: "4"),
        .init(id: "transfer", title: "New graph. Same superpower.",
              prompt: "Y has been explored and improved X. Which node comes next?",
              hint: "The goal has been discovered, but that does not mean it is ready. Compare frontier costs.",
              explanation: "X now costs 1 + 1 = 2, while G costs 1 + 8 = 9. Choose X. Discovering the goal is not the stopping rule; selecting it with the lowest g is.",
              scenario: transfer, trace: transferTrace, beforeStepIndex: transferIndex - 1,
              revealStepIndex: transferIndex, options: [node("G"), node("X")], correctOptionID: "X"),
      ])
  }

  private static func aStar() throws -> PublicLesson {
    let graph = scenario(
      id: "public-lesson-astar-v1",
      nodes: [("S", 6, 0.06, 0.5), ("A", 5, 0.38, 0.15),
              ("B", 2, 0.38, 0.85), ("C", 3, 0.69, 0.15), ("G", 0, 0.95, 0.5)],
      edges: [("S", "A", 2), ("S", "B", 4), ("A", "C", 2), ("C", "G", 3), ("B", "G", 3)])
    let trace = try SearchEngine.search(graph, algorithm: .aStar)
    let choose = try index(in: trace) { $0 == .expand(nodeID: "B") }
    let transfer = scenario(
      id: "public-lesson-astar-transfer-v1",
      nodes: [("S", 4, 0.06, 0.5), ("X", 6, 0.5, 0.15),
              ("Y", 2, 0.5, 0.85), ("G", 0, 0.95, 0.5)],
      edges: [("S", "X", 1), ("S", "Y", 3), ("X", "G", 7), ("Y", "G", 3)])
    let transferTrace = try SearchEngine.search(transfer, algorithm: .aStar)
    let transferIndex = try index(in: transferTrace) { $0 == .expand(nodeID: "Y") }
    return PublicLesson(
      algorithm: .aStar, title: "A*", subtitle: "Give your search a sense of direction.",
      rule: "Choose the lowest f: cost so far g + estimated cost remaining h.",
      recap: "Use f = g + h. A helpful estimate guides the search. It must not overestimate; our examples also use consistent estimates.",
      scenario: graph, trace: trace,
      questions: [
        .init(id: "frontier", title: "Think ahead. Then choose.",
              prompt: "A is cheaper to reach. Does that make it the next node?",
              hint: "g is paid so far. h estimates what remains. A* compares their total, f = g + h.",
              explanation: "A: 2 + 5 = 7. B: 4 + 2 = 6. A* picks B because its estimated total is lower, even though getting there costs more.",
              scenario: graph, trace: trace, beforeStepIndex: choose - 1, revealStepIndex: choose,
              options: [node("A"), node("B")], correctOptionID: "B"),
        .init(id: "priority", title: "Two numbers. One decision.",
              prompt: "B has g = 4 and h = 2. What is its priority f?",
              hint: "Use both numbers: f = g + h. An estimate is a guide, not an extra edge cost.",
              explanation: "f = 4 + 2 = 6. g = 4 is the real cost so far; h = 2 estimates the remaining cost. We compare f to decide which node to explore.",
              scenario: graph, trace: trace, beforeStepIndex: choose - 1, revealStepIndex: choose,
              options: [number(2), number(4), number(6)], correctOptionID: "6"),
        .init(id: "transfer", title: "Take your intuition somewhere new.",
              prompt: "Different graph. Which frontier node should A* explore?",
              hint: "A low g is only part of the story. Calculate g + h for X and Y.",
              explanation: "X: 1 + 6 = 7. Y: 3 + 2 = 5. Choose Y for its lower f. Choosing only the lowest g would send the search to X instead.",
              scenario: transfer, trace: transferTrace, beforeStepIndex: transferIndex - 1,
              revealStepIndex: transferIndex, options: [node("X"), node("Y")], correctOptionID: "Y"),
      ])
  }

  private static func index(in trace: SearchTrace, matching predicate: (SearchEvent) -> Bool) throws -> Int {
    guard let index = trace.steps.firstIndex(where: { predicate($0.event) }), index > 0 else {
      throw LessonContentError.missingTeachingEvent
    }
    return index
  }

  private static func node(_ id: String) -> PublicLessonOption {
    .init(id: id, title: "Node \(id)", nodeID: NodeID(rawValue: id))
  }

  private static func number(_ value: Int) -> PublicLessonOption {
    .init(id: String(value), title: String(value), nodeID: nil)
  }

  private static func scenario(
    id: String, nodes: [(String, Int, Double, Double)], edges: [(String, String, Int)]
  ) -> GraphScenario {
    .init(
      id: ScenarioID(rawValue: id),
      nodes: nodes.map {
        .init(id: NodeID(rawValue: $0.0), label: $0.0, heuristic: $0.1,
              position: .init(x: $0.2, y: $0.3))
      },
      edges: edges.map {
        .init(from: NodeID(rawValue: $0.0), to: NodeID(rawValue: $0.1), cost: $0.2, bidirectional: false)
      }, source: "S", goal: "G")
  }
}
