import AlgorithmArenaCore
import Foundation
import Testing

private let routedReference = CourseReference(id: "walking-test", version: "1")
private func routedNode(_ id: NodeID, _ x: Double, _ y: Double = 0) -> CourseNode {
  .init(id: id, name: id.rawValue,
    coordinate: .init(latitude: 55.872 + y, longitude: -4.291 + x), stoppingNote: "test")
}
private func routedPath(_ id: EdgeID, _ from: CourseNode, _ to: CourseNode, via: [Coordinate] = []) -> PedestrianPath {
  .init(id: id, fromJunction: from.id, toJunction: to.id, bidirectional: true,
    polyline: [from.coordinate] + via + [to.coordinate])
}

@Test func routedWalkingGeometryDeterminesWeightsAndOptimalSearch() throws {
  let a = routedNode("A", 0), b = routedNode("B", 0.001), c = routedNode("C", 0.002)
  let detour = Coordinate(latitude: 55.874, longitude: -4.290)
  let paths = [routedPath("ab", a, b), routedPath("bc", b, c), routedPath("ac", a, c, via: [detour])]
  let result = try RoutedCampusGraph(reference: routedReference, nodes: [c, a, b], paths: paths, source: "A", goal: "C")
  for edge in result.graph.edges {
    #expect(edge.polyline == paths.first { $0.id == edge.id }?.polyline)
    #expect(edge.costMetres == Int(ceil(try CourseGeometry.length(of: edge.polyline))))
  }
  for algorithm in AlgorithmKind.allCases {
    let route = try #require(result.graph.search(algorithm: algorithm).route)
    #expect(route.nodeIDs == ["A", "B", "C"])
    #expect(route.edgeIDs == ["ab", "bc"])
  }
  try SearchEngine.validateHeuristics(in: result.graph.scenario)
  #expect(result.maximumEndpointGapMetres == 0)
}

@Test func snappedWalkingGeometryKeepsHeuristicAdmissibleWithoutInventedConnectors() throws {
  let a = routedNode("A", 0), b = routedNode("B", 0.001), c = routedNode("C", 0.002)
  let shiftedA = routedNode("A", 0.0003), shiftedB = routedNode("B", 0.0007)
  let path = routedPath("ab", shiftedA, shiftedB)
  let result = try RoutedCampusGraph(reference: routedReference, nodes: [a, b, c],
    paths: [path, routedPath("bc", b, c)], source: "A", goal: "C")
  #expect(result.heuristicScale < 0.5)
  #expect(result.maximumEndpointGapMetres > 10)
  #expect(result.graph.edges.first { $0.id == "ab" }?.polyline == path.polyline)
  try SearchEngine.validateHeuristics(in: result.graph.scenario)
  #expect(try result.graph.search(algorithm: .dijkstra).route?.distanceMetres
    == result.graph.search(algorithm: .aStar).route?.distanceMetres)
}

@Test func routedCampusSamePointIsAZeroCostRoute() throws {
  let a = routedNode("A", 0), b = routedNode("B", 0.001)
  let result = try RoutedCampusGraph(reference: routedReference, nodes: [a, b],
    paths: [routedPath("ab", a, b)], source: "A", goal: "A")
  for algorithm in AlgorithmKind.allCases {
    #expect(try result.graph.search(algorithm: algorithm).trace.outcome == .route(nodeIDs: ["A"], cost: 0))
  }
}

@Test func routedCampusMissingConnectionsRemainUnreachable() throws {
  let a = routedNode("A", 0), b = routedNode("B", 0.001), c = routedNode("C", 0.002)
  let result = try RoutedCampusGraph(reference: routedReference, nodes: [a, b, c],
    paths: [routedPath("ab", a, b)], source: "A", goal: "C")
  for algorithm in AlgorithmKind.allCases {
    #expect(try result.graph.search(algorithm: algorithm).trace.outcome == .unreachable)
  }
  #expect(result.graph.edges.count == 1)
}

@Test func routedCampusRejectsInvalidProviderGeometryAndDuplicateNodes() throws {
  let a = routedNode("A", 0), b = routedNode("B", 0.001)
  #expect(throws: SearchError.duplicateNode("A")) {
    try RoutedCampusGraph(reference: routedReference, nodes: [a, a], paths: [], source: "A", goal: "A")
  }
  #expect(throws: CourseError.invalidPolyline("bad")) {
    try RoutedCampusGraph(reference: routedReference, nodes: [a, b],
      paths: [.init(id: "bad", fromJunction: "A", toJunction: "B", bidirectional: true, polyline: [a.coordinate])],
      source: "A", goal: "B")
  }
}

@Test func routedCampusEndpointSelectionReversesWithoutChangingOptimalCost() throws {
  let a = routedNode("A", 0), b = routedNode("B", 0.001), c = routedNode("C", 0.002)
  let paths = [routedPath("ab", a, b), routedPath("bc", b, c)]
  let forward = try RoutedCampusGraph(reference: routedReference, nodes: [a, b, c], paths: paths, source: "A", goal: "C")
  let reverse = try RoutedCampusGraph(reference: routedReference, nodes: [a, b, c], paths: paths, source: "C", goal: "A")
  #expect(try forward.graph.search(algorithm: .aStar).route?.distanceMetres
    == reverse.graph.search(algorithm: .aStar).route?.distanceMetres)
}
