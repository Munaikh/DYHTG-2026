import Foundation

/// A small educational graph whose arcs retain the exact geometry returned by a
/// walking-directions provider. A junction is a logical stop, not an assertion
/// that every returned entrance coordinate is identical. Draw edges separately:
/// concatenating them would invent connectors across the reported snapping gaps.
public struct RoutedCampusGraph: Sendable {
  public let graph: CampusRoutingGraph
  public let maximumEndpointGapMetres: Double
  public let heuristicScale: Double

  public init(
    reference: CourseReference, nodes: [CourseNode], paths: [PedestrianPath],
    source: NodeID, goal: NodeID
  ) throws {
    guard isASCIIIdentifier(reference.id.rawValue), !reference.version.isEmpty else {
      throw CourseError.invalidReference
    }
    var coordinates: [NodeID: Coordinate] = [:]
    for node in nodes {
      guard isASCIIIdentifier(node.id.rawValue) else { throw SearchError.invalidNodeID(node.id) }
      guard coordinates[node.id] == nil else { throw SearchError.duplicateNode(node.id) }
      guard CourseGeometry.isValid(node.coordinate) else { throw CourseError.invalidCoordinate }
      coordinates[node.id] = node.coordinate
    }
    for id in [source, goal] where coordinates[id] == nil { throw SearchError.unknownNode(id) }
    var edgeIDs: Set<EdgeID> = []
    var gap = 0.0
    var scale = 1.0
    var edges: [CourseEdge] = []
    for path in paths.sorted(by: { $0.id < $1.id }) {
      guard edgeIDs.insert(path.id).inserted else { throw CourseError.duplicateEdge(path.id) }
      guard isASCIIIdentifier(path.id.rawValue), path.polyline.count >= 2,
        path.polyline.allSatisfy(CourseGeometry.isValid)
      else { throw CourseError.invalidPolyline(path.id) }
      for id in [path.fromJunction, path.toJunction] where coordinates[id] == nil {
        throw SearchError.unknownNode(id)
      }
      let length = try CourseGeometry.length(of: path.polyline)
      guard length > 0, length < Double(SearchEngine.maximumCost) else {
        throw CourseError.invalidMeasuredCost(path.id)
      }
      let cost = Int(ceil(length))
      let from = coordinates[path.fromJunction]!
      let to = coordinates[path.toJunction]!
      let direct = try CourseGeometry.distance(from: from, to: to)
      // MapKit can snap either pin to an entrance. Scaling the geographic metric
      // by the tightest edge ratio keeps h consistent even when a returned path
      // is shorter than the distance between the originally selected pins.
      if direct > 0 { scale = min(scale, Double(cost) / direct) }
      gap = max(gap, try CourseGeometry.distance(from: from, to: path.polyline.first!))
      gap = max(gap, try CourseGeometry.distance(from: to, to: path.polyline.last!))
      edges.append(.init(
        id: path.id, from: path.fromJunction, to: path.toJunction,
        bidirectional: path.bidirectional, costMetres: cost, polyline: path.polyline))
    }
    // Protect the consistency inequality from floating-point boundary rounding.
    scale *= 1 - 1e-10
    let scenario = GraphScenario(
      id: searchScenarioID([reference.id.rawValue, reference.version, source.rawValue, goal.rawValue]
        + nodes.sorted { $0.id < $1.id }.flatMap {
          [$0.id.rawValue, String($0.coordinate.latitude.bitPattern), String($0.coordinate.longitude.bitPattern)]
        } + edges.flatMap { [$0.id.rawValue, String($0.costMetres)] }),
      nodes: try nodes.sorted { $0.id < $1.id }.map { node in
        .init(id: node.id, label: node.name,
          heuristic: Int(floor(scale * (try CourseGeometry.distance(
            from: node.coordinate, to: coordinates[goal]!)))))
      },
      edges: edges.map { .init(from: $0.from, to: $0.to, cost: $0.costMetres, bidirectional: $0.bidirectional) },
      source: source, goal: goal)
    try SearchEngine.validateHeuristics(in: scenario)
    func endpoint(_ id: NodeID) throws -> SnappedCampusPoint {
      let requested = coordinates[id]!
      let adjacent = edges.filter { $0.from == id || ($0.bidirectional && $0.to == id) }
      let closest = try adjacent.map { edge in
        let point = edge.from == id ? edge.polyline.first! : edge.polyline.last!
        return (edge, point, try CourseGeometry.distance(from: requested, to: point))
      }.min { $0.2 < $1.2 }
      return .init(requested: requested, coordinate: closest?.1 ?? requested,
        distanceToPathMetres: closest?.2 ?? 0, nodeID: id,
        pathID: closest?.0.id ?? "unconnected")
    }
    graph = try .init(network: reference, source: endpoint(source), goal: endpoint(goal),
      scenario: scenario, edges: edges)
    maximumEndpointGapMetres = gap
    heuristicScale = scale
  }
}
