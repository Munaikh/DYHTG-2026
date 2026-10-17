import AlgorithmArenaCore
import SwiftUI

struct ResultsView: View {
    @Bindable var store: MatchStore

    @Environment(\.arenaReduceMotion) private var reduceMotion
    @State private var revealed = false
    @State private var checkChallenge: ChallengeRoute?

    var body: some View {
        NavigationStack {
            if let snapshot = store.snapshot, let viewer = store.viewer {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            Image(systemName: resultSymbol(snapshot.room.result))
                                .font(.system(size: 44)).foregroundStyle(.tint)
                                .scaleEffect(revealed ? 1 : 0.8).accessibilityHidden(true)
                            Text(summary(snapshot.room.result))
                            Text("Match points reward answers and completion. Walking speed earns no points.").font(.footnote)
                        }
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 8, trailing: 20))
                    }

                    Section {
                        Scoreboard(viewer: viewer, opponent: store.opponent)
                    }

                    ForEach(standings(snapshot.room.result), id: \.playerID) { standing in
                        Section(heading(for: standing)) {
                            ForEach(Array(standing.awards.enumerated()), id: \.offset) { _, award in
                                LabeledContent(title(for: award.slot), value: "\(award.points)")
                                    .monospacedDigit()
                            }
                            if let route = standing.routeChoice {
                                LabeledContent("Route", value: route.title)
                            }
                        }
                    }

                    understandingSection(viewer: viewer)

                    if !snapshot.viewer.feedback.isEmpty {
                        Section("Review") {
                            ForEach(snapshot.viewer.feedback, id: \.challengeID) { item in
                                if let challenge = store.challenges[item.challengeID] {
                                    NavigationLink(challenge.slot.title) {
                                        FeedbackContent(store: store, challenge: challenge)
                                            .navigationTitle(challenge.slot.title)
                                            .navigationBarTitleDisplayMode(.inline)
                                    }
                                }
                            }
                        }
                    }
                }
                .navigationTitle(headline(snapshot.room.result))
                .onAppear { withAnimation(reduceMotion ? nil : .spring(duration: 0.4)) { revealed = true } }
                .bottomActions {
                    PrimaryButton(title: "Done") {
                        Task { await store.leave() }
                    }
                }
                .sheet(item: $checkChallenge) { route in
                    ChallengeView(store: store, challengeID: route.id)
                }
            }
        }
    }

    @ViewBuilder
    private func understandingSection(viewer: PlayerProgress) -> some View {
        if let record = store.snapshot?.viewer.learningCheck {
            Section {
                LabeledContent("Next node", value: record.nodeCorrect ? "Correct" : "Incorrect")
                LabeledContent("Reason", value: record.reasonCorrect ? "Correct" : "Incorrect")
            } header: {
                Text("Understanding Check")
            } footer: {
                Text("Your first attempt. It doesn't change the score.")
            }
        } else if let challenge = store.availableChallenge, challenge.slot == .learningCheck {
            Section {
                Button("Take Understanding Check") {
                    checkChallenge = ChallengeRoute(id: challenge.id)
                }
            } footer: {
                Text("One unscored question on a new graph.")
            }
        }
    }

    private func resultSymbol(_ result: MatchResult?) -> String {
        switch result {
        case .winner(let id, _): id == store.viewer?.id ? "trophy.fill" : "flag.checkered"
        case .draw: "equal.circle.fill"
        case .incomplete: "pause.circle.fill"
        case nil: "hourglass"
        }
    }

    private func standings(_ result: MatchResult?) -> [Standing] {
        switch result {
        case .winner(_, let standings), .draw(let standings), .incomplete(_, let standings):
            standings.sorted { first, _ in first.playerID == store.viewer?.id }
        case nil:
            []
        }
    }

    private func name(for playerID: PlayerID) -> String {
        playerID == store.viewer?.id ? "You" : store.opponent?.nickname ?? "Other player"
    }

    private func heading(for standing: Standing) -> String {
        standing.playerID == store.viewer?.id ? "Your Points" : "\(name(for: standing.playerID))'s Points"
    }

    private func headline(_ result: MatchResult?) -> String {
        switch result {
        case .winner(let playerID, _): playerID == store.viewer?.id ? "You Won" : "\(name(for: playerID)) Won"
        case .draw: "Draw"
        case .incomplete: "Match Ended"
        case nil: "Results"
        }
    }

    private func summary(_ result: MatchResult?) -> String {
        switch result {
        case .winner(let playerID, _):
            playerID == store.viewer?.id
                ? "Your reasoning earned more points than \(store.opponent?.nickname ?? "the other player")'s."
                : "\(name(for: playerID)) earned more points this time. Review the replays to see where the search went differently."
        case .draw:
            "You both finished on the same score."
        case .incomplete(let departed, _):
            "\(departed == store.viewer?.id ? "You" : name(for: departed)) left before the finish, so this match doesn't count. Scores show released points only."
        case nil:
            "Waiting for the final result."
        }
    }

    private func title(for slot: ChallengeSlot?) -> String {
        slot?.title ?? "Finish"
    }
}

private struct ChallengeRoute: Identifiable {
    let id: ChallengeID
}
