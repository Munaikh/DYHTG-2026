import AlgorithmArenaCore
import SwiftUI

struct MatchView: View {
    @Bindable var store: MatchStore

    @State private var openChallenge: ChallengeRoute?
    @State private var isConfirmingLeave = false

    var body: some View {
        NavigationStack {
            if let room = store.snapshot?.room, let viewer = store.viewer {
                List {
                    if store.isReconnecting {
                        ReconnectingRow()
                    }

                    Section("Now") {
                        StageRow(stage: viewer.stage, course: store.course)
                    }

                    Section {
                        Scoreboard(viewer: viewer, opponent: store.opponent)
                    } header: {
                        Text("Score")
                    } footer: {
                        Text(pointsSummary(viewer))
                    }

                    if let feedback = store.snapshot?.viewer.feedback, !feedback.isEmpty {
                        Section("Feedback") {
                            ForEach(feedback, id: \.challengeID) { item in
                                if let challenge = store.challenges[item.challengeID] {
                                    NavigationLink {
                                        FeedbackContent(store: store, challenge: challenge)
                                            .navigationTitle(challenge.slot.title)
                                            .navigationBarTitleDisplayMode(.inline)
                                    } label: {
                                        LabeledContent(challenge.slot.title, value: status(of: item))
                                    }
                                }
                            }
                        }
                    }

                    Section {
                        LabeledContent("Algorithm", value: room.algorithm.title)
                        Text(room.algorithm.rule)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("Match")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Leave Match", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                                isConfirmingLeave = true
                            }
                        } label: {
                            Label("More", systemImage: "ellipsis")
                        }
                    }
                }
                .bottomActions {
                    if let challenge = store.availableChallenge {
                        PrimaryButton(title: actionTitle(for: challenge)) {
                            openChallenge = ChallengeRoute(id: challenge.id)
                        }
                    }
                }
                .sheet(item: $openChallenge) { route in
                    ChallengeView(store: store, challengeID: route.id)
                }
                .sensoryFeedback(.success, trigger: releasedCount)
                .confirmationDialog("Leave the match?", isPresented: $isConfirmingLeave, titleVisibility: .visible) {
                    Button("Leave Match", role: .destructive) {
                        Task { await store.leave() }
                    }
                } message: {
                    Text("The match ends as incomplete for both players. Losing signal doesn't count as leaving.")
                }
                .actionErrorAlert(
                    $store.actionError,
                    retry: { Task { await store.retryPendingCommand() } },
                    cancel: { store.discardPendingCommand() }
                )
            }
        }
    }

    private var releasedCount: Int {
        store.snapshot?.viewer.feedback.filter {
            if case .released = $0 { return true }
            return false
        }.count ?? 0
    }

    private func actionTitle(for challenge: ChallengeDefinition) -> String {
        switch challenge.slot {
        case .practice: "Start Warm-up"
        case .learningCheck: "Take Understanding Check"
        default: "Answer \(challenge.slot.title)"
        }
    }

    private func status(of item: FeedbackAvailability) -> String {
        guard case .released(let feedback) = item else {
            return "Waiting for \(store.opponent?.nickname ?? "the other player")"
        }
        let mine = feedback.answers.first { $0.playerID == store.snapshot?.viewer.playerID }
        return mine?.isCorrect == true ? "Correct" : "Incorrect"
    }

    private func pointsSummary(_ viewer: PlayerProgress) -> String {
        let available = "\(viewer.remainingAvailablePoints) points still available."
        guard viewer.pendingRewardMaximum > 0 else { return available }
        return available + " Up to \(viewer.pendingRewardMaximum) more unlock when both players have answered."
    }
}

private struct ChallengeRoute: Identifiable {
    let id: ChallengeID
}

private struct Scoreboard: View {
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

private struct StageRow: View {
    let stage: PlayerStage
    let course: CourseGraph

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func name(_ node: NodeID) -> String {
        course.nodes.first { $0.id == node }?.name ?? node.rawValue
    }

    private var title: String {
        switch stage {
        case .atStart: "At the start"
        case .practice: "Opening prediction"
        case .walking(let target): "Walk to \(name(target))"
        case .challenge: "Checkpoint question"
        case .choosingRoute: "Choose your route"
        case .finished: "Finished"
        case .departed: "You left the match"
        }
    }

    private var detail: String {
        switch stage {
        case .atStart: "The match begins when the host starts it."
        case .practice: "A warm-up question that doesn't count towards your score."
        case .walking: "Check in when you get there."
        case .challenge: "You get one answer. It locks when you submit."
        case .choosingRoute: "Standard or bonus. You can't change it later."
        case .finished: "Your score is final."
        case .departed: "This match won't count."
        }
    }
}
