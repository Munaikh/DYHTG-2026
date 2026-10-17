import Foundation

public enum WalkingJunctionError: Error, Equatable, Sendable {
  case emptyNetwork
  case invalidPath(EdgeID)
  case invalidEndpoint(NodeID)
  case conflictingEndpointID
  case coincidentEndpoints
  case endpointNotOnPath(SelectedEndpoint)
  case disconnectedEndpoints
}

/// Turns returned walking-route geometry into a junction graph. Buildings are
/// sampling destinations, not vertices in the resulting algorithm lesson.
///
/// Only supplied vertices can form connections: a vertex on another segment
/// splits that segment, but an unmarked geometric crossing never creates a node.
/// Sub-metre coordinate noise is coalesced within 0.75 m; no longer connector or
/// shortcut is introduced. Degree-two bends remain inside each output polyline.
public struct WalkingJunctionNetwork: Sendable {
  public let nodes: [CourseNode]
  public let paths: [PedestrianPath]

  public init(paths input: [PedestrianPath], source: CourseNode, goal: CourseNode) throws {
    guard !input.isEmpty else { throw WalkingJunctionError.emptyNetwork }
    for endpoint in [source, goal] {
      guard isASCIIIdentifier(endpoint.id.rawValue), CourseGeometry.isValid(endpoint.coordinate) else {
        throw WalkingJunctionError.invalidEndpoint(endpoint.id)
      }
    }
    if source.id == goal.id, source.coordinate != goal.coordinate {
      throw WalkingJunctionError.conflictingEndpointID
    }
    if source.id != goal.id,
       try CourseGeometry.distance(from: source.coordinate, to: goal.coordinate) <= Self.tolerance {
      throw WalkingJunctionError.coincidentEndpoints
    }

    var segments: [Segment] = []
    var points: [PointKey: Coordinate] = [:]
    for path in input {
      guard path.polyline.count >= 2, path.polyline.allSatisfy(CourseGeometry.isValid) else {
        throw WalkingJunctionError.invalidPath(path.id)
      }
      var hasLength = false
      for (from, to) in zip(path.polyline, path.polyline.dropFirst()) {
        points[PointKey(from)] = from
        points[PointKey(to)] = to
        if from != to {
          hasLength = true
          segments.append(.init(from: from, to: to, bidirectional: path.bidirectional))
        }
      }
      guard hasLength else { throw WalkingJunctionError.invalidPath(path.id) }
    }
    let selections: [(CourseNode, SelectedEndpoint)] = [(source, .source), (goal, .goal)]
    for (endpoint, role) in selections {
      guard try segments.contains(where: {
        try Self.projection(endpoint.coordinate, on: $0).distance <= Self.tolerance
      }) else { throw WalkingJunctionError.endpointNotOnPath(role) }
    }

    // Endpoint anchors take priority so their supplied coordinates and IDs remain
    // exact. Sorting the other coordinates makes clustering independent of input
    // path order and direction. A cluster's full diameter is bounded, preventing
    // a chain of tiny differences from merging distinct nearby footways.
    var vertices: [Vertex] = []
    let endpointPoints = [source.coordinate, goal.coordinate].sorted(by: Self.coordinateLess)
    let otherPoints = points.values.sorted(by: Self.coordinateLess)
    var pointVertex: [PointKey: Int] = [:]
    for point in endpointPoints + otherPoints {
      let key = PointKey(point)
      if pointVertex[key] != nil { continue }
      var closest: (index: Int, distance: Double)?
      for index in vertices.indices {
        let distance = try CourseGeometry.distance(from: point, to: vertices[index].coordinate)
        guard distance <= Self.tolerance,
              try vertices[index].members.allSatisfy({
                try CourseGeometry.distance(from: point, to: $0) <= Self.tolerance
              }) else { continue }
        if closest == nil || distance < closest!.distance { closest = (index, distance) }
      }
      if let closest {
        pointVertex[key] = closest.index
        vertices[closest.index].members.append(point)
      } else {
        pointVertex[key] = vertices.count
        vertices.append(.init(coordinate: point, members: [point]))
      }
    }
    let sourceVertex = pointVertex[PointKey(source.coordinate)]!
    let goalVertex = pointVertex[PointKey(goal.coordinate)]!

    // Split only where an actual returned vertex (or selected entrance) lies on
    // a segment. The atomic key deduplicates a shared trunk even if one provider
    // route samples it more densely or traverses it in the reverse direction.
    var atomic: [AtomicKey: AtomicEdge] = [:]
    for segment in segments {
      let start = pointVertex[PointKey(segment.from)]!
      let finish = pointVertex[PointKey(segment.to)]!
      if start == finish { continue }
      var cuts: [(fraction: Double, vertex: Int)] = [(0, start), (1, finish)]
      for index in vertices.indices where index != start && index != finish {
        let projection = try Self.projection(vertices[index].coordinate, on: segment)
        guard projection.distance <= Self.tolerance, projection.fraction > 0, projection.fraction < 1 else { continue }
        cuts.append((projection.fraction, index))
      }
      cuts.sort {
        $0.fraction == $1.fraction
          ? Self.coordinateLess(vertices[$0.vertex].coordinate, vertices[$1.vertex].coordinate)
          : $0.fraction < $1.fraction
      }
      for (from, to) in zip(cuts, cuts.dropFirst()) {
        guard from.vertex != to.vertex, to.fraction > from.fraction else { continue }
        let key = AtomicKey(from.vertex, to.vertex)
        let forward = from.vertex == key.first
        var edge = atomic[key] ?? AtomicEdge(key: key, forward: false, reverse: false)
        edge.forward = edge.forward || segment.bidirectional || forward
        edge.reverse = edge.reverse || segment.bidirectional || !forward
        atomic[key] = edge
      }
    }
    var adjacency: [Int: Set<AtomicKey>] = [:]
    for key in atomic.keys {
      adjacency[key.first, default: []].insert(key)
      adjacency[key.second, default: []].insert(key)
    }
    let component = Self.reachable(from: sourceVertex, adjacency: adjacency)
    guard component.contains(goalVertex) else { throw WalkingJunctionError.disconnectedEndpoints }
    for vertex in adjacency.keys where !component.contains(vertex) { adjacency[vertex] = nil }
    atomic = atomic.filter { component.contains($0.key.first) && component.contains($0.key.second) }

    // Repeatedly remove unselected building spurs. A selected entrance is never
    // pruned, even when it is a dead end or a mid-segment degree-two point.
    let selected: Set<Int> = [sourceVertex, goalVertex]
    var queue = adjacency.keys.filter { !selected.contains($0) && adjacency[$0]!.count <= 1 }.sorted()
    var cursor = 0
    while cursor < queue.count {
      let vertex = queue[cursor]
      cursor += 1
      guard !selected.contains(vertex), let incident = adjacency[vertex], incident.count <= 1 else { continue }
      for key in incident {
        let other = key.other(vertex)
        adjacency[other]?.remove(key)
        atomic[key] = nil
        if !selected.contains(other), (adjacency[other]?.count ?? 0) <= 1 { queue.append(other) }
      }
      adjacency[vertex] = nil
    }
    let retained = Set(adjacency.keys.filter { (adjacency[$0]?.count ?? 0) != 2 }).union(selected)
    let orderedRetained = retained.sorted {
      Self.coordinateLess(vertices[$0].coordinate, vertices[$1].coordinate)
    }
    var identifiers: [Int: NodeID] = [sourceVertex: source.id]
    identifiers[goalVertex] = goal.id
    var reserved: Set<NodeID> = [source.id, goal.id]
    var outputNodes: [CourseNode] = []
    var number = 0
    for vertex in orderedRetained {
      if vertex == sourceVertex { outputNodes.append(source); continue }
      if vertex == goalVertex { outputNodes.append(goal); continue }
      number += 1
      let point = vertices[vertex].coordinate
      let base = "walking-junction-" + Self.digest(Self.coordinateKey(point))
      var id = NodeID(rawValue: base)
      var suffix = 1
      while reserved.contains(id) { id = NodeID(rawValue: "\(base)-\(suffix)"); suffix += 1 }
      reserved.insert(id)
      identifiers[vertex] = id
      outputNodes.append(.init(id: id, name: "Walking junction \(number)", coordinate: point,
        stoppingNote: "Shared vertex in Apple Maps walking-path geometry."))
    }

    var visited: Set<AtomicKey> = []
    var outputPaths: [PedestrianPath] = []
    for origin in orderedRetained {
      for firstEdge in (adjacency[origin] ?? []).sorted() where !visited.contains(firstEdge) {
        var current = origin
        var nextEdge = firstEdge
        var polyline = [vertices[current].coordinate]
        var canForward = true
        var canReverse = true
        while true {
          // Every iteration consumes a new atomic edge. A cycle therefore ends
          // at a retained junction or the selected anchor where it began.
          guard visited.insert(nextEdge).inserted, let edge = atomic[nextEdge] else { break }
          let next = nextEdge.other(current)
          canForward = canForward && edge.allows(from: current)
          canReverse = canReverse && edge.allows(from: next)
          polyline.append(vertices[next].coordinate)
          if retained.contains(next) {
            guard canForward || canReverse else { break }
            var from = identifiers[origin]!
            var to = identifiers[next]!
            if !canForward || (canReverse && (to < from || (to == from && Self.polylineKey(polyline.reversed()) < Self.polylineKey(polyline)))) {
              swap(&from, &to)
              polyline.reverse()
            }
            let key = "\(from.rawValue):\(to.rawValue):" + Self.polylineKey(polyline)
            outputPaths.append(.init(id: EdgeID(rawValue: "walking-path-" + Self.digest(key)),
              fromJunction: from, toJunction: to, bidirectional: canForward && canReverse, polyline: polyline))
            break
          }
          guard let following = adjacency[next]?.first(where: { $0 != nextEdge }) else { break }
          current = next
          nextEdge = following
        }
      }
    }
    guard Self.hasRoute(from: source.id, to: goal.id, paths: outputPaths) else {
      throw WalkingJunctionError.disconnectedEndpoints
    }
    nodes = outputNodes.sorted { $0.id < $1.id }
    paths = outputPaths.sorted { $0.id < $1.id }
  }

