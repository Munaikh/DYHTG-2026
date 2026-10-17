import AlgorithmArenaCore
import Testing

@Test(arguments: AlgorithmKind.allCases)
func publicLessonsHaveValidIndependentGraphsAndEngineBackedQuestions(algorithm: AlgorithmKind) throws {
  let lesson = try LessonCatalog.lesson(for: algorithm)
  #expect(lesson.questions.count == 3)
  #expect(lesson.scenario.id.rawValue.hasPrefix("public-lesson-"))
  #expect(lesson.questions.last?.scenario.id != lesson.scenario.id)
  #expect(lesson.trace == (try SearchEngine.search(lesson.scenario, algorithm: algorithm)))
  for question in lesson.questions {
    #expect(question.options.contains { $0.id == question.correctOptionID })
    #expect(Set(question.options.map(\.id)).count == question.options.count)
    #expect(question.revealStepIndex == question.beforeStepIndex + 1)
    #expect(question.trace == (try SearchEngine.search(question.scenario, algorithm: algorithm)))
    if let correctNode = question.options.first(where: { $0.id == question.correctOptionID })?.nodeID {
      #expect(question.before.state.frontier.first == correctNode)
      #expect(question.reveal.event == .expand(nodeID: correctNode))
    }
  }
}

@Test func dijkstraLessonTeachesARealCostImprovement() throws {
  let lesson = try LessonCatalog.lesson(for: .dijkstra)
  let question = lesson.questions[1]
  #expect(question.before.state.costs.first { $0.nodeID == "A" }?.g == 7)
  #expect(question.reveal.state.costs.first { $0.nodeID == "A" }?.g == 4)
  #expect(question.reveal.state.costs.first { $0.nodeID == "A" }?.predecessor == "B")
  #expect(question.correctOptionID == "4")
  #expect(lesson.trace.outcome == .route(nodeIDs: ["S", "B", "A", "C", "G"], cost: 8))
  let transfer = lesson.questions[2]
  #expect(transfer.before.state.frontier == ["X", "G"])
}

@Test func aStarLessonsDistinguishLowestGFromLowestF() throws {
  let lesson = try LessonCatalog.lesson(for: .aStar)
  for question in [lesson.questions[0], lesson.questions[2]] {
    let frontierCosts = question.before.state.costs.filter { question.before.state.frontier.contains($0.nodeID) }
    let lowestG = try #require(frontierCosts.min { ($0.g ?? .max) < ($1.g ?? .max) })
    #expect(lowestG.nodeID.rawValue != question.correctOptionID)
  }
  let priority = lesson.questions[1]
  let b = try #require(priority.before.state.costs.first { $0.nodeID == "B" })
  #expect(priority.correctOptionID == String(try #require(b.g) + b.h))
  #expect(lesson.questions[2].trace.outcome == .route(nodeIDs: ["S", "Y", "G"], cost: 6))
}
