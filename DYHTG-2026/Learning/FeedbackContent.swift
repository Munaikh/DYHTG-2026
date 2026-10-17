import AlgorithmArenaCore
import SwiftUI

struct FeedbackContent: View {
    let store: MatchStore
    let challenge: ChallengeDefinition

    private var opponentName: String {
        store.opponent?.nickname ?? "the other player"
    }

    var body: some View {
        List {
            switch store.feedback(for: challenge.id) {
            case .released(let feedback):
                released(feedback)
            default:
                pending
            }
        }
    }

    @ViewBuilder
    private var pending: some View {
        Section {
            if let submission = store.submission(for: challenge.id) {
                LabeledContent("Your answer", value: challenge.text(for: submission.answer))
            }
        } footer: {
            Text("Your answer is locked in.")
        }

        Section {
            HStack(spacing: 12) {
                ProgressView()
                Text("Waiting for \(opponentName) to answer")
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text("The result, points and replay unlock when both players have answered. You can keep walking; it will appear in Match Details.")
        }
    }

    @ViewBuilder
    private func released(_ feedback: ReleasedFeedback) -> some View {
        let mine = feedback.answers.first { $0.playerID == store.snapshot?.viewer.playerID }
        let theirs = feedback.answers.first { $0.playerID != store.snapshot?.viewer.playerID }

        Section {
            if let mine {
                ResultRow(isCorrect: mine.isCorrect, points: mine.awardedPoints, isScored: challenge.maximumPoints > 0)
                LabeledContent("Your answer", value: challenge.text(for: mine.answer))
                if !mine.isCorrect {
                    LabeledContent("Correct answer", value: challenge.text(for: feedback.correctAnswer))
                }
            }
            if let theirs {
                LabeledContent("\(opponentName)'s answer") {
                    Text("\(challenge.text(for: theirs.answer)), \(theirs.isCorrect ? "correct" : "incorrect")")
                }
            }
        }

        if challenge.slot == .learningCheck, let record = store.snapshot?.viewer.learningCheck {
            Section {
                LabeledContent("Next node", value: record.nodeCorrect ? "Correct" : "Incorrect")
                LabeledContent("Reason", value: record.reasonCorrect ? "Correct" : "Incorrect")
            } footer: {
                Text("Only your first attempt is recorded. It doesn't change the score.")
            }
        }

        Section("Why") {
            Text(feedback.explanation)
        }

        if !feedback.workedSteps.isEmpty {
            Section("Working") {
                ForEach(Array(feedback.workedSteps.enumerated()), id: \.offset) { _, step in
                    Text(step)
                        .monospacedDigit()
                }
            }
        }

        Section {
            NavigationLink("Replay the Search") {
                ReplayView(trace: feedback.trace, scenario: challenge.scenario)
            }
        } footer: {
            Text("Step through every node the search looked at, including the ones that don't end up on the route.")
        }
    }
}

private struct ResultRow: View {
    let isCorrect: Bool
    let points: Int
    let isScored: Bool

    var body: some View {
        HStack {
            Label(isCorrect ? "Correct" : "Incorrect", systemImage: isCorrect ? "checkmark" : "xmark")
                .font(.headline)
                .foregroundStyle(isCorrect ? .green : .red)
            Spacer()
            Text(isScored ? (points > 0 ? "+\(points) points" : "No points") : "Not scored")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
