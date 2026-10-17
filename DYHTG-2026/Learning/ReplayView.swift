import AlgorithmArenaCore
import SwiftUI

struct ReplayView: View {
    @State private var playback: ReplayPlayback

    init(trace: SearchTrace, scenario: GraphScenario) {
        _playback = State(initialValue: ReplayPlayback(trace: trace, scenario: scenario))
    }

    var body: some View {
        List {
            Section {
                Text(playback.description)
                    .contentTransition(.opacity)
            } header: {
                Text("Step \(playback.index + 1) of \(playback.trace.steps.count)")
            }

            SearchStateSection(presentation: playback.presentation, highlightedEdge: playback.highlightedEdge) {
                EmptyView()
            }

            if !playback.step.state.frontier.isEmpty {
                Section {
                    Text(frontierText)
                        .monospacedDigit()
                } header: {
                    Text("Frontier")
                } footer: {
                    Text(playback.trace.algorithm == .aStar
                        ? "Ordered by f = g + h, lowest first. Ties go to the earlier node."
                        : "Ordered by g, lowest first. Ties go to the earlier node.")
                }
            }
        }
        .navigationTitle("Replay")
        .navigationBarTitleDisplayMode(.inline)
        .bottomActions {
            ReplayControls(playback: playback)
        }
        .onDisappear { playback.isPlaying = false }
    }

    private var frontierText: String {
        let presentation = playback.presentation
        return playback.step.state.frontier.map { id in
            guard let node = presentation.summary(id) else { return id.rawValue }
            let name = playback.trace.algorithm == .aStar ? "f" : "g"
            let priority = playback.trace.algorithm == .aStar ? node.f : node.g
            return "\(node.label) (\(name) = \(priority.map(String.init) ?? "∞"))"
        }
        .joined(separator: ", ")
    }
}
