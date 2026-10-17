import AlgorithmArenaCore
import SwiftUI

struct Scoreboard: View {
    let viewer: PlayerProgress
    let opponent: PlayerProgress?

    var body: some View {
        HStack(spacing: 0) {
            ScoreColumn(name: "You", score: viewer.releasedScore)
            Divider()
            ScoreColumn(name: opponent?.nickname ?? "Other player", score: opponent?.releasedScore ?? 0)
        }
        .padding(.vertical, 8)
    }
}

private struct ScoreColumn: View {
    let name: String
    let score: Int

    var body: some View {
        VStack(spacing: 2) {
            Text(score, format: .number)
                .font(.largeTitle.bold())
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(score)))
            Text(name)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue("\(score) points")
    }
}
