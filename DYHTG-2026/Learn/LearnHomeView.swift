import AlgorithmArenaCore
import SwiftUI

struct LearnHomeView: View {
    @State private var progress = LearnProgressStore()
    @State private var path: [AlgorithmKind] = []

    private var completedCount: Int {
        AlgorithmKind.allCases.filter { progress.progress(for: $0).isComplete }.count
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    hero
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Your next move")
                                .font(.title2.bold())
                            Spacer()
                            Text("\(completedCount)/2 explored")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        lessonCard(.dijkstra, number: "01", title: "Dijkstra", subtitle: "Find the cheapest way.", detail: "Build a route, one smart choice at a time.", symbol: "point.topleft.down.to.point.bottomright.curvepath")
                        lessonCard(.aStar, number: "02", title: "A*", subtitle: "Give your search direction.", detail: "Use a good estimate to think ahead.", symbol: "sparkle.magnifyingglass")
                    }
                    Label("Your progress saves on this device.", systemImage: "checkmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 12)
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Learn")
            .navigationDestination(for: AlgorithmKind.self) { algorithm in
                LessonSessionView(algorithm: algorithm, progress: progress) { next in
                    path = [next]
                }
                // Replacing the last route keeps the same destination view type.
                // Give each algorithm its own identity so lesson/replay/selection
                // state cannot survive a Dijkstra → A* transition.
                .id(algorithm)
            }
        }
        .tint(LearnStyle.teal)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("SMALL MOVES. BIG IDEAS.", systemImage: "sparkles")
                    .font(.caption2.weight(.bold))
                    .tracking(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(LearnStyle.mint)
            Text("Think like\nan algorithm.")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.white)
            Text("Predict. Discover. Make it click.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
            HStack(spacing: 8) {
                heroPill("2 algorithms", symbol: "point.3.connected.trianglepath.dotted")
                heroPill("Learn by doing", symbol: "hand.tap")
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LearnStyle.ink, in: RoundedRectangle(cornerRadius: 28))
    }

    private func heroPill(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.white.opacity(0.1), in: Capsule())
    }

    private func lessonCard(_ algorithm: AlgorithmKind, number: String, title: String, subtitle: String, detail: String, symbol: String) -> some View {
        let record = progress.progress(for: algorithm)
        return Button {
            path.append(algorithm)
        } label: {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    Image(systemName: symbol)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(LearnStyle.teal)
                        .frame(width: 52, height: 52)
                        .background(LearnStyle.mint.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
                    Spacer()
                    Text(record.isComplete ? "EXPLORED" : "LESSON \(number)")
                        .font(.caption2.weight(.bold))
                        .tracking(1)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.title.bold())
                    Text(subtitle).font(.headline)
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                }
                HStack {
                    Text(record.isComplete ? "Revisit lesson" : record.hasStarted ? "Continue learning" : "Let's explore")
                        .font(.subheadline.weight(.bold))
                    Spacer()
                    Image(systemName: record.isComplete ? "checkmark.circle.fill" : "arrow.up.right")
                }
                .foregroundStyle(LearnStyle.teal)
                if record.hasStarted && !record.isComplete {
                    ProgressView(value: Double(record.phase), total: 4)
                        .tint(LearnStyle.teal)
                        .accessibilityLabel("Lesson progress")
                        .accessibilityValue("\(record.phase) of 4 steps complete")
                }
            }
            .learnCard()
            .contentShape(RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("learn.lesson.\(algorithm.rawValue)")
    }
}
