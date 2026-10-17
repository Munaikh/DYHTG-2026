import AlgorithmArenaCore
import Foundation
import Testing

private let networkReference = CourseReference(id: "test-campus", version: "1")
private let west = Coordinate(latitude: 55.874, longitude: -4.294)
private let centre = Coordinate(latitude: 55.874, longitude: -4.292)
private let east = Coordinate(latitude: 55.874, longitude: -4.290)
private let north = Coordinate(latitude: 55.875, longitude: -4.292)

private func network(_ paths: [PedestrianPath]? = nil) -> CampusPathNetwork {
  .init(
    reference: networkReference, readiness: .synthetic,
    paths: paths ?? [
      .init(
        id: "west", fromJunction: "W", toJunction: "C", bidirectional: true,
        polyline: [west, .init(latitude: 55.874, longitude: -4.293), centre]),
      .init(
        id: "east", fromJunction: "C", toJunction: "E", bidirectional: true,
        polyline: [centre, east]),
      .init(
        id: "north", fromJunction: "C", toJunction: "N", bidirectional: true,
        polyline: [centre, north]),
    ])
}

@Test(arguments: AlgorithmKind.allCases)
func arbitraryCampusSelectionsCreateDynamicNodesAndGeometry(algorithm: AlgorithmKind) throws {
  let router = try CampusRouter(network: network(), expected: networkReference)
  let start = Coordinate(latitude: 55.874, longitude: -4.2935)
  let goal = Coordinate(latitude: 55.8746, longitude: -4.292)
  let graph = try router.graph(from: start, to: goal)
  #expect(graph.source.nodeID == "selection:source")
  #expect(graph.goal.nodeID == "selection:goal")
  #expect(graph.source.coordinate == start)
  #expect(graph.goal.coordinate == goal)
  #expect(graph.scenario.nodes.count == 6)  // Four junctions plus this request's two nodes.
  let result = try graph.search(algorithm: algorithm)
  let route = try #require(result.route)
  #expect(route.nodeIDs == ["selection:source", "junction:C", "selection:goal"])
  #expect(route.polyline == [start, .init(latitude: 55.874, longitude: -4.293), centre, goal])
  #expect(route.polyline.first == start && route.polyline.last == goal)
  #expect(route.course == networkReference)
  let changed = try router.graph(from: .init(latitude: 55.874, longitude: -4.2938), to: east)
  #expect(graph.scenario.id != changed.scenario.id)
  #expect(graph.scenario != changed.scenario)
  #expect(changed.goal.nodeID == "junction:E")
  let reordered = try CampusRouter(
    network: network(Array(network().paths.reversed())), expected: networkReference)
  #expect(try reordered.graph(from: start, to: goal) == graph)
}

@Test(arguments: [false, true], AlgorithmKind.allCases)
func selectionsOnSamePathSplitOnlyTheRequiredSection(reverse: Bool, algorithm: AlgorithmKind) throws
{
  let router = try CampusRouter(network: network(), expected: networkReference)
  let a = Coordinate(latitude: 55.874, longitude: -4.2938)
  let b = Coordinate(latitude: 55.874, longitude: -4.2922)
  let graph = try router.graph(from: reverse ? b : a, to: reverse ? a : b)
  let result = try graph.search(algorithm: algorithm)
  let route = try #require(result.route)
  #expect(route.nodeIDs == ["selection:source", "selection:goal"])
  #expect(route.edgeIDs.count == 1)
  #expect(
    route.polyline == [
      reverse ? b : a, .init(latitude: 55.874, longitude: -4.293), reverse ? a : b,
    ])
  #expect(route.distanceMetres == Int(ceil(try CourseGeometry.length(of: route.polyline))))
}

@Test(arguments: [
  west, centre, Coordinate(latitude: 55.874, longitude: -4.293),
  Coordinate(latitude: 55.874, longitude: -4.2935),
])
func identicalSelectionsHaveAZeroCostRoute(point: Coordinate) throws {
  let graph = try CampusRouter(network: network(), expected: networkReference).graph(
    from: point, to: point)
  #expect(graph.scenario.source == graph.scenario.goal)
  let result = try graph.search(algorithm: .aStar)
  #expect(result.trace.outcome == .route(nodeIDs: [graph.source.nodeID], cost: 0))
  #expect(result.route?.polyline == [point])
  #expect(result.route?.edgeIDs.isEmpty == true)
}

@Test func oneWayPathsDoNotBecomeBidirectionalWhenSplit() throws {
  let oneWay = network([
    .init(
      id: "one-way", fromJunction: "W", toJunction: "E", bidirectional: false,
      polyline: [west, centre, east])
  ])
  let router = try CampusRouter(network: oneWay, expected: networkReference)
  let a = Coordinate(latitude: 55.874, longitude: -4.2935)
  let b = Coordinate(latitude: 55.874, longitude: -4.2905)
  #expect(try router.graph(from: a, to: b).search(algorithm: .aStar).route != nil)
  let backward = try router.graph(from: b, to: a).search(algorithm: .aStar)
  #expect(backward.trace.outcome == .unreachable)
  #expect(backward.route == nil)
}

