import AlgorithmArenaCore
import Foundation

struct CampusLabPlace: Identifiable {
    let id: NodeID
    let letter: String
    let name: String
    let coordinate: Coordinate
}

struct CampusLabExperiment {
    let graph: CampusRoutingGraph
    let scenario: GraphScenario
    let places: [CampusLabPlace]
    let dijkstra: SearchTrace
    let aStar: SearchTrace
    let previousRoute: WalkingRoute?
    let previousEdges: [CourseEdge]
    let closedPath: CourseEdge?
    let routeTitle: String
    let geometryNote: String
    let maxSnapDistanceMetres: Double
    let heuristicScale: Double

    init(
        from source: CampusMapPoint, to goal: CampusMapPoint,
        nodes: [CourseNode], paths: [PedestrianPath],
        closedPathID: EdgeID? = nil, unavailablePathCount: Int = 0, selectedPinGapMetres: Double = 0
    ) throws {
        let reference = CourseReference(id: "gilmorehill-mapkit", version: "walking-1")
        let sourceID = NodeID(rawValue: source.id)
        let goalID = NodeID(rawValue: goal.id)
        let baseline = try RoutedCampusGraph(
            reference: reference, nodes: nodes, paths: paths, source: sourceID, goal: goalID)
        let current = try RoutedCampusGraph(
            reference: reference, nodes: nodes,
            paths: paths.filter { $0.id != closedPathID }, source: sourceID, goal: goalID)
        let orderedNodes = nodes.sorted { $0.id < $1.id }
        let places = orderedNodes.enumerated().map { index, node in
            CampusLabPlace(id: node.id, letter: String(UnicodeScalar(65 + index)!),
                name: node.name, coordinate: node.coordinate)
        }
        // A staggered grid makes up to nine real-campus vertices legible without
        // changing any distance, heuristic, or MapKit edge geometry.
        let positions: [ScenarioPosition] = [
            .init(x: 0.08, y: 0.12), .init(x: 0.50, y: 0.12), .init(x: 0.92, y: 0.12),
            .init(x: 0.08, y: 0.50), .init(x: 0.50, y: 0.50), .init(x: 0.92, y: 0.50),
            .init(x: 0.08, y: 0.88), .init(x: 0.50, y: 0.88), .init(x: 0.92, y: 0.88),
        ]
        scenario = GraphScenario(
            id: current.graph.scenario.id,
            nodes: current.graph.scenario.nodes.map { node in
                let index = places.firstIndex { $0.id == node.id }!
                return .init(id: node.id, label: places[index].letter, heuristic: node.heuristic,
                    position: positions[index % positions.count])
            }, edges: current.graph.scenario.edges,
            source: current.graph.scenario.source, goal: current.graph.scenario.goal)
        graph = current.graph
        self.places = places
        dijkstra = try SearchEngine.search(scenario, algorithm: .dijkstra)
        aStar = try SearchEngine.search(scenario, algorithm: .aStar)
        let original = try baseline.graph.search(algorithm: .dijkstra)
        previousRoute = closedPathID == nil ? nil : original.route
        previousEdges = closedPathID == nil ? [] : Self.routeEdges(
            for: original.route?.nodeIDs ?? [], in: baseline.graph.edges)
        closedPath = baseline.graph.edges.first { $0.id == closedPathID }
        routeTitle = "\(source.name) → \(goal.name)"
        maxSnapDistanceMetres = max(current.maximumEndpointGapMetres, selectedPinGapMetres)
        heuristicScale = current.heuristicScale
        var notes = ["Apple Maps walking paths · shortest route through this learning network."]
        if maxSnapDistanceMetres >= 2 {
            notes.append("Pins connect at nearby mapped entrances, up to \(Int(ceil(maxSnapDistanceMetres))) m away. Gaps are not drawn or counted.")
        }
        if unavailablePathCount > 0 {
            notes.append("\(unavailablePathCount) unavailable \(unavailablePathCount == 1 ? "connection is" : "connections are") excluded.")
        }
        geometryNote = notes.joined(separator: " ")
    }

    func trace(for algorithm: AlgorithmKind) -> SearchTrace {
        algorithm == .dijkstra ? dijkstra : aStar
    }

    func place(_ id: NodeID) -> CampusLabPlace? { places.first { $0.id == id } }

    func edges(for nodes: [NodeID]) -> [CourseEdge] {
        Self.routeEdges(for: nodes, in: graph.edges)
    }

    private static func routeEdges(for nodes: [NodeID], in edges: [CourseEdge]) -> [CourseEdge] {
        zip(nodes, nodes.dropFirst()).compactMap { from, to in
            edges.filter {
                ($0.from == from && $0.to == to) || ($0.bidirectional && $0.from == to && $0.to == from)
            }.min { $0.costMetres == $1.costMetres ? $0.id < $1.id : $0.costMetres < $1.costMetres }
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
