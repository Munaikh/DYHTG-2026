import AlgorithmArenaCore
import AlgorithmArenaProgression
import SwiftUI

struct StudySessionView: View {
  @State private var activity: StudyActivity
  @Bindable var learning: LearningStore
  @State private var selected: NodeID?
  @State private var correct: Bool?
  @State private var showReplay = false
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  init(activity: StudyActivity, learning: LearningStore) {
    _activity = State(initialValue: activity)
    self.learning = learning
  }
  private var completed: Bool { learning.profile.completedActivities.contains(activity.id) }
  private var hintCount: Int { learning.profile.attempts[activity.id]?.hints ?? 0 }
  private var presentation: SearchPresentation {
    var p = SearchPresentation(
      scenario: activity.trace.scenario,
      algorithm: activity.algorithm == .aStar ? .aStar : .dijkstra, state: activity.state)
    switch activity.algorithm {
    case .bfs: p.indoorCostDisplay = .breadthFirst
    case .dfs: p.indoorCostDisplay = .depthFirst
    case .greedy: p.indoorCostDisplay = .greedy
    default: break
    }
    p.current = activity.state.settled.last
    return p
  }
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          HStack {
            Text("\(activity.mode == .lesson ? "Lesson" : "Puzzle") \(activity.ordinal+1) of 3")
              .font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(completed ? "Review" : "+\(activity.reward) XP").font(.subheadline.bold())
          }
          AdventureHeading(title: "Which point is next?", subtitle: activity.algorithm.rule)
          if learning.profile.preferences.beginnerGuide && correct == nil {
            Label(
              activity.ordinal == 0
                ? "A graph is points joined by lines. Numbers on lines are costs. Filled points are visited; dashed points are available."
                : "Try it at your own pace. You can change your choice before checking.",
              systemImage: "lightbulb.fill"
            )
            .font(.subheadline).foregroundStyle(.secondary)
          }
          AdventureCard {
            SearchGraphView(
              presentation: presentation, selectable: correct == true ? [] : activity.choices,
              selection: selected
            ) { id in
              selected = id
              if correct == false { correct = nil }
            }
          }
          if activity.algorithm == .bfs || activity.algorithm == .dfs {
            Text(
              "\(activity.algorithm == .bfs ? "Queue · first added first" : "Stack · top first"): \(activity.state.frontier.map(\.rawValue).joined(separator: " → "))"
            )
            .font(.subheadline.weight(.semibold))
          }
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 12) {
            ForEach(activity.choices, id: \.self) { node in
              Button {
                selected = node
                if correct == false { correct = nil }
              } label: {
                HStack {
                  VStack(alignment: .leading, spacing: 4) {
                    Text("Point \(node.rawValue)")
                    if let summary = presentation.nodes.first(where: { $0.id == node }),
                      activity.algorithm != .bfs && activity.algorithm != .dfs
                    {
                      Text(
                        activity.algorithm == .dijkstra
                          ? "Cost \(summary.g.map(String.init) ?? "∞")"
                          : activity.algorithm == .greedy
                            ? "Estimate \(summary.h)" : presentation.costText(summary)
                      ).font(.caption).foregroundStyle(
                        .secondary)
                    }
                  }
                  if selected == node { Image(systemName: "checkmark.circle.fill") }
                }.font(.headline).frame(
                  maxWidth: .infinity,
                  minHeight: learning.profile.preferences.largerControls ? 60 : 48
                )
                .padding(.horizontal, 8)
                .background(
                  selected == node
                    ? Color.arenaMint.opacity(0.5)
                    : Color(uiColor: .secondarySystemGroupedBackground),
                  in: RoundedRectangle(cornerRadius: 13)
                )
                .overlay(
                  RoundedRectangle(cornerRadius: 13).stroke(
                    selected == node ? Color.arenaForest : Color.secondary.opacity(0.25),
                    lineWidth: selected == node ? 2 : 1))
              }.buttonStyle(ArenaFeedbackButtonStyle()).disabled(correct == true)
                .animation(
                  systemReduceMotion || learning.profile.preferences.reduceMotion
                    ? nil : .spring(duration: 0.22), value: selected
                )
                .accessibilityAddTraits(selected == node ? .isSelected : [])
            }
          }
          if let correct {
            AdventureCard {
              VStack(alignment: .leading, spacing: 12) {
                Label(
                  correct ? "You’ve got it!" : "Good try. Let’s work it out.",
                  systemImage: correct ? "checkmark.circle.fill" : "lightbulb"
                )
                .font(.headline).foregroundStyle(correct ? Color.primary : .secondary)
                Text(activity.explanation).font(.body)
                if correct {
                  Text("Progress saved.").font(.footnote)
                    .foregroundStyle(.secondary)
                }
              }
            }
          }
          if correct == true {
            Button(nextTitle, action: advance).buttonStyle(
              AdventureButtonStyle(large: learning.profile.preferences.largerControls))
            Button("Watch the search", systemImage: "play.circle") { showReplay = true }
              .frame(maxWidth: .infinity, minHeight: 44)
          } else {
            Button("Check answer", systemImage: "checkmark") {
              guard let selected else { return }
              correct = learning.answer(selected, in: activity)
            }.buttonStyle(AdventureButtonStyle(large: learning.profile.preferences.largerControls))
              .disabled(selected == nil)
            if selected == nil {
              Text("Choose a point, then tap Check answer.").font(.footnote).foregroundStyle(
                .secondary)
            }
            Button(
              hintCount == 0
                ? "Need a hint?" : hintCount < 3 ? "Another hint" : "Show the worked answer",
              systemImage: "lightbulb"
            ) {
              learning.hint(for: activity)
            }.frame(maxWidth: .infinity, minHeight: 44).buttonStyle(ArenaFeedbackButtonStyle())
            if hintCount > 0 {
              Text(activity.hints[min(hintCount - 1, 2)]).padding(16).frame(
                maxWidth: .infinity, alignment: .leading
              ).background(Color.arenaMint.opacity(0.3), in: RoundedRectangle(cornerRadius: 14))
            }
          }
          DisclosureGroup("Read the graph as text") {
            VStack(alignment: .leading, spacing: 12) {
              Text(
                "Start: \(activity.trace.scenario.source.rawValue). Goal: \(activity.trace.scenario.goal.rawValue)."
              )
              Text(
                "Available in visit order: \(activity.state.frontier.map(\.rawValue).joined(separator: ", "))."
              )
              ForEach(Array(activity.trace.scenario.edges.enumerated()), id: \.offset) { _, edge in
                Text(
                  "Point \(edge.from.rawValue) connects to \(edge.to.rawValue) with cost \(edge.cost)\(edge.bidirectional ? " in both directions" : "")."
                )
              }
              ForEach(activity.state.costs, id: \.nodeID) { c in
                Text(
                  "\(c.nodeID.rawValue): \(c.g.map { "cost \($0)" } ?? "not reached")\(activity.algorithm == .aStar || activity.algorithm == .greedy ? ", estimate \(c.h)" : "")."
                )
              }
            }.padding(.top, 12)
          }
          DisclosureGroup("What should I know?") {
            Text(activity.algorithm.caveat).padding(.top, 10)
          }
          if let error = learning.storageError {
            Text(error).foregroundStyle(.red)
            Button("Retry loading saved progress") { learning.reload() }
          }
        }.padding(20).frame(maxWidth: 650).frame(maxWidth: .infinity)
          .animation(
            systemReduceMotion || learning.profile.preferences.reduceMotion
              ? nil : .easeOut(duration: 0.22), value: correct)
      }.background(Color.arenaCanvas)
        .navigationTitle(activity.algorithm.shortName).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        .sheet(isPresented: $showReplay) { StudyReplayView(activity: activity, learning: learning) }
        .modifier(LearningNoticeModifier(learning: learning))
    }
  }
  private var nextTitle: String {
    activity.ordinal < 2 ? (activity.mode == .lesson ? "Next lesson" : "Next puzzle") : "Done"
  }
  private func advance() {
    guard activity.ordinal < 2,
      let next = try? StudyCatalog.activity(
        algorithm: activity.algorithm, mode: activity.mode, ordinal: activity.ordinal + 1)
    else {
      dismiss()
      return
    }
    selected = nil
    correct = nil
    activity = next
  }
}

