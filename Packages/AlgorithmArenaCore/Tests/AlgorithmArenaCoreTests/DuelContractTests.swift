import Foundation
import Testing
@testable import AlgorithmArenaCore

struct DuelContractTests {
  private struct Document: Decodable {
    let round: DuelRound
    let correctNodeID: NodeID
    let explanation: String
    let trace: SearchTrace
  }
  private var repository: URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
  }
  @Test func authoredDuelRoundsMatchCanonicalSearch() throws {
    for algorithm in AlgorithmKind.allCases {
      let url = repository.appendingPathComponent("content/duel/v1/server/\(algorithm.rawValue).json")
      let documents = try ContractJSON.decoder().decode([Document].self, from: Data(contentsOf: url))
      #expect(documents.count == 3)
      for document in documents {
        let trace = try SearchEngine.search(document.round.scenario, algorithm: algorithm)
        #expect(document.trace == trace)
        let settled = document.round.presentedState.settled
        let expansions = trace.steps.filter { if case .expand = $0.event { true } else { false } }
        let next = expansions[settled.count]
        guard case .expand(let id) = next.event else { Issue.record("Expected expansion"); return }
        #expect(id == document.correctNodeID)
        #expect(document.round.choices.contains(id))
        #expect(Set(document.round.choices).count == document.round.choices.count)
        #expect(document.round.presentedState.costs == trace.steps[next.index-1].state.costs)
        #expect(document.round.presentedState.frontier == trace.steps[next.index-1].state.frontier.sorted())
      }
      let twist = documents[1]
      let previous = try #require(twist.round.previousScenario)
      #expect(previous.edges.count == twist.round.scenario.edges.count+1)
      #expect(previous.edges.contains { $0.from == "A" && $0.to == "C" })
      #expect(!twist.round.scenario.edges.contains { $0.from == "A" && $0.to == "C" })
      #expect(try SearchEngine.search(previous, algorithm: algorithm).outcome != twist.trace.outcome)
      #expect(documents[2].correctNodeID == (algorithm == .dijkstra ? "D" : "E"))
    }
  }
  @Test func commandUsesFlatStableWireContract() throws {
    let command = DuelCommand(action: .submit, matchID: UUID(), revision: 7, answerNodeID: "A")
    let data = try ContractJSON.encoder().encode(command)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["action"] as? String == "submit")
    #expect(object["answerNodeID"] as? String == "A")
    #expect(object["revision"] as? Int == 7)
    #expect(object["nickname"] == nil)
    #expect(try ContractJSON.decoder().decode(DuelCommand.self, from: data) == command)
  }
  @Test func realPostgRESTCorpusDecodesWhenProvided() throws {
    guard let path = ProcessInfo.processInfo.environment["DUEL_WIRE_PATH"] else { return }
    struct Corpus: Decodable { let snapshots: [DuelSnapshot] }
    let corpus = try ContractJSON.decoder().decode(Corpus.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    #expect(corpus.snapshots.count > 20)
    #expect(Set(corpus.snapshots.map(\.phase)) == Set([.lobby,.answering,.reveal,.finished,.incomplete]))
    for snapshot in corpus.snapshots {
      #expect(snapshot.roundCount == 3)
      #expect(snapshot.players.contains { $0.id == snapshot.viewerID })
      if snapshot.phase == .answering { #expect(snapshot.reveal == nil) }
      if snapshot.phase == .reveal || snapshot.phase == .finished {
        #expect(snapshot.reveal?.answers.count == 2)
        #expect(snapshot.reveal?.trace.algorithm == snapshot.algorithm)
      }
    }
  }
}
