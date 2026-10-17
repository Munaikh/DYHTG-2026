import AlgorithmArenaCore
import Foundation
import Testing

private func walkingPoint(_ x: Double, _ y: Double = 0) -> Coordinate {
  .init(latitude: 55.873 + y / 111_195,
    longitude: -4.29 + x / (111_195 * cos(55.873 * .pi / 180)))
}
private func walkingPath(_ id: String, _ points: [Coordinate], bidirectional: Bool = true) -> PedestrianPath {
  .init(id: EdgeID(rawValue: id), fromJunction: NodeID(rawValue: id + "-building-a"),
    toJunction: NodeID(rawValue: id + "-building-b"), bidirectional: bidirectional, polyline: points)
}
private func walkingStop(_ id: NodeID, _ coordinate: Coordinate) -> CourseNode {
  .init(id: id, name: "Selected \(id.rawValue)", coordinate: coordinate, stoppingNote: "MapKit walking entrance")
}
private func junctionGraph(_ network: WalkingJunctionNetwork, source: NodeID = "S", goal: NodeID = "G") throws -> RoutedCampusGraph {
  try .init(reference: .init(id: "junction-test", version: "1"), nodes: network.nodes,
    paths: network.paths, source: source, goal: goal)
}

@Test func walkingBendsRemainInPolylineInsteadOfBecomingNodes() throws {
  let geometry = [walkingPoint(0), walkingPoint(20), walkingPoint(20, 20), walkingPoint(40, 20)]
  let source = walkingStop("S", geometry.first!), goal = walkingStop("G", geometry.last!)
  let result = try WalkingJunctionNetwork(paths: [walkingPath("route", geometry)], source: source, goal: goal)
  #expect(result.nodes.count == 2)
  #expect(result.nodes.contains(source) && result.nodes.contains(goal))
  #expect(result.paths.count == 1)
  let polyline = result.paths[0].polyline
  #expect(polyline == geometry || polyline == geometry.reversed())
  let graph = try junctionGraph(result)
  #expect(try graph.graph.search(algorithm: .dijkstra).route?.distanceMetres == Int(ceil(CourseGeometry.length(of: geometry))))
}

@Test func walkingTJunctionSplitsAnUnmarkedTrunkAndPrunesBuildingLeaves() throws {
  let start = walkingPoint(0), junction = walkingPoint(20), goal = walkingPoint(20, 20)
  let result = try WalkingJunctionNetwork(paths: [
    walkingPath("trunk", [start, walkingPoint(40)]),
    walkingPath("branch", [junction, goal]),
    walkingPath("building-spur", [walkingPoint(40), walkingPoint(50, 10)]),
  ], source: walkingStop("S", start), goal: walkingStop("G", goal))
  #expect(result.nodes.count == 2)
  #expect(result.paths.count == 1)
  #expect(result.paths[0].polyline.contains(junction))
  #expect(!result.paths[0].polyline.contains(walkingPoint(40)))
  #expect(try junctionGraph(result).graph.search(algorithm: .aStar).route != nil)
}

@Test func walkingSharedTrunkIsDeduplicatedAcrossDifferentSamplingAndDirection() throws {
  let start = walkingPoint(0), a = walkingPoint(20), b = walkingPoint(40), goal = walkingPoint(60)
  let result = try WalkingJunctionNetwork(paths: [
    walkingPath("sparse", [start, goal]),
    walkingPath("dense-reversed", [goal, b, a, start]),
    walkingPath("building-spur", [a, walkingPoint(20, 30)]),
  ], source: walkingStop("S", start), goal: walkingStop("G", goal))
  #expect(result.nodes.count == 2)
  #expect(result.paths.count == 1)
  #expect(result.paths[0].polyline.count == 4)
  #expect(Set(result.paths[0].polyline.map { "\($0.latitude),\($0.longitude)" }).count == 4)
}

@Test func walkingGeometricCrossingWithoutReturnedVertexNeverConnects() throws {
  let west = walkingPoint(-20), east = walkingPoint(20), north = walkingPoint(0, 20), south = walkingPoint(0, -20)
  #expect(throws: WalkingJunctionError.disconnectedEndpoints) {
    try WalkingJunctionNetwork(paths: [walkingPath("over", [west, east]), walkingPath("under", [north, south])],
      source: walkingStop("S", west), goal: walkingStop("G", north))
  }
}

@Test func walkingExplicitCrossingVertexCanConnectReturnedRoutes() throws {
  let west = walkingPoint(-20), crossing = walkingPoint(0), east = walkingPoint(20), north = walkingPoint(0, 20), south = walkingPoint(0, -20)
  let result = try WalkingJunctionNetwork(paths: [
    walkingPath("with-vertex", [west, crossing, east]), walkingPath("trunk", [north, south]),
  ], source: walkingStop("S", west), goal: walkingStop("G", north))
  #expect(result.paths.count == 1)
  #expect(result.paths[0].polyline.contains(crossing))
  #expect(try junctionGraph(result).graph.search(algorithm: .dijkstra).route != nil)
}

