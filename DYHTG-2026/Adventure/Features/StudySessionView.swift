import AlgorithmArenaCore
import AlgorithmArenaProgression
import SwiftUI

struct StudySessionView: View {
    @State private var activity: StudyActivity
    @Bindable var learning: LearningStore
    @State private var selected: NodeID?
    @State private var correct: Bool?
    @State private var showReplay = false
    @State private var earnedXP = 0
    @State private var sessionError: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(activity: StudyActivity, learning: LearningStore) {
        _activity = State(initialValue: activity)
        self.learning = learning
    }

    private var completed: Bool { learning.profile.completedActivities.contains(activity.id) }
    private var hintCount: Int { learning.profile.attempts[activity.id]?.hints ?? 0 }
    private var presentation: SearchPresentation {
        var value = studyPresentation(activity, state: activity.state)
        value.current = activity.state.settled.last
        return value
    }
    private var animation: Animation? {
        reduceMotion || learning.profile.preferences.reduceMotion ? nil : .easeOut(duration: 0.22)
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header.id("study.top")
                        graph
                        choices.id("study.choices")
                        Color.clear.frame(height: 1).id("study.feedback")
                        if let correct { answerFeedback(correct) }
                        if correct != true { hints }
                        graphDetails
                        if let error = sessionError ?? learning.storageError {
                            Text(error).font(.subheadline).foregroundStyle(.red)
                                .accessibilityIdentifier("study.error")
                        }
                    }
                    .padding(20).frame(maxWidth: 650).frame(maxWidth: .infinity)
                }
                .background(ArenaPalette.canvas)
                .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
                .onChange(of: activity.id) {
                    scroll.scrollTo("study.top", anchor: .top)
                }
                .onChange(of: correct) {
                    if let correct {
                        withAnimation(animation) {
                            scroll.scrollTo(correct ? "study.feedback" : "study.choices", anchor: .top)
                        }
                    }
                }
            }
            .navigationTitle(activity.algorithm.shortName).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.accessibilityIdentifier("study.close")
                }
            }
            .sheet(isPresented: $showReplay) {
                StudyReplayView(activity: activity, learning: learning)
            }
            .modifier(LearningNoticeModifier(learning: learning))
        }
        .tint(Color.arenaAccent)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                ArenaEyebrow(text: "\(activity.mode == .lesson ? "Lesson" : "Practice") \(activity.ordinal + 1) / 3")
                Spacer()
                Text(completed ? "Review" : "+\(activity.reward) XP")
                    .font(.caption.weight(.bold)).foregroundStyle(Color.arenaAccent)
            }
            AdventureHeading(title: "Which point is next?", subtitle: activity.algorithm.rule)
            if learning.profile.preferences.beginnerGuide && correct == nil {
                Label("Dashed circles are your available moves. Tap a point or choose below.", systemImage: "lightbulb")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private var graph: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Start \(activity.trace.scenario.source.rawValue)").font(.subheadline.weight(.semibold))
                Image(systemName: "arrow.right").font(.caption)
                Text("Goal \(activity.trace.scenario.goal.rawValue)").font(.subheadline.weight(.semibold))
                Spacer()
            }.foregroundStyle(.secondary)
            SearchGraphView(
                presentation: presentation,
                selectable: correct == true ? [] : activity.choices,
                selection: selected,
                onSelect: select)
                .accessibilityIdentifier("study.graph")
            if activity.algorithm == .bfs || activity.algorithm == .dfs {
                VStack(alignment: .leading, spacing: 6) {
                    ArenaEyebrow(text: activity.algorithm == .bfs ? "Queue · first in, first out" : "Stack · top first")
                    Text(activity.state.frontier.map(\.rawValue).joined(separator: " → "))
                        .font(.system(.headline, design: .rounded)).monospaced()
                }
            } else {
                Text(activity.algorithm == .aStar ? "g = cost so far · h = estimate · f = g + h"
                     : activity.algorithm == .greedy ? "h = estimated cost to the goal" : "g = cost from the start")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.arenaCard()
    }

    private var choices: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 12) {
            ForEach(activity.choices, id: \.self) { node in
                let isSelected = selected == node
                Button { select(node) } label: {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Point \(node.rawValue)").font(.headline)
                            if let summary = presentation.summary(node),
                               activity.algorithm != .bfs && activity.algorithm != .dfs {
                                Text(presentation.costText(summary))
                                    .font(.caption.weight(.medium)).monospacedDigit()
                            }
                        }
                        Spacer(minLength: 0)
                        if isSelected { Image(systemName: "checkmark.circle.fill") }
                    }
                    .foregroundStyle(isSelected ? ArenaPalette.ink : Color.primary)
                    .padding(16).frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
                    .background(isSelected ? ArenaPalette.mint : ArenaPalette.surface, in: .rect(cornerRadius: 18))
                    .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(isSelected ? Color.arenaAccent : Color.primary.opacity(0.12), lineWidth: isSelected ? 2 : 1) }
                }
                .buttonStyle(ArenaFeedbackButtonStyle())
                .disabled(correct == true)
                .accessibilityIdentifier("study.choice.\(node.rawValue)")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .animation(animation, value: selected)
    }

    private func answerFeedback(_ isCorrect: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(isCorrect ? "That’s the move." : "Try another move.", systemImage: isCorrect ? "checkmark.circle.fill" : "arrow.uturn.backward")
                .font(.headline).foregroundStyle(isCorrect ? Color.arenaAccent : Color.primary)
                .accessibilityIdentifier(isCorrect ? "study.correct" : "study.incorrect")
            Text(isCorrect ? activity.explanation : activity.algorithm.rule).font(.subheadline)
            if isCorrect {
                Text(earnedXP > 0 ? "+\(earnedXP) XP saved" : "Review complete. Your earned XP is already saved.")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Button("Watch the search", systemImage: "play.circle") { showReplay = true }
                    .buttonStyle(ArenaActionStyle(prominent: false))
                    .accessibilityIdentifier("study.replay")
            }
        }
        .arenaCard()
    }

    private var hints: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(hintCount == 0 ? "Need a hint?" : hintCount < activity.hints.count ? "Another hint" : "Worked answer shown", systemImage: "lightbulb") {
                learning.hint(for: activity)
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 44)
            .buttonStyle(ArenaFeedbackButtonStyle())
            .disabled(hintCount >= activity.hints.count)
            .accessibilityIdentifier("study.hint")
            if hintCount > 0, !activity.hints.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ArenaEyebrow(text: "Hint \(min(hintCount, activity.hints.count)) / \(activity.hints.count)")
                    Text(activity.hints[min(hintCount - 1, activity.hints.count - 1)]).font(.subheadline)
                }.arenaCard()
            }
        }
    }

    private var graphDetails: some View {
        VStack(alignment: .leading, spacing: 16) {
            DisclosureGroup("Read the graph") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Available: \(activity.state.frontier.map(\.rawValue).joined(separator: ", ")).")
                    ForEach(Array(activity.trace.scenario.edges.enumerated()), id: \.offset) { _, edge in
                        Text("\(edge.from.rawValue) \(edge.bidirectional ? "↔" : "→") \(edge.to.rawValue) · cost \(edge.cost)")
                    }
                    ForEach(presentation.nodes) { node in
                        Text("\(node.label): \(presentation.costText(node))")
                    }
                }.font(.subheadline).padding(.top, 10)
            }
            DisclosureGroup("What should I know?") {
                Text(activity.algorithm.caveat).font(.subheadline).padding(.top, 10)
            }
        }
    }

    private var actionBar: some View {
        VStack(spacing: 8) {
            if correct == true {
                Button(nextTitle, systemImage: activity.ordinal < 2 ? "arrow.right" : "checkmark", action: advance)
                    .buttonStyle(ArenaActionStyle()).accessibilityIdentifier("study.next")
            } else {
                Button("Check answer", systemImage: "checkmark", action: check)
                    .buttonStyle(ArenaActionStyle()).disabled(selected == nil)
                    .accessibilityIdentifier("study.check")
                if selected == nil {
                    Text("Choose a point to continue.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
        .frame(maxWidth: 650).frame(maxWidth: .infinity)
        .arenaControlDock()
    }

    private var nextTitle: String {
        activity.ordinal < 2 ? (activity.mode == .lesson ? "Next lesson" : "Next puzzle") : "Done"
    }
    private func select(_ node: NodeID) {
        guard correct != true else { return }
        selected = node
        if correct == false { correct = nil }
    }
    private func check() {
        guard let selected else { return }
        let previousXP = learning.profile.xp
        correct = learning.answer(selected, in: activity)
        earnedXP = max(0, learning.profile.xp - previousXP)
    }
    private func advance() {
        guard activity.ordinal < 2 else { dismiss(); return }
        do {
            let next = try StudyCatalog.activity(algorithm: activity.algorithm, mode: activity.mode, ordinal: activity.ordinal + 1)
            selected = nil
            correct = nil
            earnedXP = 0
            sessionError = nil
            activity = next
        } catch {
            sessionError = "The next activity couldn’t be loaded. Try again."
        }
    }
}

struct StudyReplayView: View {
    let activity: StudyActivity
    let learning: LearningStore
    @State private var index = 0
    @State private var playing = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var frame: SearchStep { activity.trace.steps[index] }
    private var lastIndex: Int { activity.trace.steps.count - 1 }
    private var presentation: SearchPresentation {
        var value = studyPresentation(activity, state: frame.state)
        if case .expand(let id) = frame.event { value.current = id }
        if index == lastIndex, case .route(let nodes, _) = activity.trace.outcome { value.routeNodes = nodes }
        return value
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ArenaEyebrow(text: "\(activity.algorithm.shortName) in motion")
                    AdventureHeading(title: "Watch each step.", subtitle: "Follow the same rules, from the start to the goal.")
                    VStack(alignment: .leading, spacing: 12) {
                        SearchGraphView(presentation: presentation, highlightedEdge: activeEdge)
                        HStack {
                            Text("Step \(index + 1) / \(activity.trace.steps.count)")
                            Spacer()
                            if index == lastIndex { Text("Complete") }
                        }.font(.caption.weight(.semibold)).foregroundStyle(.secondary).monospacedDigit()
                        ProgressView(value: Double(index), total: Double(max(lastIndex, 1))).tint(Color.arenaAccent)
                    }.arenaCard()
                    Text(description).font(.body).accessibilityIdentifier("study.replay.description")
                    DisclosureGroup("Available points and costs") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Available: \(frame.state.frontier.map(\.rawValue).joined(separator: ", ")).")
                            Text("Visited: \(frame.state.settled.map(\.rawValue).joined(separator: ", ")).")
                            ForEach(presentation.nodes) { node in Text("\(node.label): \(presentation.costText(node))") }
                        }.font(.subheadline).padding(.top, 10)
                    }
                }.padding(20).frame(maxWidth: 650).frame(maxWidth: .infinity)
            }
            .background(ArenaPalette.canvas)
            .safeAreaInset(edge: .bottom, spacing: 0) { controls }
            .navigationTitle("Replay").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.accessibilityIdentifier("study.replay.close")
                }
            }
            .task(id: playing) {
                guard playing else { return }
                while playing && index < lastIndex {
                    do { try await Task.sleep(for: .seconds(1.5)) } catch { return }
                    guard !Task.isCancelled, playing, scenePhase == .active else { return }
                    move(1)
                }
                playing = false
            }
            .onChange(of: scenePhase) { if scenePhase != .active { playing = false } }
            .onDisappear { playing = false }
        }
        .tint(Color.arenaAccent)
    }

    private var controls: some View {
        ArenaGlassGroup(spacing: 12) {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Button("Previous", systemImage: "backward.frame") { playing = false; move(-1) }
                        .buttonStyle(ArenaActionStyle(prominent: false)).disabled(index == 0)
                        .accessibilityIdentifier("study.replay.previous")
                    Button(playing ? "Pause" : "Play", systemImage: playing ? "pause.fill" : "play.fill") {
                        if index == lastIndex { index = 0 }
                        playing.toggle()
                    }
                    .buttonStyle(ArenaActionStyle()).accessibilityIdentifier("study.replay.play")
                    Button("Next", systemImage: "forward.frame") { playing = false; move(1) }
                        .buttonStyle(ArenaActionStyle(prominent: false)).disabled(index == lastIndex)
                        .accessibilityIdentifier("study.replay.next")
                }.labelStyle(.iconOnly)
                Button("Restart", systemImage: "arrow.counterclockwise") { playing = false; index = 0 }
                    .buttonStyle(ArenaActionStyle(prominent: false))
                    .accessibilityIdentifier("study.replay.restart")
            }
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 4)
        .frame(maxWidth: 650).frame(maxWidth: .infinity)
        .arenaControlDock()
    }

    private var description: String {
        switch frame.event {
        case .initial:
            return "Start at \(activity.trace.scenario.source.rawValue). No other point has been reached yet."
        case .expand(let id):
            return "Visit \(id.rawValue). \(activity.algorithm.rule)"
        case .relax(let from, let to, let old, let candidate, let accepted):
            if activity.algorithm == .bfs {
                return "Check \(from.rawValue) → \(to.rawValue). " + (accepted
                    ? "Add \(to.rawValue) to the back of the queue at depth \(candidate)."
                    : "\(to.rawValue) is already discovered, so leave it in place.")
            }
            if activity.algorithm == .dfs {
                return "Check \(from.rawValue) → \(to.rawValue). " + (accepted
                    ? "Put \(to.rawValue) on top of the stack to follow this branch."
                    : "\(to.rawValue) has already been visited.")
            }
            if activity.algorithm == .greedy {
                return "Check \(from.rawValue) → \(to.rawValue). " + (accepted
                    ? "Add \(to.rawValue), ordered by its estimate h. Cost so far does not set its priority."
                    : "\(to.rawValue) is already discovered, so keep its first route.")
            }
            return "Check \(from.rawValue) → \(to.rawValue). This path costs \(candidate). " + (accepted
                ? "Update the route to \(to.rawValue)."
                : "Keep the existing \(old.map { "cost of \($0)" } ?? "choice").")
        case .reachedGoal:
            if case .route(let nodes, let cost) = activity.trace.outcome {
                return "Goal reached: \(nodes.map(\.rawValue).joined(separator: " → ")). Cost \(cost). \(activity.algorithm.caveat)"
            }
            return "Goal reached."
        case .unreachable:
            return "There is no route to the goal."
        }
    }
    private var activeEdge: (from: NodeID, to: NodeID)? {
        if case .relax(let from, let to, _, _, _) = frame.event { return (from, to) }
        return nil
    }
    private func move(_ delta: Int) {
        withAnimation(reduceMotion || learning.profile.preferences.reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            index = min(max(0, index + delta), lastIndex)
        }
    }
}

private func studyPresentation(_ activity: StudyActivity, state: SearchState) -> SearchPresentation {
    var result = SearchPresentation(scenario: activity.trace.scenario,
                                    algorithm: activity.algorithm == .aStar ? .aStar : .dijkstra,
                                    state: state)
    switch activity.algorithm {
    case .bfs: result.indoorCostDisplay = .breadthFirst
    case .dfs: result.indoorCostDisplay = .depthFirst
    case .greedy: result.indoorCostDisplay = .greedy
    case .dijkstra, .aStar: break
    }
    return result
}
