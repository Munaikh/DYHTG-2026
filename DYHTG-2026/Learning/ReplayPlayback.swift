import AlgorithmArenaCore
import Observation
import SwiftUI

@MainActor
@Observable
final class ReplayPlayback {
    let trace: SearchTrace
    let scenario: GraphScenario
    private(set) var index = 0
    var isPlaying = false

    init(trace: SearchTrace, scenario: GraphScenario) {
        self.trace = trace
        self.scenario = scenario
    }

    var lastIndex: Int { max(trace.steps.count - 1, 0) }
    var step: SearchStep { trace.steps[index] }

    var presentation: SearchPresentation {
        var presentation = SearchPresentation(scenario: scenario, algorithm: trace.algorithm, state: step.state)
        if case .expand(let id) = step.event { presentation.current = id }
        if case .relax(let from, _, _, _, _) = step.event { presentation.current = from }
        if index == lastIndex, case .route(let nodes, _) = trace.outcome { presentation.routeNodes = nodes }
        return presentation
    }

    var highlightedEdge: (from: NodeID, to: NodeID)? {
        guard case .relax(let from, let to, _, _, _) = step.event else { return nil }
        return (from, to)
    }

    var description: String {
        StepDescription(scenario: scenario, algorithm: trace.algorithm).text(
            for: step,
            previous: index > 0 ? trace.steps[index - 1].state : nil,
            outcome: trace.outcome
        )
    }

    func move(to newIndex: Int, animated: Bool) {
        let clamped = min(max(newIndex, 0), lastIndex)
        guard clamped != index else { return }
        withAnimation(animated ? .easeInOut(duration: 0.3) : nil) {
            index = clamped
        }
    }

    func play(animated: Bool) async {
        guard isPlaying else { return }
        if index == lastIndex { move(to: 0, animated: animated) }
        while index < lastIndex {
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled, isPlaying else { return }
            move(to: index + 1, animated: animated)
        }
        isPlaying = false
    }
}

struct ReplayControls: View {
    @Bindable var playback: ReplayPlayback

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { Double(playback.index) },
                    set: { playback.move(to: Int($0.rounded()), animated: !reduceMotion) }
                ),
                in: 0...Double(max(playback.lastIndex, 1)),
                step: 1
            )
            .disabled(playback.lastIndex == 0)
            .accessibilityLabel("Step")
            .accessibilityValue("\(playback.index + 1) of \(playback.trace.steps.count)")

            HStack {
                control("Restart", systemImage: "backward.end.fill") { playback.move(to: 0, animated: !reduceMotion) }
                    .disabled(playback.index == 0)
                Spacer()
                control("Previous Step", systemImage: "backward.frame.fill") {
                    playback.move(to: playback.index - 1, animated: !reduceMotion)
                }
                .disabled(playback.index == 0)
                Spacer()
                control(playback.isPlaying ? "Pause" : "Play", systemImage: playback.isPlaying ? "pause.fill" : "play.fill") {
                    playback.isPlaying.toggle()
                }
                .font(.title)
                Spacer()
                control("Next Step", systemImage: "forward.frame.fill") {
                    playback.move(to: playback.index + 1, animated: !reduceMotion)
                }
                .disabled(playback.index == playback.lastIndex)
            }
            .font(.title3)
            .padding(.horizontal, 12)
        }
        .task(id: playback.isPlaying) {
            await playback.play(animated: !reduceMotion)
        }
    }

    private func control(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(title, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .frame(minWidth: 44, minHeight: 44)
    }
}