@Test func crossingPolylinesDoNotInventAJunction() throws {
  let crossing = network([
    .init(
      id: "horizontal", fromJunction: "W", toJunction: "E", bidirectional: true,
      polyline: [west, centre, east]),
    .init(
      id: "vertical", fromJunction: "S", toJunction: "N", bidirectional: true,
      polyline: [.init(latitude: 55.873, longitude: -4.292), centre, north]),
  ])
  let graph = try CampusRouter(network: crossing, expected: networkReference).graph(
    from: west, to: north)
  #expect(try graph.search(algorithm: .dijkstra).trace.outcome == .unreachable)
  #expect(!graph.scenario.nodes.contains { $0.id == "junction:C" })
}

@Test func snappingHasExplicitDistanceAndBoundaryFailures() throws {
  let router = try CampusRouter(network: network(), expected: networkReference)
  let point = Coordinate(latitude: 55.87405, longitude: -4.2935)
  let graph = try router.graph(from: point, to: east)
  #expect(graph.source.coordinate != point)
  #expect(graph.source.distanceToPathMetres > 5 && graph.source.distanceToPathMetres < 6)
  let boundary = graph.source.distanceToPathMetres
  #expect(try router.graph(from: point, to: east, maximumSnapDistanceMetres: boundary) == graph)
  #expect(throws: CampusRoutingError.self) {
    try router.graph(from: point, to: east, maximumSnapDistanceMetres: boundary.nextDown)
  }
  #expect(throws: CampusRoutingError.invalidSnapLimit) {
    try router.graph(from: west, to: east, maximumSnapDistanceMetres: .infinity)
  }
  #expect(throws: CampusRoutingError.invalidSnapLimit) {
    try router.graph(from: west, to: east, maximumSnapDistanceMetres: -1)
  }
  #expect(throws: CourseError.invalidCoordinate) {
    try router.graph(from: .init(latitude: .nan, longitude: 0), to: east)
  }
  #expect(throws: CourseError.invalidCoordinate) {
    try router.graph(from: west, to: .init(latitude: 91, longitude: 0))
  }
  let route = try #require(graph.search(algorithm: .dijkstra).route)
  #expect(route.polyline.first == graph.source.coordinate)  // Never invent an off-path connector.
  #expect(throws: CourseError.surveyRequired) { try router.requireOutdoorReadiness() }
}

@Test func invalidNetworksAndVersionsFailClearly() throws {
  #expect(
    throws: CourseError.incompatibleCourse(
      expected: .init(id: "test-campus", version: "2"), actual: networkReference)
  ) {
    try CampusRouter(network: network(), expected: .init(id: "test-campus", version: "2"))
  }
  #expect(throws: CampusRoutingError.emptyNetwork) {
    try CampusRouter(network: network([]), expected: networkReference)
  }
  #expect(throws: CampusRoutingError.duplicatePath("east")) {
    try CampusRouter(
      network: network(network().paths + [network().paths[1]]), expected: networkReference)
  }
  #expect(throws: CampusRoutingError.inconsistentJunction("C")) {
    try CampusRouter(
      network: network(
        network().paths + [
          .init(
            id: "bad", fromJunction: "C", toJunction: "X", bidirectional: true,
            polyline: [east, north])
        ]), expected: networkReference)
  }
  #expect(throws: CampusRoutingError.invalidPath("bad")) {
    try CampusRouter(
      network: network([
        .init(
          id: "bad", fromJunction: "W", toJunction: "E", bidirectional: true,
          polyline: [west, west])
      ]), expected: networkReference)
  }
}

@Test func campusSelectionsAcrossTheNetworkHaveEqualOptimalCosts() throws {
  let campus = try GilmorehillCourse.candidate()
  let router = try CampusRouter(network: .init(course: campus), expected: campus.reference)
  let selections = campus.edges.flatMap { edge in
    zip(edge.polyline, edge.polyline.dropFirst()).map { a, b in
      Coordinate(
        latitude: (a.latitude + b.latitude) / 2, longitude: (a.longitude + b.longitude) / 2)
    }
  }
  for source in selections {
    for goal in selections {
      let graph = try router.graph(from: source, to: goal)
      let dijkstra = try graph.search(algorithm: .dijkstra)
      let aStar = try graph.search(algorithm: .aStar)
      #expect(dijkstra.route?.distanceMetres == aStar.route?.distanceMetres)
      #expect(dijkstra.route != nil && aStar.route != nil)
      #expect(dijkstra.route?.polyline.first == graph.source.coordinate)
      #expect(aStar.route?.polyline.last == graph.goal.coordinate)
    }
  }
}
