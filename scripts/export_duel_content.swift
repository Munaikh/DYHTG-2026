// Compile with the Foundation-only AlgorithmArenaCore sources. Never link into the app.
import Foundation

@main enum ExportDuelContent {
  static func main() throws {
    let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let base = graph("duel-robot-before-v1", ["S", "A", "B", "C", "G"], [6, 4, 3, 3, 0],
      [(0.12,0.5),(0.36,0.22),(0.36,0.78),(0.66,0.4),(0.88,0.5)],
      [("S","A",2),("S","B",3),("A","C",1),("A","G",8),("B","C",3),("C","G",3)])
    let twist = GraphScenario(id: "duel-robot-closed-v1", nodes: base.nodes,
      edges: base.edges.filter { !($0.from == "A" && $0.to == "C") }, source: "S", goal: "G")
    let transfer = graph("duel-rescue-transfer-v1", ["S", "D", "E", "F", "G"], [6, 5, 3, 2, 0],
      [(0.12,0.5),(0.4,0.2),(0.36,0.8),(0.67,0.65),(0.88,0.35)],
      [("S","D",2),("S","E",3),("D","G",6),("E","F",1),("F","G",2),("D","F",4)])
    for algorithm in AlgorithmKind.allCases {
      let documents = try [
        document(base, algorithm, expansions: 1, title: "Power up", prompt: "The delivery robot is leaving S. Which node is explored next?", choices: ["B","A"], twist: nil, previous: nil),
        document(twist, algorithm, expansions: 2, title: "Bridge closed!", prompt: "A → C is closed. A fresh search has explored S and A. Which node is next?", choices: ["G","B"], twist: "The bridge from A to C has closed. Replan from the start.", previous: base),
        document(transfer, algorithm, expansions: 1, title: "New world, same rule", prompt: "A rescue drone faces an unfamiliar network. Which node should it explore next?", choices: ["E","D"], twist: nil, previous: nil)
      ]
      let url = root.appendingPathComponent("\(algorithm.rawValue).json")
      try ContractJSON.encoder().encode(documents).write(to: url)
      print("Exported \(algorithm.rawValue): \(documents.count) verified duel rounds")
    }
  }
  struct Document: Codable {
    let round: DuelRound
    let correctNodeID: NodeID
    let explanation: String
    let trace: SearchTrace
  }
  static func document(_ scenario: GraphScenario, _ algorithm: AlgorithmKind, expansions: Int,
    title: String, prompt: String, choices: [NodeID], twist: String?, previous: GraphScenario?) throws -> Document {
    let trace = try SearchEngine.search(scenario, algorithm: algorithm)
    let expansionsList = trace.steps.filter { if case .expand = $0.event { return true }; return false }
    let next = expansionsList[expansions]
    guard case .expand(let correct) = next.event else { fatalError() }
    let state = trace.steps[next.index - 1].state
    // The public candidate list must not reveal priority order by position.
    let presented = SearchState(frontier: state.frontier.sorted(), settled: state.settled, costs: state.costs)
    let cost = state.costs.first { $0.nodeID == correct }!
    let rule = algorithm == .dijkstra ? "Dijkstra chooses the smallest tentative distance g." : "A* chooses the smallest f = g + h. Ties use node ID order."
    let calculation = algorithm == .dijkstra ? "\(correct.rawValue) has g = \(cost.g!)." : "\(correct.rawValue) has f = \(cost.g!) + \(cost.h) = \(cost.g! + cost.h)."
    return Document(round: DuelRound(title: title, prompt: prompt, twist: twist,
      scenario: scenario, presentedState: presented, choices: choices, previousScenario: previous),
      correctNodeID: correct, explanation: "\(rule) \(calculation)", trace: trace)
  }
  static func graph(_ id: ScenarioID, _ ids: [NodeID], _ heuristics: [Int],
    _ positions: [(Double,Double)], _ edges: [(NodeID,NodeID,Int)]) -> GraphScenario {
    GraphScenario(id: id, nodes: ids.indices.map { i in
      ScenarioNode(id: ids[i], label: ids[i].rawValue, heuristic: heuristics[i],
        position: ScenarioPosition(x: positions[i].0, y: positions[i].1))
    }, edges: edges.map { ScenarioEdge(from: $0.0, to: $0.1, cost: $0.2, bidirectional: false) },
      source: "S", goal: "G")
  }
}
