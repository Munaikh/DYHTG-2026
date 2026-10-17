import AlgorithmArenaCore
import SwiftUI

struct NodeTable: View {
    let presentation: SearchPresentation

    private var showsEstimate: Bool { presentation.algorithm == .aStar }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
            GridRow {
                Text("Node")
                Text("g")
                if showsEstimate {
                    Text("h")
                    Text("f")
                }
                Text("Via")
                Text("State")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)

            Divider()

            ForEach(presentation.nodes) { node in
                GridRow {
                    Text(node.label)
                        .fontWeight(.semibold)
                    Text(node.g.map(String.init) ?? "∞")
                    if showsEstimate {
                        Text(node.h, format: .number)
                        Text(node.f.map(String.init) ?? "-")
                    }
                    Text(node.predecessor ?? "-")
                    Text(node.state.title)
                        .foregroundStyle(node.state == .undiscovered ? .secondary : .primary)
                }
                .monospacedDigit()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Node \(node.label)")
                .accessibilityValue(accessibilityValue(node))
            }
        }
        .font(.subheadline)
        .padding(.vertical, 4)
    }

    private func accessibilityValue(_ node: NodeSummary) -> String {
        var parts = [node.state.title]
        parts.append(node.g.map { "g \($0)" } ?? "g unknown")
        if showsEstimate {
            parts.append("h \(node.h)")
            if let f = node.f { parts.append("f \(f)") }
        }
        if let predecessor = node.predecessor { parts.append("reached from \(predecessor)") }
        return parts.joined(separator: ", ")
    }
}
