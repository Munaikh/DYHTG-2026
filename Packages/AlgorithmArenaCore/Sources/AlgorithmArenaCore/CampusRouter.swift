import Foundation

/// A surveyed network supplies connectivity explicitly. Crossing lines are not
/// automatically joined: a bridge and a path beneath it may be disconnected.
public struct PedestrianPath: Codable, Equatable, Sendable {
  public let id: EdgeID
  public let fromJunction: NodeID
  public let toJunction: NodeID
  public let bidirectional: Bool
  public let polyline: [Coordinate]
  public init(
    id: EdgeID, fromJunction: NodeID, toJunction: NodeID, bidirectional: Bool,
    polyline: [Coordinate]
  ) {
    self.id = id
    self.fromJunction = fromJunction
    self.toJunction = toJunction
    self.bidirectional = bidirectional
    self.polyline = polyline
  }
}

/// Campus paths, independent of game start/finish locations and checkpoint choices.
public struct CampusPathNetwork: Codable, Equatable, Sendable {
  public let reference: CourseReference
  public let readiness: CourseReadiness
  public let paths: [PedestrianPath]
  public init(reference: CourseReference, readiness: CourseReadiness, paths: [PedestrianPath]) {
    self.reference = reference
    self.readiness = readiness
    self.paths = paths
  }
  public init(course: CourseGraph) {
    self.init(
      reference: course.reference, readiness: course.readiness,
      paths: course.edges.map {
        .init(
          id: $0.id, fromJunction: $0.from, toJunction: $0.to, bidirectional: $0.bidirectional,
          polyline: $0.polyline)
      })
  }
}

public enum SelectedEndpoint: String, Codable, Sendable { case source, goal }

public enum CampusRoutingError: Error, Equatable, Sendable {
  case emptyNetwork
  case invalidPath(EdgeID)
  case duplicatePath(EdgeID)
  case inconsistentJunction(NodeID)
  case invalidSnapLimit
  case pointOutsideNetwork(endpoint: SelectedEndpoint, distanceMetres: Double, limitMetres: Double)
}

public struct SnappedCampusPoint: Codable, Equatable, Sendable {
  public let requested: Coordinate
  public let coordinate: Coordinate
  public let distanceToPathMetres: Double
  public let nodeID: NodeID
  public let pathID: EdgeID
}

/// A fresh graph for these two selections. Export the exact integer h values in
/// `scenario` to the server rather than recalculating floating-point geometry there.
public struct CampusRoutingGraph: Encodable, Equatable, Sendable {
  public let network: CourseReference
  public let source: SnappedCampusPoint
  public let goal: SnappedCampusPoint
  public let scenario: GraphScenario
  public let edges: [CourseEdge]

  public func search(algorithm: AlgorithmKind) throws -> CourseSearchResult {
    let trace = try SearchEngine.search(scenario, algorithm: algorithm)
    guard case .route(let ids, let cost) = trace.outcome else {
      return .init(trace: trace, route: nil)
    }
    var edgeIDs: [EdgeID] = []
    var polyline = [source.coordinate]
    for (from, to) in zip(ids, ids.dropFirst()) {
      // Search has proved the path exists. Cost, then stable edge ID resolves parallel paths.
      let edge = edges.filter {
        ($0.from == from && $0.to == to) || ($0.bidirectional && $0.to == from && $0.from == to)
      }.min { $0.costMetres == $1.costMetres ? $0.id < $1.id : $0.costMetres < $1.costMetres }!
      edgeIDs.append(edge.id)
      let points = edge.from == from ? edge.polyline : Array(edge.polyline.reversed())
      polyline.append(contentsOf: points.dropFirst())
    }
    return .init(
      trace: trace,
      route: .init(
        course: network, nodeIDs: ids, edgeIDs: edgeIDs, polyline: polyline, distanceMetres: cost))
  }
}

/// Builds dynamic start/goal nodes anywhere on the supplied campus pedestrian
/// network. A map adapter supplies selected coordinates; this core has no MapKit dependency.
public struct CampusRouter: Sendable {
  public let network: CampusPathNetwork
  private let junctions: [NodeID: Coordinate]

