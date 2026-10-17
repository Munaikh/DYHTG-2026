import Foundation

public struct CourseReference: Codable, Equatable, Sendable {
  public let id: CourseID
  public let version: String
  public init(id: CourseID, version: String) {
    self.id = id
    self.version = version
  }
}

public struct Coordinate: Codable, Equatable, Sendable {
  public let latitude: Double
  public let longitude: Double
  public init(latitude: Double, longitude: Double) {
    self.latitude = latitude
    self.longitude = longitude
  }
}

public struct ArrivalPolicy: Codable, Equatable, Sendable {
  public let radiusMetres: Double
  public let maximumFixAgeSeconds: Double
  public let maximumHorizontalAccuracyMetres: Double
  public init(
    radiusMetres: Double, maximumFixAgeSeconds: Double, maximumHorizontalAccuracyMetres: Double
  ) {
    self.radiusMetres = radiusMetres
    self.maximumFixAgeSeconds = maximumFixAgeSeconds
    self.maximumHorizontalAccuracyMetres = maximumHorizontalAccuracyMetres
  }
}

public struct CourseNode: Codable, Equatable, Sendable, Identifiable {
  public let id: NodeID
  public let name: String
  public let coordinate: Coordinate
  public let stoppingNote: String
  public init(id: NodeID, name: String, coordinate: Coordinate, stoppingNote: String) {
    self.id = id
    self.name = name
    self.coordinate = coordinate
    self.stoppingNote = stoppingNote
  }
}

public struct CourseEdge: Codable, Equatable, Sendable, Identifiable {
  public let id: EdgeID
  public let from: NodeID
  public let to: NodeID
  public let bidirectional: Bool
  public let costMetres: Int
  /// Ordered from `from` to `to`; reverse for the opposite traversal.
  public let polyline: [Coordinate]
  public init(
    id: EdgeID, from: NodeID, to: NodeID, bidirectional: Bool, costMetres: Int,
    polyline: [Coordinate]
  ) {
    self.id = id
    self.from = from
    self.to = to
    self.bidirectional = bidirectional
    self.costMetres = costMetres
    self.polyline = polyline
  }
}

public struct CourseStops: Codable, Equatable, Sendable {
  public let start: NodeID
  public let first: NodeID
  public let standardMiddle: NodeID
  public let bonusMiddle: NodeID
  public let third: NodeID
  public let finish: NodeID
  public init(
    start: NodeID, first: NodeID, standardMiddle: NodeID, bonusMiddle: NodeID, third: NodeID,
    finish: NodeID
  ) {
    self.start = start
    self.first = first
    self.standardMiddle = standardMiddle
    self.bonusMiddle = bonusMiddle
    self.third = third
    self.finish = finish
  }
}

public struct CourseRoute: Codable, Equatable, Sendable {
  public let branch: RouteBranch
  /// Complete ordered start-to-finish route, including the common legs.
  public let edgeIDs: [EdgeID]
  public let distanceMetres: Int
  public let difficulty: String
  public let middleRewardPoints: Int
  public init(
    branch: RouteBranch, edgeIDs: [EdgeID], distanceMetres: Int, difficulty: String,
    middleRewardPoints: Int
  ) {
    self.branch = branch
    self.edgeIDs = edgeIDs
    self.distanceMetres = distanceMetres
    self.difficulty = difficulty
    self.middleRewardPoints = middleRewardPoints
  }
}

public enum CourseReadiness: String, Codable, Sendable { case synthetic, awaitingSurvey, surveyed }

public struct CourseGraph: Codable, Equatable, Sendable {
  public let contractVersion: ContractVersion
  public let reference: CourseReference
  public let name: String
  public let readiness: CourseReadiness
  public let nodes: [CourseNode]
  public let edges: [CourseEdge]
  public let stops: CourseStops
  public let routes: [CourseRoute]
  public let arrivalPolicy: ArrivalPolicy
  public init(
    contractVersion: ContractVersion = .v1, reference: CourseReference, name: String,
    readiness: CourseReadiness, nodes: [CourseNode], edges: [CourseEdge], stops: CourseStops,
    routes: [CourseRoute], arrivalPolicy: ArrivalPolicy
  ) {
    self.contractVersion = contractVersion
    self.reference = reference
    self.name = name
    self.readiness = readiness
    self.nodes = nodes
    self.edges = edges
    self.stops = stops
    self.routes = routes
    self.arrivalPolicy = arrivalPolicy
  }
}
