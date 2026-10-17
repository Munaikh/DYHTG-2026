import AlgorithmArenaCore
import SwiftUI

struct Scoreboard: View {
    let viewer: PlayerProgress
    let opponent: PlayerProgress?

    var body: some View {
        HStack(spacing: 0) {
            ScoreColumn(name: "You", score: viewer.releasedScore, route: viewer.routeChoice)
            Divider()
            ScoreColumn(name: opponent?.nickname ?? "Other player", score: opponent?.releasedScore ?? 0, route: opponent?.routeChoice)
        }
        .padding(.vertical, 8)
    }
}

private struct ScoreColumn: View {
    let name: String
    let score: Int
    let route: RouteBranch?

    var body: some View {
        VStack(spacing: 2) {
            Text(score, format: .number)
                .font(.largeTitle.bold())
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(score)))
            Text(name)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(route.map { "of \($0 == .bonus ? 100 : 80) match points" } ?? "Match points · max 100")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(route.map { "\(score) of \($0 == .bonus ? 100 : 80) match points" } ?? "\(score) released match points; route not yet chosen")
    }
}
