import AlgorithmArenaCore
import SwiftUI

struct LabLegend: View {
    let isGraph: Bool

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { items }.fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 8) { items }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(.caption2.weight(.medium))
        .foregroundStyle(.secondary)
    }

    @ViewBuilder private var items: some View {
        Label {
            Text("Frontier")
        } icon: {
            Circle().strokeBorder(.teal, style: StrokeStyle(lineWidth: 2, dash: [2, 2])).frame(width: 10, height: 10)
        }
        Label {
            Text("Exploring")
        } icon: {
            Circle().fill(isGraph ? Color.accentColor : Color.orange).frame(width: 10, height: 10)
        }
        Label {
            Text("Settled")
        } icon: {
            Circle().fill(Color(.systemGray3)).frame(width: 10, height: 10)
        }
        Label {
            Text("Route")
        } icon: {
            Circle().strokeBorder(isGraph ? Color.accentColor : Color.teal, lineWidth: isGraph ? 2 : 5).frame(width: 10, height: 10)
        }
    }
}

struct LabStepCard: View {
    let experiment: CampusLabExperiment
    let playback: ReplayPlayback

    private var completed: Bool { playback.index == playback.lastIndex }
    private var label: (String, String) {
        switch playback.step.event {
        case .initial: ("Ready to explore", "sparkle.magnifyingglass")
        case .expand(let id): ("Explore \(letter(id))", "scope")
        case .relax(_, _, _, _, let accepted): (accepted ? "A better distance" : "Keep the current distance", accepted ? "arrow.triangle.branch" : "equal.circle")
        case .reachedGoal: ("Shortest route found", "checkmark.seal.fill")
        case .unreachable: ("No route remains", "point.topleft.down.to.point.bottomright.curvepath")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(label.0, systemImage: label.1)
                .font(.headline)
                .foregroundStyle(.teal)
            Text(explanation)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("visualize.explanation")
            HStack(spacing: 0) {
                metric("Expanded", value: String(playback.step.state.settled.count))
                Divider().frame(height: 30)
                metric("Frontier", value: String(playback.step.state.frontier.count))
                Divider().frame(height: 30)
                metric("Route cost", value: routeCost)
            }
            if !playback.step.state.frontier.isEmpty {
                Text("Next in line: \(playback.step.state.frontier.map(letter).joined(separator: " → "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
    }

    private var routeCost: String {
        guard completed else { return "—" }
        return CampusLabExperiment.routeCost(playback.trace).map { "\($0) m" } ?? "No route"
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .monospacedDigit()
                .minimumScaleFactor(0.8)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, title == "Expanded" ? 0 : 12)
        .accessibilityElement(children: .combine)
    }

    private func letter(_ id: NodeID) -> String { experiment.place(id)?.letter ?? id.rawValue }

    private var explanation: String {
        switch playback.step.event {
        case .initial:
            "\(letter(experiment.scenario.source)) starts at 0 m. Every other distance is unknown."
        case .expand(let id):
            expansionText(id)
        case .relax(let from, let to, let old, let candidate, let accepted):
            relaxationText(from: from, to: to, old: old, candidate: candidate, accepted: accepted)
        case .reachedGoal:
            if case .route(let nodes, let cost) = playback.trace.outcome {
                "\(nodes.map(letter).joined(separator: " → ")) costs \(cost) m through the connected walking network."
            } else {
                "The goal has been reached."
            }
        case .unreachable:
            "The frontier is empty. No open connection reaches \(letter(experiment.scenario.goal)). Reopen the path to try again."
        }
    }

    private func expansionText(_ id: NodeID) -> String {
        if id == experiment.scenario.goal {
            return "\(letter(id)) is the goal. Its cheapest route is settled; the search can stop."
        }
        guard let node = playback.presentation.summary(id), let g = node.g else {
            return "Check the paths leaving \(letter(id))."
        }
        if playback.trace.algorithm == .aStar {
            return "\(letter(id)) has the lowest f = g + h: \(g) + \(node.h) = \(g + node.h) m. Check its neighbours."
        }
        return "\(letter(id)) has the lowest known distance on the frontier: \(g) m. Check its neighbours."
    }

    private func relaxationText(from: NodeID, to: NodeID, old: Int?, candidate: Int, accepted: Bool) -> String {
        let base = playback.step.state.costs.first { $0.nodeID == from }?.g ?? 0
        let calculation = "\(letter(from)) → \(letter(to)): \(base) + \(candidate - base) = \(candidate) m."
        if accepted {
            return calculation + (old == nil ? " First route to \(letter(to)); add it to the frontier." : " Shorter than \(old!) m, so update its distance.")
        }
        if playback.step.state.settled.contains(to) {
            return calculation + " \(letter(to)) is already settled."
        }
        return calculation + " Keep the existing \(old.map(String.init) ?? "unknown") m distance."
    }
}

struct LabComparison: View {
    let experiment: CampusLabExperiment
    let isComplete: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Same journey. Different priorities.", systemImage: "arrow.left.arrow.right")
                .font(.subheadline.weight(.semibold))
            if isComplete {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                    GridRow {
                        Text("Algorithm")
                        Text("Expanded")
                        Text("Route cost")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    row("Dijkstra", trace: experiment.dijkstra)
                    row("A*", trace: experiment.aStar)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("visualize.comparison")
                Text(comparisonText + (experiment.heuristicScale < 0.99 ? " The distance estimate is scaled to stay a lower bound when map entrances differ from pins." : ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Finish the search to compare route cost and expanded nodes.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
    }

    private func row(_ title: String, trace: SearchTrace) -> some View {
        GridRow {
            Text(title).fontWeight(.semibold)
            Text(CampusLabExperiment.expandedCount(trace), format: .number)
            Text(CampusLabExperiment.routeCost(trace).map { "\($0) m" } ?? "No route")
        }
        .font(.subheadline)
        .monospacedDigit()
        .accessibilityElement(children: .combine)
    }

    private var comparisonText: String {
        let dijkstra = CampusLabExperiment.expandedCount(experiment.dijkstra)
        let aStar = CampusLabExperiment.expandedCount(experiment.aStar)
        if CampusLabExperiment.routeCost(experiment.dijkstra) == nil {
            return "Both exhaust their reachable frontier. A heuristic cannot create a missing connection."
        }
        if aStar == dijkstra {
            return "Equal work on this network. A* uses distance estimates; that does not guarantee fewer expansions on every journey."
        }
        if aStar < dijkstra {
            return "A* expanded \(dijkstra - aStar) fewer nodes here using distance estimates. Both found the same shortest cost."
        }
        return "Both found the same shortest cost. Expansion counts depend on the network, heuristic, and tie order."
    }
}

struct LabSearchTable: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let experiment: CampusLabExperiment
    let presentation: SearchPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(presentation.algorithm == .aStar ? "g = distance so far · h = remaining-distance estimate · f = g + h" : "g = best known distance from the start")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(experiment.places) { place in
                if let node = presentation.summary(place.id) {
                    let layout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                        : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
                    layout {
                        HStack(alignment: .top, spacing: 10) {
                            Text(place.letter)
                                .font(.caption.weight(.bold))
                                .frame(minWidth: 28, minHeight: 28)
                                .background(.teal.opacity(0.12), in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(place.name).font(.subheadline.weight(.medium))
                                Text(node.state.title).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(presentation.costText(node) + " m")
                            .font(.caption.monospacedDigit())
                            .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