  public init(network: CampusPathNetwork, expected: CourseReference) throws {
    guard network.reference == expected else {
      throw CourseError.incompatibleCourse(expected: expected, actual: network.reference)
    }
    guard !network.paths.isEmpty else { throw CampusRoutingError.emptyNetwork }
    guard isASCIIIdentifier(network.reference.id.rawValue), !network.reference.version.isEmpty
    else {
      throw CourseError.invalidReference
    }
    var junctions: [NodeID: Coordinate] = [:]
    var ids: Set<EdgeID> = []
    for path in network.paths.sorted(by: { $0.id < $1.id }) {
      guard ids.insert(path.id).inserted else { throw CampusRoutingError.duplicatePath(path.id) }
      guard isASCIIIdentifier(path.id.rawValue), isASCIIIdentifier(path.fromJunction.rawValue),
        isASCIIIdentifier(path.toJunction.rawValue), path.polyline.count >= 2,
        path.polyline.allSatisfy(CourseGeometry.isValid)
      else { throw CampusRoutingError.invalidPath(path.id) }
      let length = try CourseGeometry.length(of: path.polyline)
      guard length > 0, length < Double(SearchEngine.maximumCost) else {
        throw CampusRoutingError.invalidPath(path.id)
      }
      for (id, coordinate) in [
        (path.fromJunction, path.polyline.first!), (path.toJunction, path.polyline.last!),
      ] {
        if let existing = junctions[id], existing != coordinate {
          throw CampusRoutingError.inconsistentJunction(id)
        }
        junctions[id] = coordinate
      }
    }
    self.network = network
    self.junctions = junctions
  }

  public func requireOutdoorReadiness() throws {
    guard network.readiness == .surveyed else { throw CourseError.surveyRequired }
  }

  /// Snapping gaps are returned explicitly, never drawn or charged as invented paths.
  /// Points farther than the configurable limit fail with a recoverable error.
  public func graph(
    from source: Coordinate, to goal: Coordinate, maximumSnapDistanceMetres: Double = 25
  ) throws -> CampusRoutingGraph {
    guard maximumSnapDistanceMetres.isFinite, maximumSnapDistanceMetres >= 0 else {
      throw CampusRoutingError.invalidSnapLimit
    }
    let start = try snap(source, endpoint: .source, limit: maximumSnapDistanceMetres)
    let finish = try snap(goal, endpoint: .goal, limit: maximumSnapDistanceMetres)
    var coordinates = Dictionary(
      uniqueKeysWithValues: junctions.map { (junctionID($0.key), $0.value) })
    func selectionID(_ snap: Snap, role: String) -> NodeID {
      if snap.offset == 0 { return junctionID(snap.path.fromJunction) }
      if snap.offset == snap.length { return junctionID(snap.path.toJunction) }
      return .init(rawValue: "selection:\(role)")
    }
    let sourceID = selectionID(start, role: "source")
    let samePosition = start.path.id == finish.path.id && start.offset == finish.offset
    let goalID = samePosition ? sourceID : selectionID(finish, role: "goal")
    coordinates[sourceID] = start.coordinate
    coordinates[goalID] = samePosition ? start.coordinate : finish.coordinate
    var edges: [CourseEdge] = []
    for path in network.paths.sorted(by: { $0.id < $1.id }) {
      let cumulative = try offsets(path.polyline)
      var cuts: [(offset: Double, id: NodeID, coordinate: Coordinate)] = [
        (0, junctionID(path.fromJunction), path.polyline.first!),
        (cumulative.last!, junctionID(path.toJunction), path.polyline.last!),
      ]
      if start.path.id == path.id && sourceID.rawValue.hasPrefix("selection:") {
        cuts.append((start.offset, sourceID, start.coordinate))
      }
      if finish.path.id == path.id && goalID != sourceID && goalID.rawValue.hasPrefix("selection:")
      {
        cuts.append((finish.offset, goalID, finish.coordinate))
      }
      cuts.sort { $0.offset == $1.offset ? $0.id < $1.id : $0.offset < $1.offset }
      for (index, pair) in zip(cuts, cuts.dropFirst()).enumerated() {
        let (from, to) = pair
        let interior = path.polyline.indices.filter {
          cumulative[$0] > from.offset && cumulative[$0] < to.offset
        }.map { path.polyline[$0] }
        let polyline = [from.coordinate] + interior + [to.coordinate]
        edges.append(
          .init(
            id: .init(rawValue: "path:\(path.id.rawValue):\(index)"), from: from.id, to: to.id,
            bidirectional: path.bidirectional,
            costMetres: Int(ceil(try CourseGeometry.length(of: polyline))), polyline: polyline))
      }
    }
    let scenario = GraphScenario(
      id: searchScenarioID(
        [network.reference.id.rawValue, network.reference.version]
          + selectionKey(start) + selectionKey(finish)),
      nodes: try coordinates.keys.sorted().map { id in
        .init(
          id: id,
          label: id == sourceID ? "Selected start" : id == goalID ? "Selected goal" : id.rawValue,
          heuristic: Int(
            floor(try CourseGeometry.distance(from: coordinates[id]!, to: coordinates[goalID]!))))
      },
      edges: edges.map {
        .init(from: $0.from, to: $0.to, cost: $0.costMetres, bidirectional: $0.bidirectional)
      },
      source: sourceID, goal: goalID)
    try SearchEngine.validateHeuristics(in: scenario)
    return .init(
      network: network.reference,
      source: .init(
        requested: source, coordinate: start.coordinate, distanceToPathMetres: start.distance,
        nodeID: sourceID, pathID: start.path.id),
      goal: .init(
        requested: goal, coordinate: coordinates[goalID]!, distanceToPathMetres: finish.distance,
        nodeID: goalID, pathID: finish.path.id),
      scenario: scenario, edges: edges)
  }

