import AlgorithmArenaCore
import SwiftUI

struct ReplayView: View {
    let trace: SearchTrace
    let scenario: GraphScenario

    @State private var index = 0
    @State private var isPlaying = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var lastIndex: Int { max(trace.steps.count - 1, 0) }
    private var step: SearchStep { trace.steps[index] }

    private var presentation: SearchPresentation {
        var presentation = SearchPresentation(scenario: scenario, algorithm: trace.algorithm, state: step.state)
        if case .expand(let id) = step.event { presentation.current = id }
        if index == lastIndex, case .route(let nodes, _) = trace.outcome { presentation.routeNodes = nodes }
        return presentation
    }

    private var highlightedEdge: (from: NodeID, to: NodeID)? {
        guard case .relax(let from, let to, _, _, _) = step.event else { return nil }
        return (from, to)
    }

    var body: some View {
        List {
            Section {
                Text(StepDescription(scenario: scenario, algorithm: trace.algorithm).text(
                    for: step,
                    previous: index > 0 ? trace.steps[index - 1].state : nil,
                    outcome: trace.outcome
                ))
                .contentTransition(.opacity)
            } header: {
                Text("Step \(index + 1) of \(trace.steps.count)")
            }

            SearchStateSection(presentation: presentation, highlightedEdge: highlightedEdge) {
                EmptyView()
            }

            if !step.state.frontier.isEmpty {
                Section {
                    Text(frontierText)
                        .monospacedDigit()
                } header: {
                    Text("Frontier")
                } footer: {
                    Text(trace.algorithm == .aStar
                        ? "Ordered by f = g + h, lowest first. Ties go to the earlier node."
                        : "Ordered by g, lowest first. Ties go to the earlier node.")
                }
            }
        }
        .navigationTitle("Replay")
        .navigationBarTitleDisplayMode(.inline)
        .bottomActions {
            controls
        }
        .task(id: isPlaying) {
            guard isPlaying else { return }
            if index == lastIndex { index = 0 }
            while index < lastIndex {
                try? await Task.sleep(for: .seconds(1.6))
                guard !Task.isCancelled else { return }
                move(to: index + 1)
            }
            isPlaying = false
        }
        .onDisappear { isPlaying = false }
    }

    private var frontierText: String {
        let summaries = presentation
        return step.state.frontier.map { id in
            guard let node = summaries.summary(id) else { return id.rawValue }
            let name = trace.algorithm == .aStar ? "f" : "g"
            let priority = trace.algorithm == .aStar ? node.f : node.g
            return "\(node.label) (\(name) = \(priority.map(String.init) ?? "∞"))"
        }
        .joined(separator: ", ")
    }

    private var controls: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(get: { Double(index) }, set: { move(to: Int($0.rounded())) }),
                in: 0...Double(max(lastIndex, 1)),
                step: 1
            )
            .disabled(lastIndex == 0)
            .accessibilityLabel("Step")
            .accessibilityValue("\(index + 1) of \(trace.steps.count)")

            HStack {
                control("Restart", systemImage: "backward.end.fill") { move(to: 0) }
                    .disabled(index == 0)
                Spacer()
                control("Previous Step", systemImage: "backward.frame.fill") { move(to: index - 1) }
                    .disabled(index == 0)
                Spacer()
                control(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill") {
                    isPlaying.toggle()
                }
                .font(.title)
                Spacer()
                control("Next Step", systemImage: "forward.frame.fill") { move(to: index + 1) }
                    .disabled(index == lastIndex)
            }
            .font(.title3)
            .padding(.horizontal, 12)
        }
    }

    private func control(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(title, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .frame(minWidth: 44, minHeight: 44)
    }

    private func move(to newIndex: Int) {
        let clamped = min(max(newIndex, 0), lastIndex)
        guard clamped != index else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
            index = clamped
        }
    }
}
