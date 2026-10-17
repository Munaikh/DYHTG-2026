import AlgorithmArenaCore
import Foundation
import Testing

@Test func candidateCourseHasMeasuredBranchesAndSurveyGate() throws {
  let course = try GilmorehillCourse.candidate()
  let navigator = try CourseNavigator(course: course, expected: course.reference)
  #expect(course.readiness == .awaitingSurvey)
  #expect(course.nodes.allSatisfy { $0.stoppingNote.contains("not approved for navigation") })
  #expect(throws: CourseError.surveyRequired) { try navigator.requireOutdoorReadiness() }
  let standard = try navigator.route(for: .standard)
  let bonus = try navigator.route(for: .bonus)
  #expect(standard.distanceMetres == 607)
  #expect(bonus.distanceMetres == 699)
  #expect(
    (500...800).contains(standard.distanceMetres) && (500...800).contains(bonus.distanceMetres))
  #expect((50...100).contains(bonus.distanceMetres - standard.distanceMetres))
  #expect(
    standard.nodeIDs == [
      course.stops.start, course.stops.first, course.stops.standardMiddle, "05-rejoin",
      course.stops.third, course.stops.finish,
    ])
  #expect(
    bonus.nodeIDs == [
      course.stops.start, course.stops.first, course.stops.bonusMiddle, "05-rejoin",
      course.stops.third, course.stops.finish,
    ])
  for edge in course.edges {
    #expect(edge.costMetres == Int(ceil(try CourseGeometry.length(of: edge.polyline))))
    #expect(edge.polyline.count >= 2)
  }
  #expect(
    try ContractJSON.decoder().decode(CourseGraph.self, from: ContractJSON.encoder().encode(course))
      == course)
}

@Test func perGoalCampusHeuristicsAndReverseGeometryAreValid() throws {
  let course = try GilmorehillCourse.candidate()
  let navigator = try CourseNavigator(course: course, expected: course.reference)
  for goal in course.nodes {
    let table = try navigator.heuristics(to: goal.id)
    #expect(table.course == course.reference && table.goal == goal.id)
    #expect(table.values.map(\.nodeID) == course.nodes.map(\.id).sorted())
    #expect(table.values.first { $0.nodeID == goal.id }?.h == 0)
    #expect(table.values.allSatisfy { $0.h >= 0 })
    for source in course.nodes {
      let dijkstra = try navigator.search(from: source.id, to: goal.id, algorithm: .dijkstra)
      let aStar = try navigator.search(from: source.id, to: goal.id, algorithm: .aStar)
      let route = try #require(dijkstra.route)
      #expect(route.distanceMetres == aStar.route?.distanceMetres)
      #expect(table.values.first { $0.nodeID == source.id }!.h <= route.distanceMetres)
      #expect(route.polyline.first == source.coordinate && route.polyline.last == goal.coordinate)
    }
  }
  let first = course.edges[0]
  #expect(
    try navigator.search(from: first.to, to: first.from, algorithm: .aStar).route?.polyline
      == Array(first.polyline.reversed()))
}

private func editingCourse(_ edit: (inout [String: Any]) -> Void) throws -> CourseGraph {
  var json = try #require(
    JSONSerialization.jsonObject(with: ContractJSON.encoder().encode(GilmorehillCourse.candidate()))
      as? [String: Any])
  edit(&json)
  return try ContractJSON.decoder().decode(
    CourseGraph.self, from: JSONSerialization.data(withJSONObject: json))
}

@Test func malformedCourseDocumentsAreRejected() throws {
  let course = try GilmorehillCourse.candidate()
  #expect(
    throws: CourseError.incompatibleCourse(
      expected: .init(id: course.reference.id, version: "other"), actual: course.reference)
  ) {
    try CourseNavigator(course: course, expected: .init(id: course.reference.id, version: "other"))
  }
  let wrongCost = try editingCourse { json in
    var edges = json["edges"] as! [[String: Any]]
    edges[0]["costMetres"] = 1
    json["edges"] = edges
  }
  #expect(throws: CourseError.invalidMeasuredCost("jms-gardens")) {
    try CourseNavigator(course: wrongCost, expected: course.reference)
  }
  let wrongPolyline = try editingCourse { json in
    var edges = json["edges"] as! [[String: Any]]
    edges[0]["polyline"] = [["latitude": 0, "longitude": 0], ["latitude": 1, "longitude": 1]]
    json["edges"] = edges
  }
  #expect(throws: CourseError.invalidPolyline("jms-gardens")) {
    try CourseNavigator(course: wrongPolyline, expected: course.reference)
  }
  let wrongRoute = try editingCourse { json in
    var routes = json["routes"] as! [[String: Any]]
    routes[0]["edgeIDs"] = ["fraser-library", "jms-gardens"]
    json["routes"] = routes
  }
  #expect(throws: CourseError.invalidRoute(.standard)) {
    try CourseNavigator(course: wrongRoute, expected: course.reference)
  }
  let duplicateEdge = try editingCourse { json in
    var edges = json["edges"] as! [[String: Any]]
    edges.append(edges[0])
    json["edges"] = edges
  }
  #expect(throws: CourseError.duplicateEdge("jms-gardens")) {
    try CourseNavigator(course: duplicateEdge, expected: course.reference)
  }
  let invalidStops = try editingCourse { json in
    var stops = json["stops"] as! [String: Any]
    stops["finish"] = stops["start"]
    json["stops"] = stops
  }
  #expect(throws: CourseError.invalidStops) {
    try CourseNavigator(course: invalidStops, expected: course.reference)
  }
  let invalidPolicy = try editingCourse { json in
    var policy = json["arrivalPolicy"] as! [String: Any]
    policy["radiusMetres"] = -1
    json["arrivalPolicy"] = policy
  }
  #expect(throws: CourseError.invalidArrivalPolicy) {
    try CourseNavigator(course: invalidPolicy, expected: course.reference)
  }
}

@Test func geometryRejectsInvalidCoordinatesAndHandlesCoincidentPoints() throws {
  let point = Coordinate(latitude: 55.874, longitude: -4.292)
  #expect(try CourseGeometry.distance(from: point, to: point) == 0)
  #expect(throws: CourseError.invalidCoordinate) {
    try CourseGeometry.distance(from: .init(latitude: 91, longitude: 0), to: point)
  }
  #expect(throws: CourseError.invalidCoordinate) {
    try CourseGeometry.distance(from: point, to: .init(latitude: 0, longitude: .infinity))
  }
  #expect(throws: CourseError.invalidCoordinate) { try CourseGeometry.length(of: [point]) }
}
