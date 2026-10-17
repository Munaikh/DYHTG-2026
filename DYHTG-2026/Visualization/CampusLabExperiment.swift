import AlgorithmArenaCore
import Foundation

/// Prepared experiments use the same geographic network as the campus map.
/// Coordinates are an educational model; this feature never requests a location fix.
enum LabJourney: String, CaseIterable, Identifiable {
    case library
    case learningHub

    var id: String { rawValue }
    var title: String { self == .library ? "Library delivery" : "Back to the Hub" }
    var routeLabel: String { self == .library ? "JMS Hub → Library" : "Library → JMS Hub" }
    var source: NodeID { self == .library ? "01-jms" : "07-library" }
    var goal: NodeID { self == .library ? "07-library" : "01-jms" }
}

enum LabDisruption: String, CaseIterable, Identifiable {
    case none
    case detour
    case cutOff

    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: "All paths open"
        case .detour: "Gardens path closed"
        case .cutOff: "Library cut off"
        }
    }
    var closedEdgeID: EdgeID? {
        switch self {
        case .none: nil
        case .detour: "gardens-house"
        case .cutOff: "rejoin-fraser"
        }
    }
    var explanation: String {
        switch self {
        case .none: "Find the shortest route through the campus model."
        case .detour: "The B–C path is closed. Can the search find another way?"
        case .cutOff: "The E–F connection is closed. Watch what happens when no route remains."
        }
    }
}

struct CampusLabPlace: Identifiable {
    let id: NodeID
    let letter: String
    let name: String
    let coordinate: Coordinate
}

struct CampusLabExperiment {
    let journey: LabJourney
    let disruption: LabDisruption
    let graph: CampusRoutingGraph
    let scenario: GraphScenario
    let places: [CampusLabPlace]
    let dijkstra: SearchTrace
    let aStar: SearchTrace
    let previousRoute: WalkingRoute?
    let closedPath: CourseEdge?

    init(journey: LabJourney, disruption: LabDisruption) throws {
        let course = try GilmorehillCourse.candidate()
        guard let source = course.nodes.first(where: { $0.id == journey.source }),
              let goal = course.nodes.first(where: { $0.id == journey.goal }) else {
            throw CourseError.invalidStops
        }
        let originalNetwork = CampusPathNetwork(course: course)
        let network = CampusPathNetwork(
            reference: originalNetwork.reference,
            readiness: originalNetwork.readiness,
            paths: originalNetwork.paths.filter { $0.id != disruption.closedEdgeID }
        )
        let router = try CampusRouter(network: network, expected: course.reference)
        let graph = try router.graph(from: source.coordinate, to: goal.coordinate)
        let shortNames = ["JMS Hub", "Lilybank Gardens", "Lilybank House", "Hetherington", "Bute Gardens", "Fraser Building", "Library"]
        let places = course.nodes.sorted { $0.id < $1.id }.enumerated().map { index, node in
            CampusLabPlace(
                id: NodeID(rawValue: "junction:\(node.id.rawValue)"),
                letter: String(UnicodeScalar(65 + index)!), name: shortNames[index],
                coordinate: node.coordinate
            )
        }
        // A folded diagram keeps all seven vertices readable on a phone. Edge
        // costs and heuristic values remain the exact geographic model values.
        let positions: [ScenarioPosition] = [
            .init(x: 0.05, y: 0.12), .init(x: 0.42, y: 0.12), .init(x: 0.88, y: 0.12),
            .init(x: 0.42, y: 0.5), .init(x: 0.88, y: 0.5),
            .init(x: 0.49, y: 0.88), .init(x: 0.05, y: 0.88),
        ]
        let scenario = GraphScenario(
            id: ScenarioID(rawValue: "campus-lab-\(journey.rawValue)-\(disruption.rawValue)"),
            nodes: graph.scenario.nodes.map { node in
                let index = places.firstIndex { $0.id == node.id }
                return ScenarioNode(
                    id: node.id, label: index.map { places[$0].letter } ?? node.label,
                    heuristic: node.heuristic, position: index.map { positions[$0] }
                )
            },
            edges: graph.scenario.edges, source: graph.scenario.source, goal: graph.scenario.goal
        )
        let originalRouter = try CampusRouter(network: originalNetwork, expected: course.reference)
        let baseline = try originalRouter.graph(from: source.coordinate, to: goal.coordinate)
            .search(algorithm: .dijkstra)
        self.journey = journey
        self.disruption = disruption
        self.graph = graph
        self.scenario = scenario
        self.places = places
        self.dijkstra = try SearchEngine.search(scenario, algorithm: .dijkstra)
        self.aStar = try SearchEngine.search(scenario, algorithm: .aStar)
        self.previousRoute = disruption == .none ? nil : baseline.route
        self.closedPath = course.edges.first { $0.id == disruption.closedEdgeID }
    }

    func trace(for algorithm: AlgorithmKind) -> SearchTrace {
        algorithm == .dijkstra ? dijkstra : aStar
    }

    func place(_ id: NodeID) -> CampusLabPlace? { places.first { $0.id == id } }

    func edges(for nodes: [NodeID]) -> [CourseEdge] {
        zip(nodes, nodes.dropFirst()).compactMap { from, to in
            graph.edges.first {
                ($0.from == from && $0.to == to) || ($0.bidirectional && $0.from == to && $0.to == from)
            }
        }
    }

    static func expandedCount(_ trace: SearchTrace) -> Int {
        trace.steps.filter { if case .expand = $0.event { true } else { false } }.count
    }

    static func routeCost(_ trace: SearchTrace) -> Int? {
        guard case .route(_, let cost) = trace.outcome else { return nil }
        return cost
    }
}
