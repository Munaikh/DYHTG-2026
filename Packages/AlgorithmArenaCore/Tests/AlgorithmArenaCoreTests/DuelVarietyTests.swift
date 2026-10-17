import Foundation
import Testing
@testable import AlgorithmArenaCore

struct DuelVarietyTests {
  struct Document: Decodable {
    let id: String
    let algorithm: StudyAlgorithm
    let slot: Int
    let round: DuelRound
    let correctNodeID: NodeID
    let explanation: String
    let trace: DuelTrace
  }
  private var root: URL {
    URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  }
  @Test(arguments: StudyAlgorithm.allCases)
  func everyQuestionUsesTheRealSharedEngine(_ algorithm: StudyAlgorithm) throws {
    let url=root.appendingPathComponent("content/duel/v2/server/\(algorithm.rawValue).json")
    let bank=try ContractJSON.decoder().decode([Document].self,from:Data(contentsOf:url))
    #expect(bank.count==24)
    #expect(Set(bank.map(\.id)).count==24)
    #expect(Set(bank.compactMap(\.round.questionKind)) == Set(DuelQuestionKind.allCases))
    for slot in 0..<3 { #expect(bank.filter { $0.slot==slot }.count==8) }
    var diagrams=Set<Data>()
    for document in bank {
      let round=document.round
      let computed=try StudySearch.run(round.scenario,algorithm:algorithm)
      #expect(DuelTrace(computed)==document.trace)
      #expect(round.questionID==document.id)
      #expect(document.algorithm==algorithm)
      #expect(round.choices.count>=2)
      #expect(Set(round.choices).count==round.choices.count)
      #expect(round.choices.contains(document.correctNodeID))
      #expect(!document.explanation.isEmpty)
      #expect(round.presentedState.frontier==round.presentedState.frontier.sorted())
      try SearchEngine.validateHeuristics(in:round.scenario)
      if algorithm == .bfs || algorithm == .dfs { #expect(round.scenario.edges.allSatisfy { $0.cost==1 }) }
      for node in round.scenario.nodes {
        let position=try #require(node.position)
        #expect((0...1).contains(position.x) && (0...1).contains(position.y))
      }
      switch try #require(round.questionKind) {
      case .nextExpansion:
        let next=try #require(computed.steps.indices.first { index in
          guard index>0 else { return false }
          if case .expand = computed.steps[index].event {
            return computed.steps[index-1].state.costs==round.presentedState.costs &&
              computed.steps[index-1].state.settled==round.presentedState.settled &&
              computed.steps[index-1].state.frontier.sorted()==round.presentedState.frontier
          }
          return false
        })
        #expect(computed.steps[next].event == .expand(nodeID:document.correctNodeID))
      case .predecessor:
        let focus=try #require(round.focusNodeID)
        #expect(round.presentedState.costs.first { $0.nodeID==focus }?.predecessor==document.correctNodeID)
        #expect(computed.steps.contains { $0.state.costs==round.presentedState.costs && $0.state.settled==round.presentedState.settled })
        let before=try #require(round.previousScenario)
        #expect(before.edges.count==round.scenario.edges.count+1)
        #expect(try StudySearch.run(before,algorithm:algorithm).outcome != computed.outcome)
      case .routeHop:
        guard case .route(let route,_) = computed.outcome else { Issue.record("Expected route");continue }
        #expect(route[1]==document.correctNodeID)
        #expect(round.presentedState.settled.isEmpty)
      case .goalPredecessor:
        guard case .route(let route,_) = computed.outcome else { Issue.record("Expected route");continue }
        #expect(route[route.count-2]==document.correctNodeID)
        #expect(round.presentedState.settled.isEmpty)
      }
      let encoded=try ContractJSON.encoder().encode(round)
      let publicText=String(decoding:encoded,as:UTF8.self)
      #expect(!publicText.contains("correctNodeID") && !publicText.contains("explanation") && !publicText.contains("trace"))
      // Remove identity metadata: verify actual diagram data changes, not just IDs/titles.
      let diagram=GraphScenario(id:"diagram",nodes:round.scenario.nodes,edges:round.scenario.edges,source:round.scenario.source,goal:round.scenario.goal)
      diagrams.insert(try ContractJSON.encoder().encode(diagram))
    }
    #expect(diagrams.count==24)
  }
  @Test(arguments: StudyAlgorithm.allCases)
  func fiveAlgorithmCommandRoundTrips(_ algorithm: StudyAlgorithm) throws {
    let command=DuelCommand(action:.create,nickname:"Rival",algorithm:algorithm)
    #expect(try ContractJSON.decoder().decode(DuelCommand.self,from:ContractJSON.encoder().encode(command))==command)
  }
}
