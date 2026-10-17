import Foundation

/// Desktop survey proposal only. Coordinates and polylines are estimates, not verified
/// pedestrian/accessibility data. See docs/COURSE_SURVEY.md before outdoor use.
public enum GilmorehillCourse {
  public static let candidateReference = CourseReference(
    id: "gilmorehill-jms-library", version: "candidate-2026-10-17-1")

  public static func candidate() throws -> CourseGraph {
    let nodes: [CourseNode] = [
      node("01-jms", "Outside James McCune Smith Learning Hub", 55.87312, -4.29370),
      node("02-lilybank-gardens", "Lilybank Gardens — checkpoint one", 55.87425, -4.29275),
      node("03-lilybank-house", "Lilybank House — standard middle", 55.87468, -4.29145),
      node("04-hetherington", "Hetherington — bonus middle", 55.87415, -4.29045),
      node("05-rejoin", "Bute Gardens branch rejoin", 55.87375, -4.29020),
      node("06-fraser", "Outside Fraser Building — checkpoint three", 55.87312, -4.28955),
      node("07-library", "Outside University Library — finish", 55.87360, -4.28875),
    ]
    let coordinates = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.coordinate) })
    func edge(_ id: EdgeID, _ from: NodeID, _ to: NodeID, via: [Coordinate] = []) throws
      -> CourseEdge
    {
      // All endpoints refer to the closed, immutable node list above.
      let polyline = [coordinates[from]!] + via + [coordinates[to]!]
      return .init(
        id: id, from: from, to: to, bidirectional: true,
        costMetres: Int(ceil(try CourseGeometry.length(of: polyline))), polyline: polyline)
    }
    let edges: [CourseEdge] = try [
      edge(
        "jms-gardens", "01-jms", "02-lilybank-gardens",
        via: [
          .init(latitude: 55.87345, longitude: -4.29365),
          .init(latitude: 55.87395, longitude: -4.29335),
        ]),
      edge(
        "gardens-house", "02-lilybank-gardens", "03-lilybank-house",
        via: [
          .init(latitude: 55.87465, longitude: -4.29260)
        ]),
      edge(
        "house-rejoin", "03-lilybank-house", "05-rejoin",
        via: [
          .init(latitude: 55.87470, longitude: -4.29090),
          .init(latitude: 55.87415, longitude: -4.29065),
        ]),
      edge(
        "gardens-hetherington", "02-lilybank-gardens", "04-hetherington",
        via: [
          .init(latitude: 55.87500, longitude: -4.29260),
          .init(latitude: 55.87500, longitude: -4.29045),
        ]),
      edge("hetherington-rejoin", "04-hetherington", "05-rejoin"),
      edge(
        "rejoin-fraser", "05-rejoin", "06-fraser",
        via: [
          .init(latitude: 55.87335, longitude: -4.29010)
        ]),
      edge(
        "fraser-library", "06-fraser", "07-library",
        via: [
          .init(latitude: 55.87312, longitude: -4.28875)
        ]),
    ]
    let costs = Dictionary(uniqueKeysWithValues: edges.map { ($0.id, $0.costMetres) })
    func route(_ branch: RouteBranch, _ ids: [EdgeID]) -> CourseRoute {
      .init(
        branch: branch, edgeIDs: ids, distanceMetres: ids.reduce(0) { $0 + costs[$1]! },
        difficulty: branch == .standard
          ? "One cost update" : "Compare and replace a tentative cost",
        middleRewardPoints: branch == .standard ? 20 : 40)
    }
    return .init(
      reference: candidateReference, name: "Gilmorehill JMS → Library — awaiting outdoor survey",
      readiness: .awaitingSurvey, nodes: nodes, edges: edges,
      stops: .init(
        start: "01-jms", first: "02-lilybank-gardens", standardMiddle: "03-lilybank-house",
        bonusMiddle: "04-hetherington", third: "06-fraser", finish: "07-library"),
      routes: [
        route(
          .standard,
          ["jms-gardens", "gardens-house", "house-rejoin", "rejoin-fraser", "fraser-library"]),
        route(
          .bonus,
          [
            "jms-gardens", "gardens-hetherington", "hetherington-rejoin", "rejoin-fraser",
            "fraser-library",
          ]),
      ],
      arrivalPolicy: .init(
        radiusMetres: 25, maximumFixAgeSeconds: 10, maximumHorizontalAccuracyMetres: 20))
  }

  private static func node(_ id: NodeID, _ name: String, _ latitude: Double, _ longitude: Double)
    -> CourseNode
  {
    .init(
      id: id, name: name, coordinate: .init(latitude: latitude, longitude: longitude),
      stoppingNote:
        "Estimated survey candidate. Confirm pedestrian access, step-free route and safe stopping space outdoors; not approved for navigation."
    )
  }
}
