import AlgorithmArenaCore
import SwiftUI

struct LessonTraceView: View {
    @State private var playback: ReplayPlayback

    init(lesson: PublicLesson) {
        _playback = State(initialValue: ReplayPlayback(trace: lesson.trace, scenario: lesson.scenario))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("LIVE SEARCH", systemImage: "waveform.path")
                        .font(.caption2.weight(.bold))
                        .tracking(1)
                        .foregroundStyle(LearnStyle.teal)
                    Spacer()
                    Text("\(playback.index + 1) / \(playback.trace.steps.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                SearchGraphView(presentation: playback.presentation, highlightedEdge: playback.highlightedEdge)
                ReplayControls(playback: playback)
            }
            .learnCard()
            VStack(alignment: .leading, spacing: 10) {
                Text("What's happening")
                    .font(.headline)
                Text(playback.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                    .accessibilityIdentifier("learn.replay.description")
            }
            .learnCard()
            if !playback.step.state.frontier.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Next in line")
                        .font(.headline)
                    Text(frontierDescription)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(LearnStyle.teal)
                    Text(playback.trace.algorithm == .aStar
                         ? "Lowest f first. Equal priorities use node ID order."
                         : "Lowest g first. Equal costs use node ID order.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .learnCard()
            }
            DisclosureGroup("All node values") {
                LessonNodeValues(presentation: playback.presentation)
                    .padding(.top, 10)
            }
            .font(.subheadline.weight(.semibold))
            .learnCard()
        }
        .onDisappear { playback.isPlaying = false }
    }

    private var frontierDescription: String {
        playback.step.state.frontier.compactMap { id in
            guard let node = playback.presentation.summary(id) else { return nil }
            let value = playback.trace.algorithm == .aStar ? node.f : node.g
            return "\(node.label) (\(value.map(String.init) ?? "∞"))"
        }
        .joined(separator: " → ")
    }
}