struct StudyReplayView: View {
  let activity: StudyActivity
  let learning: LearningStore
  @State private var index = 0
  @State private var playing = false
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  private var frame: SearchStep { activity.trace.steps[index] }
  private var presentation: SearchPresentation {
    var p = SearchPresentation(
      scenario: activity.trace.scenario,
      algorithm: activity.algorithm == .aStar ? .aStar : .dijkstra, state: frame.state)
    switch activity.algorithm {
    case .bfs: p.indoorCostDisplay = .breadthFirst
    case .dfs: p.indoorCostDisplay = .depthFirst
    case .greedy: p.indoorCostDisplay = .greedy
    default: break
    }
    if case .expand(let id) = frame.event { p.current = id }
    if index == activity.trace.steps.count - 1, case .route(let nodes, _) = activity.trace.outcome {
      p.routeNodes = nodes
    }
    return p
  }
  private var description: String {
    switch frame.event {
    case .initial:
      "Start at \(activity.trace.scenario.source.rawValue). Other costs are not known yet."
    case .expand(let id): "Visit \(id.rawValue). \(activity.algorithm.rule)"
    case .relax(let from, let to, let old, let candidate, let accepted):
      "Check \(from.rawValue) → \(to.rawValue). This path costs \(candidate). "
        + (accepted
          ? "Add or update \(to.rawValue) in the available points."
          : "Keep the existing \(old.map { "cost of \($0)" } ?? "choice").")
    case .reachedGoal:
      if case .route(let nodes, let cost) = activity.trace.outcome {
        "Goal reached. \(nodes.map(\.rawValue).joined(separator: " → ")) costs \(cost). \(activity.algorithm.caveat)"
      } else {
        "Goal reached."
      }
    case .unreachable: "There is no route to the goal."
    }
  }
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          AdventureHeading(
            title: "Watch each step",
            subtitle: "This is the real \(activity.algorithm.shortName) search.")
          SearchGraphView(presentation: presentation, highlightedEdge: activeEdge)
          Text("Step \(index+1) of \(activity.trace.steps.count)").font(.subheadline)
            .foregroundStyle(.secondary)
          Text(description).font(.body).accessibilityLabel(description)
          HStack {
            Button("Previous", systemImage: "backward.frame") {
              playing = false
              move(-1)
            }.disabled(index == 0)
            Spacer()
            Button(playing ? "Pause" : "Play", systemImage: playing ? "pause.fill" : "play.fill") {
              if index == activity.trace.steps.count - 1 { index = 0 }
              playing.toggle()
            }
            Spacer()
            Button("Next", systemImage: "forward.frame") {
              playing = false
              move(1)
            }.disabled(index == activity.trace.steps.count - 1)
          }.font(.headline).labelStyle(.iconOnly).buttonStyle(.bordered).controlSize(.large)
          Button("Restart", systemImage: "arrow.counterclockwise") {
            playing = false
            index = 0
          }.frame(maxWidth: .infinity, minHeight: 44)
          DisclosureGroup("Available points and costs") {
            VStack(alignment: .leading, spacing: 10) {
              Text("Available: \(frame.state.frontier.map(\.rawValue).joined(separator: ", ")).")
              Text("Visited: \(frame.state.settled.map(\.rawValue).joined(separator: ", ")).")
              ForEach(frame.state.costs, id: \.nodeID) { c in
                Text(
                  "\(c.nodeID.rawValue): g \(c.g.map(String.init) ?? "∞"), h \(c.h)\(activity.algorithm == .aStar ? ", f \(c.g.map { String($0+c.h) } ?? "∞")" : "")"
                )
              }
            }.padding(.top, 10)
          }
        }.padding(20).frame(maxWidth: 650).frame(maxWidth: .infinity)
      }.background(Color.arenaCanvas).navigationTitle("Replay").navigationBarTitleDisplayMode(
        .inline
      )
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
      .task(id: playing) {
        guard playing else { return }
        while playing && index < activity.trace.steps.count - 1 {
          do { try await Task.sleep(for: .seconds(1.5)) } catch { return }
          guard !Task.isCancelled, playing else { return }
          move(1)
        }
        playing = false
      }
      .onDisappear { playing = false }
    }
  }
  private var activeEdge: (from: NodeID, to: NodeID)? {
    if case .relax(let from, let to, _, _, _) = frame.event { return (from, to) }
    return nil
  }
  private func move(_ delta: Int) {
    withAnimation(
      systemReduceMotion || learning.profile.preferences.reduceMotion
        ? nil : .easeInOut(duration: 0.25)
    ) { index = min(max(0, index + delta), activity.trace.steps.count - 1) }
  }
}