@Test func walkingSelectedEntranceMidSegmentIsPreservedAndOuterTailPruned() throws {
  let source = walkingStop("S", walkingPoint(15)), goal = walkingStop("G", walkingPoint(60))
  let result = try WalkingJunctionNetwork(paths: [walkingPath("walk", [walkingPoint(0), walkingPoint(60)])], source: source, goal: goal)
  #expect(result.nodes == [goal, source])
  #expect(result.paths.count == 1)
  #expect(result.paths[0].polyline.count == 2)
  #expect(!result.paths[0].polyline.contains(walkingPoint(0)))
  #expect(try junctionGraph(result).graph.search(algorithm: .aStar).route?.distanceMetres == 46)
}

@Test func walkingParallelCorridorsAndTheirJunctionsArePreserved() throws {
  let start = walkingPoint(-20), a = walkingPoint(0), b = walkingPoint(60), goal = walkingPoint(80)
  let input = [
    walkingPath("direct", [start, a, b, goal]),
    walkingPath("north", [a, walkingPoint(20, 20), walkingPoint(40, 20), b]),
  ]
  let network = try WalkingJunctionNetwork(paths: input, source: walkingStop("S", start), goal: walkingStop("G", goal))
  #expect(network.nodes.count == 4)
  #expect(network.paths.count == 4)
  let junctions = network.nodes.filter { $0.id != "S" && $0.id != "G" }
  #expect(junctions.allSatisfy { $0.name.hasPrefix("Walking junction") })
  let parallel = network.paths.filter { path in
    junctions.contains { $0.id == path.fromJunction } && junctions.contains { $0.id == path.toJunction }
  }
  #expect(parallel.count == 2)
  #expect(parallel[0].id != parallel[1].id)
  let graph = try junctionGraph(network)
  #expect(try graph.graph.search(algorithm: .dijkstra).route?.distanceMetres
    == graph.graph.search(algorithm: .aStar).route?.distanceMetres)
}

@Test func walkingTopologyIDsAreStableWhenInputOrderAndDirectionReverse() throws {
  let a = walkingPoint(0), b = walkingPoint(60)
  let input = [walkingPath("one", [a, walkingPoint(20), b]), walkingPath("two", [a, walkingPoint(30, 30), b])]
  let source = walkingStop("S", a), goal = walkingStop("G", b)
  let original = try WalkingJunctionNetwork(paths: input, source: source, goal: goal)
  let reversed = try WalkingJunctionNetwork(paths: input.reversed().map { path in
    .init(id: path.id, fromJunction: path.toJunction, toJunction: path.fromJunction,
      bidirectional: path.bidirectional, polyline: path.polyline.reversed())
  }, source: source, goal: goal)
  #expect(original.nodes == reversed.nodes)
  #expect(original.paths == reversed.paths)
}

@Test func walkingLoopCompressionTerminatesAndKeepsTheRing() throws {
  let source = walkingStop("S", walkingPoint(0)), goal = walkingStop("G", walkingPoint(20, 20))
  let ring = [source.coordinate, walkingPoint(20), goal.coordinate, walkingPoint(0, 20), source.coordinate]
  let result = try WalkingJunctionNetwork(paths: [walkingPath("ring", ring)], source: source, goal: goal)
  #expect(result.nodes.count == 2)
  #expect(result.paths.count == 2)
  #expect(result.paths.allSatisfy { $0.polyline.count == 3 })
}

@Test func walkingSubMetreNoiseMergesButNearbyParallelPathsDoNot() throws {
  let source = walkingStop("S", walkingPoint(0)), goal = walkingStop("G", walkingPoint(40))
  let result = try WalkingJunctionNetwork(paths: [
    walkingPath("left", [source.coordinate, walkingPoint(20)]),
    walkingPath("right", [walkingPoint(20.4), goal.coordinate]),
  ], source: source, goal: goal)
  #expect(result.nodes.count == 2)
  #expect(result.paths.count == 1)
  #expect(throws: WalkingJunctionError.disconnectedEndpoints) {
    try WalkingJunctionNetwork(paths: [
      walkingPath("left", [walkingPoint(0), walkingPoint(40)]),
      walkingPath("parallel", [walkingPoint(0, 2), walkingPoint(40, 2)]),
    ], source: source, goal: walkingStop("G", walkingPoint(40, 2)))
  }
}

@Test func walkingEndpointsOutsideReturnedGeometryFailExplicitly() throws {
  #expect(throws: WalkingJunctionError.endpointNotOnPath(.source)) {
    try WalkingJunctionNetwork(paths: [walkingPath("route", [walkingPoint(0), walkingPoint(40)])],
      source: walkingStop("S", walkingPoint(0, 10)), goal: walkingStop("G", walkingPoint(40)))
  }
}

@Test func walkingDirectedSegmentsNeverInventReverseAccess() throws {
  let a = walkingPoint(0), b = walkingPoint(20), c = walkingPoint(40)
  let input = [walkingPath("one-way", [a, b, c], bidirectional: false)]
  let result = try WalkingJunctionNetwork(paths: input, source: walkingStop("S", a), goal: walkingStop("G", c))
  #expect(result.paths.count == 1)
  #expect(!result.paths[0].bidirectional)
  #expect(result.paths[0].fromJunction == "S")
  #expect(throws: WalkingJunctionError.disconnectedEndpoints) {
    try WalkingJunctionNetwork(paths: input, source: walkingStop("S", c), goal: walkingStop("G", a))
  }
}
