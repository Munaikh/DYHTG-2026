import AlgorithmArenaCore
import CoreGraphics

enum NodeSearchState: Equatable {
    case undiscovered
    case frontier
    case current
    case settled
    case route

    var title: String {
        switch self {
        case .undiscovered: "Not discovered"
        case .frontier: "Frontier"
        case .current: "Expanding"
        case .settled: "Settled"
        case .route: "Final route"
        }
    }
}

struct NodeSummary: Identifiable {
    let id: NodeID
    let label: String
    let g: Int?
    let h: Int
    let predecessor: String?
    let state: NodeSearchState

    var f: Int? { g.map { $0 + h } }
}

struct SearchPresentation {
    let scenario: GraphScenario
    let algorithm: AlgorithmKind
    let state: SearchState
    var current: NodeID?
    var routeNodes: [NodeID] = []

    var routeEdges: Set<String> {
        Set(zip(routeNodes, routeNodes.dropFirst()).map { "\($0.0.rawValue)>\($0.1.rawValue)" })
    }

    func label(_ id: NodeID) -> String {
        scenario.nodes.first { $0.id == id }?.label ?? id.rawValue
    }

    var nodes: [NodeSummary] {
        scenario.nodes.sorted { $0.id < $1.id }.map { node in
            let cost = state.costs.first { $0.nodeID == node.id }
            return NodeSummary(
                id: node.id,
                label: node.label,
                g: cost?.g,
                h: cost?.h ?? node.heuristic,
                predecessor: cost?.predecessor.map(label),
                state: searchState(of: node.id)
            )
        }
    }

    func summary(_ id: NodeID) -> NodeSummary? {
        nodes.first { $0.id == id }
    }

    private func searchState(of id: NodeID) -> NodeSearchState {
        if routeNodes.contains(id) { return .route }
        if id == current { return .current }
        if state.settled.contains(id) { return .settled }
        if state.frontier.contains(id) { return .frontier }
        return .undiscovered
    }

    func costText(_ node: NodeSummary) -> String {
        let g = node.g.map(String.init) ?? "∞"
        switch algorithm {
        case .dijkstra:
            return "g \(g)"
        case .aStar:
            guard let f = node.f else { return "h \(node.h)" }
            return "\(g) + \(node.h) = \(f)"
        }
    }
}

struct GraphLayout {
    let positions: [NodeID: CGPoint]
    let rows: Int

    init(scenario: GraphScenario) {
        if !scenario.nodes.isEmpty, scenario.nodes.allSatisfy({ node in
            guard let point = node.position else { return false }
            return point.x.isFinite && point.y.isFinite && (0...1).contains(point.x) && (0...1).contains(point.y)
        }) {
            positions = Dictionary(uniqueKeysWithValues: scenario.nodes.map { node in
                (node.id, CGPoint(x: node.position!.x, y: node.position!.y))
            })
            rows = scenario.nodes.count > 5 ? 3 : 2
            return
        }
        var neighbours: [NodeID: Set<NodeID>] = [:]
        for edge in scenario.edges {
            neighbours[edge.from, default: []].insert(edge.to)
            neighbours[edge.to, default: []].insert(edge.from)
        }
        var depth: [NodeID: Int] = [scenario.source: 0]
        var queue = [scenario.source]
        while !queue.isEmpty {
            let node = queue.removeFirst()
            for next in (neighbours[node] ?? []).sorted() where depth[next] == nil {
                depth[next] = depth[node]! + 1
                queue.append(next)
            }
        }
        let deepest = depth.values.max() ?? 0
        for node in scenario.nodes where depth[node.id] == nil {
            depth[node.id] = deepest + 1
        }
        let columns = Dictionary(grouping: scenario.nodes.map(\.id)) { depth[$0]! }
        let lastColumn = max(columns.keys.max() ?? 0, 1)
        let rows = columns.values.map(\.count).max() ?? 1
        var positions: [NodeID: CGPoint] = [:]
        for (column, ids) in columns {
            let offset = CGFloat(rows - ids.count) / 2
            for (row, id) in ids.sorted().enumerated() {
                positions[id] = CGPoint(
                    x: CGFloat(column) / CGFloat(lastColumn),
                    y: (CGFloat(row) + 0.5 + offset) / CGFloat(rows)
                )
            }
        }
        self.positions = positions
        self.rows = rows
    }
}