  private static let tolerance = 0.75

  private struct PointKey: Hashable {
    let latitude: Double
    let longitude: Double
    init(_ point: Coordinate) { latitude = point.latitude; longitude = point.longitude }
  }
  private struct Vertex { let coordinate: Coordinate; var members: [Coordinate] }
  private struct Segment { let from: Coordinate; let to: Coordinate; let bidirectional: Bool }
  private struct AtomicKey: Hashable, Comparable {
    let first: Int
    let second: Int
    init(_ a: Int, _ b: Int) { first = min(a, b); second = max(a, b) }
    func other(_ vertex: Int) -> Int { vertex == first ? second : first }
    static func < (lhs: Self, rhs: Self) -> Bool {
      lhs.first == rhs.first ? lhs.second < rhs.second : lhs.first < rhs.first
    }
  }
  private struct AtomicEdge {
    let key: AtomicKey
    var forward: Bool
    var reverse: Bool
    func allows(from: Int) -> Bool { from == key.first ? forward : reverse }
  }

  private static func projection(_ point: Coordinate, on segment: Segment) throws -> (fraction: Double, distance: Double) {
    let scale = cos((segment.from.latitude + segment.to.latitude) / 2 * .pi / 180)
    let dx = (segment.to.longitude - segment.from.longitude) * scale
    let dy = segment.to.latitude - segment.from.latitude
    let denominator = dx * dx + dy * dy
    let fraction = denominator > 0 ? min(1, max(0,
      ((point.longitude - segment.from.longitude) * scale * dx + (point.latitude - segment.from.latitude) * dy) / denominator)) : 0
    let projected = Coordinate(
      latitude: segment.from.latitude + fraction * (segment.to.latitude - segment.from.latitude),
      longitude: segment.from.longitude + fraction * (segment.to.longitude - segment.from.longitude))
    return (fraction, try CourseGeometry.distance(from: point, to: projected))
  }

