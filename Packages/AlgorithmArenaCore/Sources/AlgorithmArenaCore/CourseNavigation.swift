import Foundation

public enum CourseError: Error, Equatable, Sendable {
  case incompatibleCourse(expected: CourseReference, actual: CourseReference)
  case invalidReference
  case invalidCoordinate
  case duplicateEdge(EdgeID)
  case invalidPolyline(EdgeID)
  case invalidMeasuredCost(EdgeID)
  case invalidStops
  case invalidRoute(RouteBranch)
  case invalidArrivalPolicy
  case surveyRequired
}

/// A spherical distance model, shared with the server fixture verifier (mean Earth radius).
public enum CourseGeometry {
  public static let earthRadiusMetres = 6_371_008.8

  public static func distance(from: Coordinate, to: Coordinate) throws -> Double {
    guard isValid(from), isValid(to) else { throw CourseError.invalidCoordinate }
    let radians = Double.pi / 180
    let latitude = (to.latitude - from.latitude) * radians
    let longitude = (to.longitude - from.longitude) * radians
    let a =
      pow(sin(latitude / 2), 2)
      + cos(from.latitude * radians) * cos(to.latitude * radians) * pow(sin(longitude / 2), 2)
    return 2 * earthRadiusMetres * asin(sqrt(min(1, max(0, a))))
  }

  public static func length(of polyline: [Coordinate]) throws -> Double {
    guard polyline.count >= 2 else { throw CourseError.invalidCoordinate }
    return try zip(polyline, polyline.dropFirst()).reduce(0) {
      try $0 + distance(from: $1.0, to: $1.1)
    }
  }

  static func isValid(_ coordinate: Coordinate) -> Bool {
    coordinate.latitude.isFinite && coordinate.longitude.isFinite
      && (-90...90).contains(coordinate.latitude) && (-180...180).contains(coordinate.longitude)
  }
}

public struct NodeHeuristic: Codable, Equatable, Sendable {
  public let nodeID: NodeID
  public let h: Int
  public init(nodeID: NodeID, h: Int) {
    self.nodeID = nodeID
    self.h = h
  }
}

/// Publish these exact integers; server implementations should not re-round coordinates.
public struct CourseHeuristics: Codable, Equatable, Sendable {
  public let course: CourseReference
  public let goal: NodeID
  public let values: [NodeHeuristic]
  public init(course: CourseReference, goal: NodeID, values: [NodeHeuristic]) {
    self.course = course
    self.goal = goal
    self.values = values
  }
}

public struct WalkingRoute: Codable, Equatable, Sendable {
  public let course: CourseReference
  public let nodeIDs: [NodeID]
  public let edgeIDs: [EdgeID]
  public let polyline: [Coordinate]
  public let distanceMetres: Int
  public init(
    course: CourseReference, nodeIDs: [NodeID], edgeIDs: [EdgeID], polyline: [Coordinate],
    distanceMetres: Int
  ) {
    self.course = course
    self.nodeIDs = nodeIDs
    self.edgeIDs = edgeIDs
    self.polyline = polyline
    self.distanceMetres = distanceMetres
  }
}

public struct CourseSearchResult: Equatable, Sendable {
  public let trace: SearchTrace
  public let route: WalkingRoute?
}

/// Validates downloaded course data once, including version, paths and checkpoint order.
/// Inspection of an awaiting-survey candidate is supported; live adapters must call
/// `requireOutdoorReadiness()` before starting a match.
public struct CourseNavigator: Sendable {
  public let course: CourseGraph
  private let nodes: [NodeID: CourseNode]
  private let edges: [EdgeID: CourseEdge]

  public init(course: CourseGraph, expected: CourseReference) throws {
    guard course.reference == expected else {
      throw CourseError.incompatibleCourse(expected: expected, actual: course.reference)
    }
    guard isASCIIIdentifier(course.reference.id.rawValue), !course.reference.version.isEmpty else {
      throw CourseError.invalidReference
    }
    let stops = course.stops
    let stopIDs = [
      stops.start, stops.first, stops.standardMiddle, stops.bonusMiddle, stops.third, stops.finish,
    ]
    guard Set(stopIDs).count == 6,
      stopIDs.allSatisfy({ id in course.nodes.contains { $0.id == id } })
    else {
      throw CourseError.invalidStops
    }
    // Zero heuristics validate the transport graph without assuming its geometry is admissible.
    try SearchEngine.validateHeuristics(
      in: .init(
        id: "course-validation",
        nodes: course.nodes.map { .init(id: $0.id, label: $0.name, heuristic: 0) },
        edges: course.edges.map {
          .init(from: $0.from, to: $0.to, cost: $0.costMetres, bidirectional: $0.bidirectional)
        },
        source: stops.start, goal: stops.finish))
    self.course = course
    self.nodes = Dictionary(uniqueKeysWithValues: course.nodes.map { ($0.id, $0) })
    var edges: [EdgeID: CourseEdge] = [:]
    for node in course.nodes where !CourseGeometry.isValid(node.coordinate) {
      throw CourseError.invalidCoordinate
    }
    for edge in course.edges {
      guard edges[edge.id] == nil else { throw CourseError.duplicateEdge(edge.id) }
      guard isASCIIIdentifier(edge.id.rawValue), edge.polyline.count >= 2,
        edge.polyline.first == nodes[edge.from]?.coordinate,
        edge.polyline.last == nodes[edge.to]?.coordinate,
        edge.polyline.allSatisfy(CourseGeometry.isValid)
      else { throw CourseError.invalidPolyline(edge.id) }
      if course.readiness != .synthetic {
        let measured = try CourseGeometry.length(of: edge.polyline)
        guard measured > 0, edge.costMetres == Int(ceil(measured)) else {
          throw CourseError.invalidMeasuredCost(edge.id)
        }
      }
      edges[edge.id] = edge
    }
    self.edges = edges
    let policy = course.arrivalPolicy
    guard
      [policy.radiusMetres, policy.maximumFixAgeSeconds, policy.maximumHorizontalAccuracyMetres]
        .allSatisfy({ $0.isFinite && $0 > 0 })
    else { throw CourseError.invalidArrivalPolicy }
    guard course.routes.count == 2, Set(course.routes.map(\.branch)) == Set(RouteBranch.allCases)
    else {
      throw CourseError.invalidStops
    }
    for route in course.routes {
      let walking = try walkingRoute(
        edgeIDs: route.edgeIDs, source: stops.start, branch: route.branch)
      let middle = route.branch == .standard ? stops.standardMiddle : stops.bonusMiddle
      guard walking.nodeIDs.last == stops.finish,
        walking.nodeIDs.filter({ stopIDs.contains($0) }) == [
          stops.start, stops.first, middle, stops.third, stops.finish,
        ],
        walking.distanceMetres == route.distanceMetres,
        route.middleRewardPoints == (route.branch == .standard ? 20 : 40)
      else { throw CourseError.invalidRoute(route.branch) }
    }
  }

