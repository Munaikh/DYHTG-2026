import AlgorithmArenaCore
import SwiftUI

struct SearchGraphView: View {
    let presentation: SearchPresentation
    var selectable: [NodeID] = []
    var selection: NodeID?
    var highlightedEdge: (from: NodeID, to: NodeID)?
    var onSelect: (NodeID) -> Void = { _ in }

    private let nodeSize: CGFloat = 44
    private let inset = CGSize(width: 44, height: 12)

    var body: some View {
        let layout = GraphLayout(scenario: presentation.scenario)
        let height = CGFloat(layout.rows) * 96 + 24

        GeometryReader { proxy in
            let frame = proxy.size
            ZStack {
                ForEach(Array(presentation.scenario.edges.enumerated()), id: \.offset) { _, edge in
                    if let from = layout.positions[edge.from], let to = layout.positions[edge.to] {
                        EdgeView(
                            from: point(from, in: frame),
                            to: point(to, in: frame),
                            cost: edge.cost,
                            directed: !edge.bidirectional,
                            emphasis: emphasis(for: edge),
                            nodeRadius: nodeSize / 2
                        )
                    }
                }
                ForEach(presentation.nodes) { node in
                    if let position = layout.positions[node.id] {
                        NodeView(
                            node: node,
                            caption: presentation.costText(node),
                            isSource: node.id == presentation.scenario.source,
                            isGoal: node.id == presentation.scenario.goal,
                            isSelected: node.id == selection,
                            size: nodeSize
                        )
                        .position(point(position, in: frame))
                        .onTapGesture {
                            if selectable.contains(node.id) { onSelect(node.id) }
                        }
                        .accessibilityAddTraits(selectable.contains(node.id) ? .isButton : [])
                        .accessibilityAction {
                            if selectable.contains(node.id) { onSelect(node.id) }
                        }
                    }
                }
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Search graph")
    }

    private func point(_ unit: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: inset.width + unit.x * (size.width - inset.width * 2),
            y: inset.height + unit.y * (size.height - inset.height * 2) - 10
        )
    }

    private func emphasis(for edge: ScenarioEdge) -> EdgeView.Emphasis {
        let key = "\(edge.from.rawValue)>\(edge.to.rawValue)"
        let reverse = "\(edge.to.rawValue)>\(edge.from.rawValue)"
        if presentation.routeEdges.contains(key) || (edge.bidirectional && presentation.routeEdges.contains(reverse)) {
            return .route
        }
        if let highlightedEdge, highlightedEdge.from == edge.from, highlightedEdge.to == edge.to {
            return .active
        }
        return .normal
    }
}

private struct EdgeView: View {
    enum Emphasis {
        case normal
        case active
        case route
    }

    let from: CGPoint
    let to: CGPoint
    let cost: Int
    let directed: Bool
    let emphasis: Emphasis
    let nodeRadius: CGFloat

    private var color: Color {
        switch emphasis {
        case .normal: Color(.tertiaryLabel)
        case .active, .route: .accentColor
        }
    }

    var body: some View {
        let length = max(hypot(to.x - from.x, to.y - from.y), 1)
        let unit = CGPoint(x: (to.x - from.x) / length, y: (to.y - from.y) / length)
        let start = CGPoint(x: from.x + unit.x * nodeRadius, y: from.y + unit.y * nodeRadius)
        let end = CGPoint(x: to.x - unit.x * (nodeRadius + 2), y: to.y - unit.y * (nodeRadius + 2))

        ZStack {
            Path { path in
                path.move(to: start)
                path.addLine(to: end)
                if directed {
                    let wing: CGFloat = 8
                    let angle = atan2(unit.y, unit.x)
                    for offset in [CGFloat.pi * 0.84, -CGFloat.pi * 0.84] {
                        path.move(to: end)
                        path.addLine(to: CGPoint(x: end.x + cos(angle + offset) * wing, y: end.y + sin(angle + offset) * wing))
                    }
                }
            }
            .stroke(
                color,
                style: StrokeStyle(
                    lineWidth: emphasis == .route ? 3 : 1.5,
                    lineCap: .round,
                    dash: emphasis == .active ? [5, 4] : []
                )
            )

            Text(cost, format: .number)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(emphasis == .normal ? Color.secondary : Color.accentColor)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 4))
                .position(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
        }
        .accessibilityHidden(true)
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
        VStack(spacing: 4) {
            ZStack {
                shape
                Text(node.label)
                    .font(.headline)
                    .foregroundStyle(node.state == .current ? Color(uiColor: .systemBackground) : node.state == .undiscovered ? Color.secondary : Color.primary)
            }
            .frame(width: size, height: size)
            .overlay {
                if isSelected {
                    Circle()
                        .stroke(Color.accentColor, lineWidth: 2)
                        .padding(-5)
                }
            }

            Text(caption)
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityValue("\(node.state.title), \(caption)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var accessibilityTitle: String {
        if isSource { return "Node \(node.label), start" }
        if isGoal { return "Node \(node.label), goal" }
        return "Node \(node.label)"
    }

    @ViewBuilder
    private var shape: some View {
        switch node.state {
        case .undiscovered:
            Circle()
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay(Circle().strokeBorder(Color(.tertiaryLabel), lineWidth: 1.5))
        case .frontier:
            Circle()
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay(Circle().strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [4, 3])))
        case .current:
            Circle()
                .fill(Color.accentColor)
        case .settled:
            Circle()
                .fill(Color(.systemGray5))
                .overlay(Circle().strokeBorder(Color(.systemGray3), lineWidth: 1))
        case .route:
            Circle()
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 3))
        }
    }
}