  private struct Snap {
    let path: PedestrianPath
    let coordinate: Coordinate
    let distance: Double
    let offset: Double
    let length: Double
  }

  private func snap(_ point: Coordinate, endpoint: SelectedEndpoint, limit: Double) throws -> Snap {
    guard CourseGeometry.isValid(point) else { throw CourseError.invalidCoordinate }
    var best: Snap?
    for path in network.paths.sorted(by: { $0.id < $1.id }) {
      let cumulative = try offsets(path.polyline)
      for index in 0..<(path.polyline.count - 1) {
        let a = path.polyline[index]
        let b = path.polyline[index + 1]
        // Local equirectangular projection is appropriate for short campus path segments.
        let scale = cos((a.latitude + b.latitude) / 2 * .pi / 180)
        let dx = (b.longitude - a.longitude) * scale
        let dy = b.latitude - a.latitude
        let denominator = dx * dx + dy * dy
        guard denominator > 0 else { continue }
        let fraction = min(
          1,
          max(
            0,
            ((point.longitude - a.longitude) * scale * dx + (point.latitude - a.latitude) * dy)
              / denominator))
        let coordinate =
          fraction == 0
          ? a
          : fraction == 1
            ? b
            : Coordinate(
              latitude: a.latitude + fraction * (b.latitude - a.latitude),
              longitude: a.longitude + fraction * (b.longitude - a.longitude))
        let distance = try CourseGeometry.distance(from: point, to: coordinate)
        let offset =
          fraction == 1
          ? cumulative[index + 1]
          : cumulative[index] + (try CourseGeometry.distance(from: a, to: coordinate))
        if best == nil || distance < best!.distance - 0.000000001 {
          best = .init(
            path: path, coordinate: coordinate, distance: distance, offset: offset,
            length: cumulative.last!)
        }
      }
    }
    // Nonempty network and positive path lengths guarantee a segment.
    let result = best!
    guard result.distance <= limit else {
      throw CampusRoutingError.pointOutsideNetwork(
        endpoint: endpoint, distanceMetres: result.distance, limitMetres: limit)
    }
    return result
  }

  private func offsets(_ polyline: [Coordinate]) throws -> [Double] {
    var result = [0.0]
    for (a, b) in zip(polyline, polyline.dropFirst()) {
      result.append(result.last! + (try CourseGeometry.distance(from: a, to: b)))
    }
    return result
  }

  private func junctionID(_ id: NodeID) -> NodeID { .init(rawValue: "junction:\(id.rawValue)") }

  private func selectionKey(_ snap: Snap) -> [String] {
    [
      snap.path.id.rawValue, String(snap.coordinate.latitude.bitPattern, radix: 16),
      String(snap.coordinate.longitude.bitPattern, radix: 16),
    ]
  }
}
