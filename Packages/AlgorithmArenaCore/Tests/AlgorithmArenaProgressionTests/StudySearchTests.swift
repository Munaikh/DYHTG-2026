import AlgorithmArenaCore
import AlgorithmArenaProgression
import Foundation
import Testing

@Test(arguments: StudyAlgorithm.allCases)
func indoorTracesAreDeterministicAndDriveAnswers(_ algorithm: StudyAlgorithm) throws {
  for mode in [ActivityMode.lesson, .practice] {
    let activities = try StudyCatalog.activities(for: algorithm, mode: mode)
    #expect(activities.count == 3)
    for a in activities {
      #expect(a.choices.count >= 2)
      #expect(a.choices.contains(a.correct))
      #expect(a.trace.steps[a.presentedStepIndex + 1].event == .expand(nodeID: a.correct))
      let graph = a.trace.scenario
      let reordered = GraphScenario(
        id: graph.id, nodes: graph.nodes.reversed(), edges: graph.edges.reversed(),
        source: graph.source, goal: graph.goal)
      let repeated = try StudySearch.run(reordered, algorithm: algorithm)
      #expect(repeated.steps == a.trace.steps)
      #expect(repeated.outcome == a.trace.outcome)
      #expect(a.trace.steps.enumerated().allSatisfy { $0.offset == $0.element.index })
      for step in a.trace.steps {
        #expect(Set(step.state.frontier).isDisjoint(with: step.state.settled))
      }
    }
  }
}
@Test func bfsUsesEdgesAndDFSExploresOneBranch() throws {
  let graph = try StudyCatalog.scenario(unitCosts: true)
  let bfs = try StudySearch.run(graph, algorithm: .bfs)
  let dfs = try StudySearch.run(graph, algorithm: .dfs)
  func order(_ t: StudyTrace) -> [NodeID] {
    t.steps.compactMap {
      if case .expand(let id) = $0.event { return id }
      return nil
    }
  }
  #expect(order(bfs) == ["A", "B", "C", "D", "E", "F"])
  #expect(order(dfs) == ["A", "B", "C", "D", "E", "F"])
  #expect(bfs.outcome == .route(nodeIDs: ["A", "B", "D", "F"], cost: 3))
  #expect(dfs.outcome == .route(nodeIDs: ["A", "B", "C", "D", "E", "F"], cost: 5))
}
@Test func greedyDoesNotPretendToBeOptimal() throws {
  let graph = try StudyCatalog.scenario()
  #expect(
    try StudySearch.run(graph, algorithm: .dijkstra).outcome
      == .route(nodeIDs: ["A", "C", "B", "D", "E", "F"], cost: 13))
  #expect(
    try StudySearch.run(graph, algorithm: .aStar).outcome
      == .route(nodeIDs: ["A", "C", "B", "D", "E", "F"], cost: 13))
  #expect(
    try StudySearch.run(graph, algorithm: .greedy).outcome
      == .route(nodeIDs: ["A", "B", "D", "F"], cost: 15))
  #expect(AlgorithmKind.allCases.count == 2)
}
