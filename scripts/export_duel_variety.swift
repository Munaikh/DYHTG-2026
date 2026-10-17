// Authoring only: compile with Core sources. Never link answer documents into the app.
import Foundation

@main enum ExportDuelVariety {
  struct Document: Codable {
    let id: String
    let algorithm: StudyAlgorithm
    let slot: Int
    let round: DuelRound
    let correctNodeID: NodeID
    let explanation: String
    let trace: DuelTrace
  }
  struct Random {
    var state: UInt64
    mutating func next(_ limit: Int) -> Int {
      state = state &* 6364136223846793005 &+ 1442695040888963407
      return Int((state >> 32) % UInt64(limit))
    }
    mutating func shuffled<T>(_ values: [T]) -> [T] {
      var result = values
      if result.count > 1 {
        for i in stride(from: result.count-1, through: 1, by: -1) { result.swapAt(i, next(i+1)) }
      }
      return result
    }
  }
  static func main() throws {
    let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for algorithm in StudyAlgorithm.allCases {
      var documents: [Document] = []
      for variant in 0..<8 {
        var random = Random(state: UInt64(713 + variant*191 + StudyAlgorithm.allCases.firstIndex(of: algorithm)!*100_003))
        let base = try graph(variant, algorithm: algorithm, random: &random)
        let changed = try twist(base, algorithm: algorithm, variant: variant)
        let transfer = try graph(variant+11, algorithm: algorithm, random: &random)
        documents.append(try question(base, algorithm, slot: 0, variant: variant, kind: .nextExpansion, random: &random))
        documents.append(try question(changed.0, algorithm, slot: 1, variant: variant, kind: .predecessor,
          previous: base, twist: changed.1, random: &random))
        let incoming = Set(transfer.edges.filter { $0.to == transfer.goal }.map(\.from))
        documents.append(try question(transfer, algorithm, slot: 2, variant: variant,
          kind: variant%2 == 1 && incoming.count > 1 ? .goalPredecessor : .routeHop, random: &random))
      }
      try ContractJSON.encoder().encode(documents).write(to: folder.appendingPathComponent("\(algorithm.rawValue).json"))
      print("\(algorithm.rawValue): \(documents.count) verified questions, 8 variants per round")
    }
  }
  static func graph(_ variant: Int, algorithm: StudyAlgorithm, random: inout Random) throws -> GraphScenario {
    let templates = [
      [(0,1),(0,2),(0,3),(1,4),(1,5),(2,4),(2,5),(3,5),(4,6),(5,6),(4,5)],
      [(0,2),(0,3),(2,1),(2,5),(3,4),(3,6),(1,4),(4,5),(5,7),(6,7),(6,5)],
      [(0,1),(0,4),(0,2),(1,3),(4,6),(2,5),(3,7),(5,7),(6,8),(7,8),(3,5),(5,6)],
      [(0,3),(0,1),(3,2),(3,5),(1,4),(2,4),(4,5),(4,6),(5,6),(2,1)]
    ]
    let template = templates[variant%4]
    let count = template.flatMap { [$0.0,$0.1] }.max()!+1
    let middle = (0..<(count-2)).map { NodeID(rawValue: String(UnicodeScalar(65+$0)!)) }
    let labels = random.shuffled(middle)
    let ids: [NodeID] = ["S"] + labels + ["Z"]
    let nodes = ids.indices.map { i in
      ScenarioNode(id: ids[i], label: ids[i].rawValue, heuristic: 0,
        position: i == 0 ? .init(x:0.08,y:0.5) : i == count-1 ? .init(x:0.92,y:0.5) :
          .init(x:i%2 == 1 ? 0.34 : 0.65,y:0.14+Double((i-1)/2)*0.24))
    }
    let unit = algorithm == .bfs || algorithm == .dfs
    let edges = template.map { ScenarioEdge(from:ids[$0.0],to:ids[$0.1],cost:unit ? 1 : 1+random.next(9),bidirectional:false) }
    return try estimated(GraphScenario(id:ScenarioID(rawValue:"duel-v2-\(algorithm.rawValue)-map-\(variant)"),nodes:nodes,edges:edges,source:"S",goal:"Z"))
  }
  static func estimated(_ graph: GraphScenario) throws -> GraphScenario {
    var distances: [NodeID:Int] = [:]
    for node in graph.nodes {
      let route = try SearchEngine.search(GraphScenario(id:graph.id,nodes:graph.nodes,edges:graph.edges,source:node.id,goal:graph.goal),algorithm:.dijkstra)
      guard case .route(_,let cost) = route.outcome else { throw AuthoringError.unreachable }
      distances[node.id] = cost
    }
    // Half of exact remaining distance is consistent and admissible on these integer edges.
    let nodes = graph.nodes.map { ScenarioNode(id:$0.id,label:$0.label,heuristic:distances[$0.id]!/2,position:$0.position) }
    let result = GraphScenario(id:graph.id,nodes:nodes,edges:graph.edges,source:graph.source,goal:graph.goal)
    try SearchEngine.validateHeuristics(in:result)
    return result
  }
  static func twist(_ base: GraphScenario, algorithm: StudyAlgorithm, variant: Int) throws -> (GraphScenario,String) {
    let original = try StudySearch.run(base,algorithm:algorithm)
    guard case .route(let route,_) = original.outcome else { throw AuthoringError.unreachable }
    for (a,b) in zip(route,route.dropFirst()) {
      let edges = base.edges.filter { !($0.from == a && $0.to == b) }
      let raw = GraphScenario(id:ScenarioID(rawValue:base.id.rawValue+"-twist"),nodes:base.nodes.map {
        ScenarioNode(id:$0.id,label:$0.label,heuristic:0,position:$0.position)
      },edges:edges,source:base.source,goal:base.goal)
      guard let graph = try? estimated(raw), let result = try? StudySearch.run(graph,algorithm:algorithm), result.outcome != original.outcome else { continue }
      let messages = ["The connection \(a.rawValue) → \(b.rawValue) is closed for maintenance.",
        "A fallen tree blocks \(a.rawValue) → \(b.rawValue). That edge is unavailable.",
        "The link \(a.rawValue) → \(b.rawValue) went offline. Rebuild the search.",
        "A one-way gate closed on \(a.rawValue) → \(b.rawValue). Find another way."]
      return (graph,messages[variant%messages.count]+" Restart from S; the displayed state is from the new search.")
    }
    throw AuthoringError.noTwist
  }
  static func question(_ graph: GraphScenario, _ algorithm: StudyAlgorithm, slot: Int, variant: Int,
    kind: DuelQuestionKind, previous: GraphScenario? = nil, twist: String? = nil, random: inout Random) throws -> Document {
    let trace = try StudySearch.run(graph,algorithm:algorithm)
    let id = "duel-v2.\(algorithm.rawValue).\(slot).\(variant)"
    let worlds = ["Campus courier", "Rescue relay", "Robot warehouse", "Forest trail", "Metro transfer", "Server network", "Museum delivery", "Island crossing"]
    var state = trace.steps[0].state
    var correct: NodeID
    var focus: NodeID?
    var choices: [NodeID]
    let prompt: String
    let explanation: String
    switch kind {
    case .nextExpansion:
      let decisions = trace.steps.indices.filter { i in
        guard i>0,trace.steps[i-1].state.frontier.count>=2 else { return false }
        if case .expand = trace.steps[i].event { return true }; return false
      }
      guard !decisions.isEmpty else { throw AuthoringError.noQuestion }
      let next = decisions[variant%decisions.count]
      guard case .expand(let node) = trace.steps[next].event else { throw AuthoringError.noQuestion }
      state = trace.steps[next-1].state;correct=node;choices=state.frontier
      let prompts = ["Which frontier node will \(algorithm.shortName) visit next?",
        "The search has reached this decision. Pick the next node using \(algorithm.shortName).",
        "Continue the exploration: which available node takes the next turn?",
        "Read the visited nodes and frontier. Where does \(algorithm.shortName) go now?"]
      prompt=prompts[variant%prompts.count]
      explanation="\(algorithm.rule) \(algorithm.tieRule) The next expansion is \(node.rawValue)."
    case .predecessor:
      let candidates = trace.steps.filter { $0.state.settled.count>=2 && $0.state.costs.contains { $0.predecessor != nil && $0.predecessor != graph.source } }
      guard !candidates.isEmpty else { throw AuthoringError.noQuestion }
      state=candidates[variant%candidates.count].state
      let nodes=state.costs.filter { $0.predecessor != nil && $0.predecessor != graph.source }
      let target=nodes[variant%nodes.count];correct=target.predecessor!;focus=target.nodeID
      choices=Array(random.shuffled(graph.nodes.map(\.id).filter { $0 != target.nodeID && $0 != correct }).prefix(3))+[correct]
      let prompts = ["After the change, which node is recorded as the predecessor of \(target.nodeID.rawValue)?",
        "Reconstruct the discovery of \(target.nodeID.rawValue): which node led to it in this new search?",
        "The world changed. Which node now supplies \(target.nodeID.rawValue)'s current parent link?",
        "Trace one step backwards from \(target.nodeID.rawValue) in the displayed search tree. Which node comes before it?"]
      prompt=prompts[variant%prompts.count]
      explanation="\(target.nodeID.rawValue) was reached from \(correct.rawValue) in the displayed state. Follow predecessor links backwards to reconstruct the route. \(algorithm.caveat)"
    case .routeHop, .goalPredecessor:
      guard case .route(let route,let cost)=trace.outcome,route.count>=2 else { throw AuthoringError.noQuestion }
      if kind == .routeHop {
        correct=route[1];focus=graph.source
        choices=Array(Set(graph.edges.filter { $0.from == graph.source }.map(\.to)))
        prompt="Run \(algorithm.shortName) from S to Z. Which node comes immediately after S on the route it finds?"
      } else {
        correct=route[route.count-2];focus=graph.goal
        choices=Array(Set(graph.edges.filter { $0.to == graph.goal }.map(\.from)))
        prompt="Finish \(algorithm.shortName)'s route from S to Z. Which node is immediately before Z?"
      }
      explanation="Following \(algorithm.shortName) gives \(route.map(\.rawValue).joined(separator:" → ")), with total edge cost \(cost). \(algorithm.caveat)"
    }
    guard choices.count>=2,Set(choices).count==choices.count,choices.contains(correct) else { throw AuthoringError.noQuestion }
    // A displayed set is not a pre-sorted answer key. Queue/stack order is derived from
    // the supplied visited sequence and the explicitly documented neighbour order.
    let shown = SearchState(frontier:state.frontier.sorted(),settled:state.settled,costs:state.costs)
    let round = DuelRound(title:worlds[variant%worlds.count]+" · "+kind.title,prompt:prompt,twist:twist,
      scenario:graph,presentedState:shown,choices:random.shuffled(choices.sorted()),previousScenario:previous,
      questionID:id,questionKind:kind,focusNodeID:focus)
    return Document(id:id,algorithm:algorithm,slot:slot,round:round,correctNodeID:correct,explanation:explanation,trace:DuelTrace(trace))
  }
  enum AuthoringError: Error { case unreachable, noQuestion, noTwist }
}
