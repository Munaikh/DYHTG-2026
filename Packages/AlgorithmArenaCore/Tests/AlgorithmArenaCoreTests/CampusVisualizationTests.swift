import AlgorithmArenaCore
import Testing

/// Regression cases for the Visualize tab's prepared campus experiments.
@Test(arguments: [false, true], AlgorithmKind.allCases)
func campusPlotTwistReroutesAroundClosedGardensPath(reverse: Bool, algorithm: AlgorithmKind) throws {
  let course = try GilmorehillCourse.candidate()
  let source = try #require(course.nodes.first { $0.id == (reverse ? "07-library" : "01-jms") })
  let goal = try #require(course.nodes.first { $0.id == (reverse ? "01-jms" : "07-library") })
  let openNetwork = CampusPathNetwork(course: course)
  let original = try CampusRouter(network: openNetwork, expected: course.reference)
    .graph(from: source.coordinate, to: goal.coordinate).search(algorithm: algorithm)
  let originalRoute = try #require(original.route)
  #expect(originalRoute.nodeIDs.contains("junction:03-lilybank-house"))

  let closedNetwork = CampusPathNetwork(
    reference: openNetwork.reference, readiness: openNetwork.readiness,
    paths: openNetwork.paths.filter { $0.id != "gardens-house" })
  let reroute = try CampusRouter(network: closedNetwork, expected: course.reference)
    .graph(from: source.coordinate, to: goal.coordinate).search(algorithm: algorithm)
  let changedRoute = try #require(reroute.route)
  #expect(changedRoute.distanceMetres > originalRoute.distanceMetres)
  #expect(changedRoute.nodeIDs.contains("junction:04-hetherington"))
  #expect(!changedRoute.edgeIDs.contains { $0.rawValue.contains("gardens-house") })
  #expect(changedRoute.polyline.first == source.coordinate)
  #expect(changedRoute.polyline.last == goal.coordinate)
  #expect(openNetwork.paths.contains { $0.id == "gardens-house" })
  #expect(original.route == originalRoute)  // The original route remains a valid ghost overlay.
}

@Test(arguments: [false, true], AlgorithmKind.allCases)
func isolatedLibraryEndsWithEmptyFrontierWithoutInventingAPath(reverse: Bool, algorithm: AlgorithmKind) throws {
  let course = try GilmorehillCourse.candidate()
  let source = try #require(course.nodes.first { $0.id == (reverse ? "07-library" : "01-jms") })
  let goal = try #require(course.nodes.first { $0.id == (reverse ? "01-jms" : "07-library") })
  let openNetwork = CampusPathNetwork(course: course)
  let isolatedNetwork = CampusPathNetwork(
    reference: openNetwork.reference, readiness: openNetwork.readiness,
    paths: openNetwork.paths.filter { $0.id != "rejoin-fraser" })
  let graph = try CampusRouter(network: isolatedNetwork, expected: course.reference)
    .graph(from: source.coordinate, to: goal.coordinate)
  let result = try graph.search(algorithm: algorithm)
  #expect(result.route == nil)
  #expect(result.trace.outcome == .unreachable)
  #expect(result.trace.steps.last?.event == .unreachable)
  #expect(result.trace.steps.last?.state.frontier.isEmpty == true)
  #expect(result.trace.steps.last?.state.settled.contains(graph.scenario.goal) == false)
}

@Test(arguments: [false, true])
func campusVisualizationComparisonsUseEqualOptimalMetreCosts(reverse: Bool) throws {
  let course = try GilmorehillCourse.candidate()
  let source = try #require(course.nodes.first { $0.id == (reverse ? "07-library" : "01-jms") })
  let goal = try #require(course.nodes.first { $0.id == (reverse ? "01-jms" : "07-library") })
  let network = CampusPathNetwork(course: course)
  for closedID: EdgeID? in [nil, "gardens-house", "rejoin-fraser"] {
    let changed = CampusPathNetwork(
      reference: network.reference, readiness: network.readiness,
      paths: network.paths.filter { $0.id != closedID })
    let graph = try CampusRouter(network: changed, expected: course.reference)
      .graph(from: source.coordinate, to: goal.coordinate)
    try SearchEngine.validateHeuristics(in: graph.scenario)
    let dijkstra = try graph.search(algorithm: .dijkstra)
    let aStar = try graph.search(algorithm: .aStar)
    #expect(dijkstra.route?.distanceMetres == aStar.route?.distanceMetres)
    #expect((dijkstra.route == nil) == (aStar.route == nil))
    for trace in [dijkstra.trace, aStar.trace] {
      let expansions = trace.steps.filter { if case .expand = $0.event { true } else { false } }
      #expect(expansions.count == trace.steps.last?.state.settled.count)
    }
  }
}
