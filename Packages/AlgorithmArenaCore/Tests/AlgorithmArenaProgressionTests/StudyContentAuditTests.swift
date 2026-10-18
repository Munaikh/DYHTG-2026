import AlgorithmArenaCore
import AlgorithmArenaProgression
import Testing

@Test(arguments: StudyAlgorithm.allCases, [ActivityMode.lesson, .practice])
func studyAnswersAgreeWithIndependentRules(algorithm: StudyAlgorithm, mode: ActivityMode) throws {
  for activity in try StudyCatalog.activities(for: algorithm, mode: mode) {
    let graph = activity.trace.scenario
    try SearchEngine.validateHeuristics(in: graph)
    func neighbours(_ node: NodeID) -> [NodeID] {
      graph.edges.compactMap { edge in
        if edge.from == node { return edge.to }
        if edge.bidirectional && edge.to == node { return edge.from }
        return nil
      }.sorted()
    }
    let expansions = activity.trace.steps.compactMap { step -> NodeID? in
      if case .expand(let node) = step.event { return node }
      return nil
    }
    if algorithm == .dfs || algorithm == .bfs {
      var order: [NodeID] = []
      var seen: Set<NodeID> = []
      if algorithm == .dfs {
        // Recursive DFS oracle, independent of the engine's mutable pending stack.
        func visit(_ node: NodeID) {
          guard !seen.contains(node), !order.contains(graph.goal) else { return }
          seen.insert(node)
          order.append(node)
          for next in neighbours(node) { visit(next) }
        }
        visit(graph.source)
      } else {
        // Whole layers, preserving discovery order within each layer.
        var layer = [graph.source]
        seen.insert(graph.source)
        while !layer.isEmpty && !order.contains(graph.goal) {
          var nextLayer: [NodeID] = []
          for node in layer {
            order.append(node)
            if node == graph.goal { break }
            for next in neighbours(node) where seen.insert(next).inserted {
              nextLayer.append(next)
            }
          }
          layer = nextLayer
        }
      }
      #expect(expansions == order, "Traversal mismatch in \(activity.id)")
      #expect(activity.correct == order[activity.state.settled.count])
    } else {
      let frontier = activity.state.costs.filter { activity.state.frontier.contains($0.nodeID) }
      var ranked: [(node: NodeID, priority: Int)] = []
      for cost in frontier {
        let g = try #require(cost.g)
        let priority = algorithm == .greedy ? cost.h : g + (algorithm == .aStar ? cost.h : 0)
        ranked.append((node: cost.nodeID, priority: priority))
      }
      ranked.sort { lhs, rhs in
        lhs.priority == rhs.priority ? lhs.node < rhs.node : lhs.priority < rhs.priority
      }
      #expect(activity.correct == ranked.first?.node)
    }
    guard case .route(let route, let cost) = activity.trace.outcome else {
      Issue.record("Study graph must reach its goal: \(activity.id)")
      return
    }
    #expect(route.first == graph.source && route.last == graph.goal)
    var total = 0
    for (from, to) in zip(route, route.dropFirst()) {
      let edge = try #require(graph.edges.first {
        ($0.from == from && $0.to == to) || ($0.bidirectional && $0.to == from && $0.from == to)
      })
      total += edge.cost
    }
    #expect(total == cost)
  }
}
