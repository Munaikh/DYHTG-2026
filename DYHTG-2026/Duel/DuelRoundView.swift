import AlgorithmArenaCore
import SwiftUI

struct DuelRoundView: View {
    @Bindable var store: DuelStore
    let snapshot: DuelSnapshot
    let round: DuelRound
    @State private var selection: NodeID?
    @State private var showsBefore = false
    @State private var showTable = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                ArenaEyebrow(text: "Round \(snapshot.roundIndex + 1) / \(snapshot.roundCount)")
                Spacer()
                Text(snapshot.algorithm.title)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(ArenaPalette.surface, in: .capsule)
            }
            Text(round.title).font(.system(.largeTitle, design: .rounded).bold())
                .fixedSize(horizontal: false, vertical: true)

            if let twist = round.twist {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "bolt.fill").font(.title2)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("PLOT TWIST").font(.caption.weight(.black)).tracking(1.5)
                        Text(twist).font(.subheadline.weight(.medium))
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(ArenaPalette.ink)
                .background(ArenaPalette.amber, in: .rect(cornerRadius: 20))
            }

            if let reveal = snapshot.reveal, snapshot.phase == .reveal {
                revealContent(reveal)
            } else {
                question
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    private var question: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(round.prompt).font(.title3.weight(.semibold))
            VStack(spacing: 16) {
                if round.previousScenario != nil {
                    Picker("Network", selection: $showsBefore) {
                        Text("Before twist").tag(true)
                        Text("After twist").tag(false)
                    }
                    .pickerStyle(.segmented)
                }
                HStack {
                    Label(showsBefore ? "Original network" : (round.questionKind?.title ?? "Choose the next node"), systemImage: showsBefore ? "clock.arrow.circlepath" : "hand.tap")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Button(showTable ? "Graph" : "Table", systemImage: showTable ? "point.3.connected.trianglepath.dotted" : "tablecells") {
                        showTable.toggle()
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(ArenaCompactButtonStyle())
                    .frame(minHeight: 44)
                }
                if showTable {
                    NodeTable(presentation: presentation)
                } else {
                    SearchGraphView(presentation: presentation,
                                    selectable: canSelect ? round.choices : [], selection: selection,
                                    onSelect: { selection = $0 })
                }
                Text(snapshot.algorithm.rule)
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(snapshot.algorithm.tieRule)
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .arenaCard()

            if let focus = round.focusNodeID {
                Text("Focus node: \(focus.rawValue)").font(.caption.weight(.semibold))
            }
            if !round.presentedState.settled.isEmpty {
                Text("Visited in order: " + round.presentedState.settled.map(\.rawValue).joined(separator: " → "))
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            if store.viewer?.submitted == true {
                VStack(spacing: 10) {
                    Label("Prediction locked", systemImage: "lock.fill").font(.headline)
                    Text("Waiting for \(store.opponent?.nickname ?? "your opponent"). Your answers will reveal together.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    ProgressView().padding(.top, 4)
                }
                .frame(maxWidth: .infinity).padding(24)
                .background(ArenaPalette.surface, in: .rect(cornerRadius: 22))
                .accessibilityIdentifier("duel.waitingReveal")
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 85), spacing: 12)], spacing: 12) {
                    ForEach(round.choices, id: \.self) { id in
                        Button {
                            showsBefore = false
                            selection = id
                        } label: {
                            HStack(spacing: 8) {
                                Text(round.scenario.nodes.first { $0.id == id }?.label ?? id.rawValue)
                                if selection == id { Image(systemName: "checkmark") }
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .foregroundStyle(selection == id ? ArenaPalette.ink : Color.primary)
                            .background(selection == id ? ArenaPalette.mint : ArenaPalette.surface, in: .rect(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Choose node \(id.rawValue)")
                        .accessibilityAddTraits(selection == id ? .isSelected : [])
                        .accessibilityIdentifier("duel.choice.\(id.rawValue)")
                        .disabled(!store.canAct)
                    }
                }
                Button {
                    guard let selection else { return }
                    Task { await store.perform(.submit, answer: selection) }
                } label: {
                    Label("Lock In Prediction", systemImage: "lock.fill")
                }
                .buttonStyle(ArenaActionStyle())
                .disabled(selection == nil || !store.canAct || showsBefore)
                .accessibilityIdentifier("duel.submit")
                Text("One prediction each. Take your time.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var canSelect: Bool { !showsBefore && store.viewer?.submitted == false && store.canAct }

    private var presentation: SearchPresentation {
        if showsBefore, let previous = round.previousScenario {
            let initial = SearchState(frontier: [previous.source], settled: [], costs: previous.nodes.map {
                NodeCost(nodeID: $0.id, g: $0.id == previous.source ? 0 : nil, h: $0.heuristic, predecessor: nil)
            })
            return SearchPresentation(scenario: previous, studyAlgorithm: snapshot.algorithm, state: initial)
        }
        return SearchPresentation(scenario: round.scenario, studyAlgorithm: snapshot.algorithm, state: round.presentedState)
    }

    private func revealContent(_ reveal: DuelReveal) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 16) {
                Label("Correct choice: \(presentation.label(reveal.correctNodeID))", systemImage: "sparkles")
                    .font(.title2.bold())
                ForEach(reveal.answers) { answer in
                    HStack {
                        Image(systemName: answer.correct ? "checkmark.circle.fill" : "arrow.uturn.backward.circle")
                            .foregroundStyle(answer.correct ? ArenaPalette.teal : Color.orange)
                        Text(snapshot.players.first { $0.id == answer.playerID }?.nickname ?? "Player")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(presentation.label(answer.answerNodeID)) · +\(answer.points)")
                            .font(.subheadline.monospacedDigit())
                    }
                }
                Text(reveal.explanation).font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .arenaCard()
            DuelRevealPlayback(reveal: reveal, round: round)
            if store.viewer?.hasContinued == true {
                Label("Ready for the next round. Waiting for your opponent…", systemImage: "checkmark.circle.fill")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .arenaCard()
            } else {
                Button(snapshot.roundIndex + 1 == snapshot.roundCount ? "See Results" : "Next Round") {
                    Task { await store.perform(.advance) }
                }
                .buttonStyle(ArenaActionStyle())
                .disabled(!store.canAct)
                .accessibilityIdentifier("duel.advance")
            }
        }
    }
}

private struct DuelRevealPlayback: View {
    @State private var playback: ReplayPlayback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(reveal: DuelReveal, round: DuelRound) {
        let playback = ReplayPlayback(trace: reveal.trace, scenario: round.scenario)
        if let decision = reveal.trace.steps.firstIndex(where: {
            $0.state.settled == round.presentedState.settled && $0.state.costs == round.presentedState.costs
                && $0.state.frontier.sorted() == round.presentedState.frontier.sorted()
        }) {
            playback.move(to: decision, animated: false)
        }
        _playback = State(initialValue: playback)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ArenaEyebrow(text: "Watch the reasoning")
            SearchGraphView(presentation: playback.presentation, highlightedEdge: playback.highlightedEdge)
            Text(playback.description).font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentTransition(.opacity)
            ReplayControls(playback: playback)
        }
        .arenaCard()
        .onAppear { if !reduceMotion { playback.isPlaying = true } }
        .onDisappear { playback.isPlaying = false }
    }
}
