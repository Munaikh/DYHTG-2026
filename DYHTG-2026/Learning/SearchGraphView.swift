import AlgorithmArenaCore
import SwiftUI

struct SearchGraphView: View {
    let presentation: SearchPresentation
    var selectable: [NodeID] = []
    var selection: NodeID?
    var highlightedEdge: (from: NodeID, to: NodeID)?
    var highlightedEdgeCost: Int?
    var onSelect: (NodeID) -> Void = { _ in }
    private let nodeSize: CGFloat = 46

    var body: some View {
        let layout = GraphLayout(scenario: presentation.scenario)
        let height: CGFloat = max(layout.rows > 2 ? 370 : 300, CGFloat((presentation.nodes.count + 2) / 3) * 110 + 40)
        GeometryReader { proxy in
            let drawing = GraphDrawing(layout: layout, scenario: presentation.scenario,
                                       size: proxy.size, isAStar: presentation.algorithm == .aStar,
                                       isIndoorTraversal: presentation.indoorCostDisplay == .breadthFirst
                                           || presentation.indoorCostDisplay == .depthFirst)
            ZStack {
                ForEach(Array(presentation.scenario.edges.enumerated()), id: \.offset) { index, edge in
                    if let path = drawing.edges[index] {
                        EdgeView(path: path,
                                 directed: !edge.bidirectional, emphasis: emphasis(for: edge, at: index),
                                 nodeRadius: nodeSize / 2)
                    }
                }
                ForEach(Array(presentation.scenario.edges.enumerated()), id: \.offset) { index, edge in
                    if let point = drawing.edgeLabels[index] {
                        EdgeCostLabel(cost: edge.cost, highlighted: emphasis(for: edge, at: index) != .normal)
                            .position(point)
                    }
                }
                ForEach(presentation.nodes) { node in
                    if let point = drawing.points[node.id] {
                        NodeView(node: node, caption: presentation.costText(node),
                                 isSource: node.id == presentation.scenario.source,
                                 isGoal: node.id == presentation.scenario.goal,
                                 isSelected: node.id == selection, size: nodeSize)
                            .position(point)
                            .onTapGesture {
                                if selectable.contains(node.id) { onSelect(node.id) }
                            }
                            .accessibilityAddTraits(selectable.contains(node.id) ? .isButton : [])
                        NodeCostLabel(node: node, caption: presentation.costText(node),
                                      isAStar: presentation.algorithm == .aStar)
                            .position(drawing.captions[node.id] ?? point)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Search graph")
    }

    private func emphasis(for edge: ScenarioEdge, at index: Int) -> EdgeView.Emphasis {
        let peers = presentation.scenario.edges.indices.filter { other in
            let candidate = presentation.scenario.edges[other]
            return (candidate.from == edge.from && candidate.to == edge.to)
                || (candidate.bidirectional && edge.bidirectional && candidate.from == edge.to && candidate.to == edge.from)
        }
        let cheapest = peers.min {
            let first = presentation.scenario.edges[$0].cost, second = presentation.scenario.edges[$1].cost
            return first == second ? $0 < $1 : first < second
        }
        let key = "\(edge.from.rawValue)>\(edge.to.rawValue)"
        let reverse = "\(edge.to.rawValue)>\(edge.from.rawValue)"
        if cheapest == index,
           presentation.routeEdges.contains(key) || (edge.bidirectional && presentation.routeEdges.contains(reverse)) {
            return .route
        }
        if let highlightedEdge,
           (highlightedEdge.from == edge.from && highlightedEdge.to == edge.to)
            || (edge.bidirectional && highlightedEdge.from == edge.to && highlightedEdge.to == edge.from) {
            if let highlightedEdgeCost {
                return edge.cost == highlightedEdgeCost
                    && peers.first(where: { presentation.scenario.edges[$0].cost == highlightedEdgeCost }) == index ? .active : .normal
            }
            return .active
        }
        return .normal
    }
}

/// Circle centers anchor the edges; captions never shift their endpoints.
/// Normalizing authored positions uses the full available card width.
private struct GraphDrawing {
    let points: [NodeID: CGPoint]
    let captions: [NodeID: CGPoint]
    let edgeLabels: [Int: CGPoint]
    let edges: [Int: GraphEdgePath]

    init(layout: GraphLayout, scenario: GraphScenario, size: CGSize, isAStar: Bool, isIndoorTraversal: Bool) {
        let xs = layout.positions.values.map(\.x), ys = layout.positions.values.map(\.y)
        let minX = xs.min() ?? 0, maxX = xs.max() ?? 1
        let minY = ys.min() ?? 0, maxY = ys.max() ?? 1
        let insetX: CGFloat = 28
        let insetY: CGFloat = isAStar ? 68 : 54
        let points = layout.positions.mapValues { unit in
            CGPoint(x: insetX + (unit.x - minX) / max(maxX - minX, 0.01) * max(size.width - 2 * insetX, 1),
                    y: minY == maxY ? size.height / 2 : insetY + (unit.y - minY) / (maxY - minY) * (size.height - 2 * insetY))
        }
        let captionSize = CGSize(width: isAStar ? 96 : isIndoorTraversal ? 64 : 48, height: isAStar ? 38 : 24)
        var captions = points.mapValues { point in
            CGPoint(x: min(max(point.x, captionSize.width / 2), size.width - captionSize.width / 2),
                    y: point.y + (point.y < size.height * 0.4 ? -1 : 1) * (28 + captionSize.height / 2))
        }
        let nodeBoxes = points.values.map { CGRect(x: $0.x - 29, y: $0.y - 29, width: 58, height: 58) }
        func captionBox(_ center: CGPoint) -> CGRect {
            CGRect(x: center.x - captionSize.width / 2 - 3, y: center.y - captionSize.height / 2 - 3,
                   width: captionSize.width + 6, height: captionSize.height + 6)
        }
        let ids = points.keys.sorted()
        let captionBoxes = ids.compactMap { captions[$0].map(captionBox) }
        let hasCaptionCollision = captionBoxes.indices.contains { index in
            captionBoxes.indices.contains { $0 > index && captionBoxes[index].intersects(captionBoxes[$0]) }
        }
        // At narrow widths, adjacent A* captions can meet. For small diagrams,
        // choose above/below placements together so fixing one label cannot
        // push the next into a dead end. Uncrowded layouts stay exactly as authored.
        if hasCaptionCollision && ids.count <= 10 {
            let preferred = captions
            var best = captions
            var bestScore = Int.max
            let labelBounds = CGRect(origin: .zero, size: size).insetBy(dx: -3, dy: -3)
            func arrange(_ index: Int, _ chosen: [NodeID: CGPoint], _ boxes: [CGRect], _ score: Int) {
                guard score < bestScore else { return }
                guard index < ids.count else { best = chosen; bestScore = score; return }
                let id = ids[index]
                guard let point = points[id], let first = preferred[id] else { return }
                let opposite = CGPoint(x: first.x, y: 2 * point.y - first.y)
                for (offset, center) in [first, opposite].enumerated() {
                    let box = captionBox(center)
                    let penalty = (labelBounds.contains(box) ? 0 : 10_000)
                        + nodeBoxes.filter { $0.intersects(box) }.count * 10_000
                        + boxes.filter { $0.intersects(box) }.count * 1_000 + offset
                    var next = chosen
                    next[id] = center
                    arrange(index + 1, next, boxes + [box], score + penalty)
                }
            }
            arrange(0, [:], [], 0)
            captions = best
        }
        var occupied = nodeBoxes
        occupied += captions.values.map { CGRect(x: $0.x - captionSize.width / 2 - 3, y: $0.y - captionSize.height / 2 - 3,
                                                 width: captionSize.width + 6, height: captionSize.height + 6) }
        var labels: [Int: CGPoint] = [:]
        let bounds = CGRect(origin: .zero, size: size)
        var edges: [Int: GraphEdgePath] = [:]
        for (index, edge) in scenario.edges.enumerated() {
            guard let from = points[edge.from], let to = points[edge.to] else { continue }
            let others = points.filter { $0.key != edge.from && $0.key != edge.to }.map(\.value)
            let direct = GraphEdgePath(from: from, to: to)
            let blocked = others.contains { center in
                (1..<24).contains { step in direct.point(CGFloat(step) / 24).distance(to: center) < 38 }
            }
            let parallel = scenario.edges.indices.filter { other in
                let candidate = scenario.edges[other]
                return (candidate.from == edge.from && candidate.to == edge.to)
                    || (candidate.from == edge.to && candidate.to == edge.from)
            }
            if blocked || parallel.count > 1 {
                let middle = direct.point(0.5), normal = direct.normal(0.5)
                let offsets: [CGFloat]
                if parallel.count > 1 {
                    let rank = CGFloat(parallel.firstIndex(of: index)!) - CGFloat(parallel.count - 1) / 2
                    let offset = rank * 100 * (edge.from < edge.to ? 1 : -1)
                    offsets = offset == 0 ? [0, 25, -25] : [offset, offset * 1.5, offset * 2]
                } else {
                    offsets = [-100, 100, -150, 150]
                }
                let candidates = offsets.map { offset in
                    GraphEdgePath(from: from, to: to,
                                  control: CGPoint(x: middle.x + normal.x * offset, y: middle.y + normal.y * offset))
                }
                func score(_ path: GraphEdgePath) -> Int {
                    (1..<24).reduce(0) { result, step in
                        let point = path.point(CGFloat(step) / 24)
                        return result + others.filter { point.distance(to: $0) < 38 }.count * 100
                            + (bounds.insetBy(dx: 8, dy: 8).contains(point) ? 0 : 1000)
                            + captions.values.filter { point.distance(to: $0) < 24 }.count
                    }
                }
                edges[index] = candidates.enumerated().min {
                    score($0.element) * 10 + $0.offset < score($1.element) * 10 + $1.offset
                }?.element ?? direct
            } else {
                edges[index] = direct
            }
        }
        for (index, edge) in scenario.edges.enumerated() {
            guard let path = edges[index] else { continue }
            let width = CGFloat(String(edge.cost).count) * 9 + 14
            var candidates: [CGPoint] = []
            let fractions: [CGFloat] = [0.5, 0.4, 0.6]
            let offsets: [CGFloat] = [-16, 16, -28, 28]
            for fraction in fractions {
                for offset in offsets {
                    let point = path.point(fraction), normal = path.normal(fraction)
                    let x = point.x + normal.x * offset
                    let y = point.y + normal.y * offset
                    candidates.append(CGPoint(x: x, y: y))
                }
            }
            func box(_ point: CGPoint) -> CGRect {
                CGRect(x: point.x - width / 2, y: point.y - 12, width: width, height: 24)
            }
            let best = candidates.enumerated().min { lhs, rhs in
                func score(_ item: (offset: Int, element: CGPoint)) -> Int {
                    let rect = box(item.element)
                    let crossedEdges = edges.filter { otherIndex, otherPath in
                        guard otherIndex != index else { return false }
                        return (0...24).contains { step in
                            rect.insetBy(dx: -2, dy: -2).contains(otherPath.point(CGFloat(step) / 24))
                        }
                    }.count
                    return (bounds.contains(rect) ? 0 : 10_000)
                        + occupied.filter { $0.intersects(rect) }.count * 1_000
                        + crossedEdges * 100 + item.offset
                }
                return score(lhs) < score(rhs)
            }?.element ?? path.point(0.5)
            labels[index] = best
            occupied.append(box(best).insetBy(dx: -3, dy: -3))
        }
        self.points = points
        self.captions = captions
        self.edgeLabels = labels
        self.edges = edges
    }
}

private struct GraphEdgePath {
    let from: CGPoint
    let to: CGPoint
    var control: CGPoint?

    func point(_ t: CGFloat) -> CGPoint {
        guard let control else {
            return CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
        }
        let u = 1 - t
        return CGPoint(x: u * u * from.x + 2 * u * t * control.x + t * t * to.x,
                       y: u * u * from.y + 2 * u * t * control.y + t * t * to.y)
    }

    func direction(_ t: CGFloat) -> CGPoint {
        let dx: CGFloat, dy: CGFloat
        if let control {
            dx = (1 - t) * (control.x - from.x) + t * (to.x - control.x)
            dy = (1 - t) * (control.y - from.y) + t * (to.y - control.y)
        } else {
            dx = to.x - from.x
            dy = to.y - from.y
        }
        let length = max(hypot(dx, dy), 1)
        return CGPoint(x: dx / length, y: dy / length)
    }

    func normal(_ t: CGFloat) -> CGPoint {
        let direction = direction(t)
        return CGPoint(x: -direction.y, y: direction.x)
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat { hypot(x - other.x, y - other.y) }
}

private struct EdgeView: View {
    enum Emphasis { case normal, active, route }
    let path: GraphEdgePath
    let directed: Bool
    let emphasis: Emphasis
    let nodeRadius: CGFloat

    private var color: Color {
        emphasis == .normal ? Color(.secondaryLabel) : Color.accentColor
    }

    var body: some View {
        let first = path.direction(0), unit = path.direction(1)
        let start = CGPoint(x: path.from.x + first.x * (nodeRadius + 3), y: path.from.y + first.y * (nodeRadius + 3))
        let end = CGPoint(x: path.to.x - unit.x * (nodeRadius + 5), y: path.to.y - unit.y * (nodeRadius + 5))
        let base = CGPoint(x: end.x - unit.x * 10, y: end.y - unit.y * 10)
        ZStack {
            Path { stroke in
                stroke.move(to: start)
                if let control = path.control {
                    stroke.addQuadCurve(to: directed ? base : end, control: control)
                } else {
                    stroke.addLine(to: directed ? base : end)
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: emphasis == .normal ? 2.2 : 3.2, lineCap: .round))
            if directed {
                Path { path in
                    path.move(to: end)
                    path.addLine(to: CGPoint(x: base.x - unit.y * 5, y: base.y + unit.x * 5))
                    path.addLine(to: CGPoint(x: base.x + unit.y * 5, y: base.y - unit.x * 5))
                    path.closeSubpath()
                }
                .fill(color)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct EdgeCostLabel: View {
    let cost: Int
    let highlighted: Bool

    var body: some View {
        Text(cost, format: .number)
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(highlighted ? Color.accentColor : Color.primary)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 7))
            .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1) }
            .accessibilityHidden(true)
    }
}

private struct NodeCostLabel: View {
    let node: NodeSummary
    let caption: String
    let isAStar: Bool

    var body: some View {
        VStack(spacing: 2) {
            if isAStar {
                Text("g \(node.g.map(String.init) ?? "∞") · h \(node.h)")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                Text("f \(node.f.map(String.init) ?? "∞")")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            } else {
                Text(caption)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
        }
        .monospacedDigit()
        .foregroundStyle(.primary)
        .fixedSize()
        .padding(.horizontal, 3).padding(.vertical, 2)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 5))
    }
}

private struct NodeView: View {
    let node: NodeSummary
    let caption: String
    let isSource: Bool
    let isGoal: Bool
    let isSelected: Bool
    let size: CGFloat

    var body: some View {
        ZStack {
            shape
            Text(node.label)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .lineLimit(1).minimumScaleFactor(0.65).padding(.horizontal, 3)
                .foregroundStyle(node.state == .current ? Color.white : Color.primary)
        }
        .frame(width: size, height: size)
        .overlay {
            if isSelected { Circle().stroke(Color.accentColor, lineWidth: 2).padding(-5) }
        }
        .contentShape(Circle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isSource ? "Node \(node.label), start" : isGoal ? "Node \(node.label), goal" : "Node \(node.label)")
        .accessibilityValue("\(node.state.title), \(caption)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder private var shape: some View {
        switch node.state {
        case .undiscovered:
            Circle().fill(Color(.secondarySystemGroupedBackground))
                .overlay(Circle().strokeBorder(Color(.secondaryLabel), lineWidth: 2))
        case .frontier:
            Circle().fill(Color(.secondarySystemGroupedBackground))
                .overlay(Circle().strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, dash: [5, 3])))
        case .current:
            // The app tint becomes mint in dark mode. A fixed teal fill keeps
            // the white node label readable in every learning/duel/map context.
            Circle().fill(ArenaPalette.teal)
        case .settled:
            Circle().fill(Color(.systemGray5))
                .overlay(Circle().strokeBorder(Color(.secondaryLabel), lineWidth: 1.5))
        case .route:
            Circle().fill(Color(.secondarySystemGroupedBackground))
                .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 3))
        }
    }
}