  private static func reachable(from start: Int, adjacency: [Int: Set<AtomicKey>]) -> Set<Int> {
    var found: Set<Int> = [start]
    var queue = [start]
    var cursor = 0
    while cursor < queue.count {
      let current = queue[cursor]
      cursor += 1
      for edge in adjacency[current] ?? [] {
        let next = edge.other(current)
        if found.insert(next).inserted { queue.append(next) }
      }
    }
    return found
  }

  private static func hasRoute(from source: NodeID, to goal: NodeID, paths: [PedestrianPath]) -> Bool {
    var neighbors: [NodeID: Set<NodeID>] = [:]
    for path in paths {
      neighbors[path.fromJunction, default: []].insert(path.toJunction)
      if path.bidirectional { neighbors[path.toJunction, default: []].insert(path.fromJunction) }
    }
    var seen: Set<NodeID> = [source]
    var queue = [source]
    var cursor = 0
    while cursor < queue.count {
      let current = queue[cursor]
      cursor += 1
      if current == goal { return true }
      for next in neighbors[current] ?? [] where seen.insert(next).inserted { queue.append(next) }
    }
    return false
  }

  private static func coordinateLess(_ a: Coordinate, _ b: Coordinate) -> Bool {
    a.latitude == b.latitude ? a.longitude < b.longitude : a.latitude < b.latitude
  }
  private static func coordinateKey(_ point: Coordinate) -> String {
    "\(point.latitude.bitPattern):\(point.longitude.bitPattern)"
  }
  private static func polylineKey(_ points: some Sequence<Coordinate>) -> String {
    points.map(coordinateKey).joined(separator: ";")
  }
  private static func digest(_ value: String) -> String {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in value.utf8 { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
    return String(hash, radix: 16)
  }
}