  public func requireOutdoorReadiness() throws {
    guard course.readiness == .surveyed else { throw CourseError.surveyRequired }
  }

  /// Use complete authored branches for the match; a free shortest path may skip stops.
  public func route(for branch: RouteBranch) throws -> WalkingRoute {
    let route = course.routes.first { $0.branch == branch }!
    return try walkingRoute(edgeIDs: route.edgeIDs, source: course.stops.start, branch: branch)
  }

  public func heuristics(to goal: NodeID) throws -> CourseHeuristics {
    guard let target = nodes[goal] else { throw SearchError.unknownNode(goal) }
    let values = try nodes.keys.sorted().map { id in
      NodeHeuristic(
        nodeID: id,
        h: Int(
          floor(try CourseGeometry.distance(from: nodes[id]!.coordinate, to: target.coordinate))))
    }
    let table = CourseHeuristics(course: course.reference, goal: goal, values: values)
    try SearchEngine.validateHeuristics(
      in: scenario(from: course.stops.start, to: goal, table: table))
    return table
  }

  public func search(from source: NodeID, to goal: NodeID, algorithm: AlgorithmKind) throws
    -> CourseSearchResult
  {
    // The scenario's h values are immutable; Dijkstra ignores h only for priority.
    let table = try heuristics(to: goal)
    let trace = try SearchEngine.search(
      scenario(from: source, to: goal, table: table), algorithm: algorithm)
    guard case .route(let nodeIDs, _) = trace.outcome else {
      return .init(trace: trace, route: nil)
    }
    // Parallel edges are resolved by cost then edge ID, matching search's neighbour/cost ordering.
    let edgeIDs = zip(nodeIDs, nodeIDs.dropFirst()).map { from, to in
      course.edges.filter {
        ($0.from == from && $0.to == to) || ($0.bidirectional && $0.to == from && $0.from == to)
      }.min { $0.costMetres == $1.costMetres ? $0.id < $1.id : $0.costMetres < $1.costMetres }!.id
    }
    return .init(
      trace: trace, route: try walkingRoute(edgeIDs: edgeIDs, source: source, branch: .standard))
  }

  private func scenario(from source: NodeID, to goal: NodeID, table: CourseHeuristics)
    -> GraphScenario
  {
    let values = Dictionary(uniqueKeysWithValues: table.values.map { ($0.nodeID, $0.h) })
    return .init(
      id: searchScenarioID([
        course.reference.id.rawValue, course.reference.version, source.rawValue, goal.rawValue,
      ]),
      nodes: nodes.keys.sorted().map {
        .init(id: $0, label: nodes[$0]!.name, heuristic: values[$0]!)
      },
      edges: course.edges.map {
        .init(from: $0.from, to: $0.to, cost: $0.costMetres, bidirectional: $0.bidirectional)
      },
      source: source, goal: goal)
  }

  private func walkingRoute(edgeIDs: [EdgeID], source: NodeID, branch: RouteBranch) throws
    -> WalkingRoute
  {
    var nodeIDs = [source]
    var polyline = [nodes[source]!.coordinate]
    var distance = 0
    for id in edgeIDs {
      guard let edge = edges[id] else { throw CourseError.invalidRoute(branch) }
      let next: NodeID
      let points: [Coordinate]
      if edge.from == nodeIDs.last {
        next = edge.to
        points = edge.polyline
      } else if edge.bidirectional && edge.to == nodeIDs.last {
        next = edge.from
        points = edge.polyline.reversed()
      } else {
        throw CourseError.invalidRoute(branch)
      }
      nodeIDs.append(next)
      polyline.append(contentsOf: points.dropFirst())
      distance = try checkedCost(distance, edge.costMetres)
    }
    return .init(
      course: course.reference, nodeIDs: nodeIDs, edgeIDs: edgeIDs, polyline: polyline,
      distanceMetres: distance)
  }
}
