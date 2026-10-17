import AlgorithmArenaCore
import SwiftUI

struct ChallengeView: View {
    @Bindable var store: MatchStore
    let challengeID: ChallengeID

    @Environment(\.dismiss) private var dismiss
    @State private var isSubmitting = false
    @State private var isConfirming = false
    @FocusState private var costFocused: Bool

    var body: some View {
        NavigationStack {
            if let challenge = store.challenges[challengeID] {
                Group {
                    if store.submission(for: challengeID) != nil {
                        FeedbackContent(store: store, challenge: challenge)
                    } else {
                        question(challenge)
                    }
                }
                .navigationTitle(challenge.slot.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        if #available(iOS 26, *) {
                            Button(role: .close) { dismiss() }
                        } else {
                            Button("Close") { dismiss() }
                        }
                    }
                }
            }
        }
        .actionErrorAlert(
            $store.actionError,
            retry: { Task { await store.retryPendingCommand() } },
            cancel: { store.discardPendingCommand() }
        )
    }

    private var draft: Binding<ChallengeDraft> {
        Binding(
            get: { store.drafts[challengeID] ?? ChallengeDraft() },
            set: { store.drafts[challengeID] = $0 }
        )
    }

    private func question(_ challenge: ChallengeDefinition) -> some View {
        let presentation = SearchPresentation(
            scenario: challenge.scenario,
            algorithm: challenge.algorithm,
            state: challenge.presentedState
        )
        let tappable: [NodeID] = switch challenge.action {
        case .selectNode(let options), .transfer(let options, _): options
        default: []
        }

        return List {
            Section {
                Text(challenge.prompt)
                    .font(.title3.weight(.semibold))
                    .padding(.vertical, 4)
                LabeledContent("Algorithm", value: challenge.algorithm.title)
                LabeledContent("Worth", value: challenge.pointsText)
            }

            SearchStateSection(
                presentation: presentation,
                selectable: tappable,
                selection: draft.wrappedValue.node,
                onSelect: { draft.wrappedValue.node = $0 }
            ) {
                Text(legend(for: challenge.algorithm))
            }

            AnswerSections(challenge: challenge, draft: draft, costFocused: $costFocused)
        }
        .scrollDismissesKeyboard(.interactively)
        .bottomActions {
            if challenge.feedbackGate == .afterBothSubmissions {
                Label("Your answer stays private. Feedback unlocks after both players submit.", systemImage: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if draft.wrappedValue.answer(for: challenge.action) == nil {
                Text("Complete the labelled answer fields to enable Submit answer.").font(.footnote).foregroundStyle(.secondary)
            }
            PrimaryButton(title: "Submit Answer", busyTitle: "Submitting...", isBusy: isSubmitting) {
                if challenge.maximumPoints > 0 {
                    isConfirming = true
                } else {
                    submit(challenge)
                }
            }
            .disabled(draft.wrappedValue.answer(for: challenge.action) == nil)
        }
        .confirmationDialog("Submit this answer?", isPresented: $isConfirming, titleVisibility: .visible) {
            Button("Submit Answer") { submit(challenge) }
        } message: {
            Text("You get one answer for \(challenge.slot.title). It can't be changed afterwards.")
        }
    }

    private func legend(for algorithm: AlgorithmKind) -> String {
        let costs = algorithm == .aStar
            ? "Under each node: g + h = f."
            : "Under each node: g, the cheapest known cost from the start."
        return "\(costs) Dashed ring: on the frontier. Grey: settled. Edge labels are walking costs."
    }

    private func submit(_ challenge: ChallengeDefinition) {
        guard !isSubmitting, let answer = draft.wrappedValue.answer(for: challenge.action) else { return }
        costFocused = false
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            await store.submit(answer, to: challenge)
        }
    }
}
