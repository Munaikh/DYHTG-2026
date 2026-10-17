import AlgorithmArenaProgression
import SwiftUI

struct LearningShell: View {
  let match: MatchStore
  @Bindable var learning: LearningStore
  @State private var tab = 0
  @State private var activity: StudyActivity?
  var body: some View {
    TabView(selection: $tab) {
      AdventureHome(
        learning: learning, openLesson: { activity = $0 }, play: { tab = 2 }, quests: { tab = 3 },
        profile: { tab = 4 }
      )
      .tabItem { Label("Home", systemImage: "house.fill") }.tag(0)
      LearnLibrary(learning: learning, mode: .lesson)
        .tabItem { Label("Learn", systemImage: "book.closed.fill") }.tag(1)
      AdventurePlay(match: match, learning: learning)
        .tabItem { Label("Play", systemImage: "play.circle.fill") }.tag(2)
      AdventureQuests(learning: learning)
        .tabItem { Label("Quests", systemImage: "checkmark.seal.fill") }.badge(
          learning.pendingQuests
        )
        .tag(3)
      AdventureProfile(learning: learning)
        .tabItem { Label("Profile", systemImage: "person.crop.circle") }.tag(4)
    }
    .tint(.arenaAccent)
    .sheet(item: $activity) { StudySessionView(activity: $0, learning: learning) }
  }
}
struct AdventureHome: View {
  @Bindable var learning: LearningStore
  let openLesson: (StudyActivity) -> Void
  let play: () -> Void
  let quests: () -> Void
  let profile: () -> Void
  private var dailyTip: String {
    let tips = [
      "A graph is a group of points joined by lines.", "The cheapest route can have more steps.",
      "BFS explores nearby points first.", "A* adds cost so far to estimated cost left.",
      "An incorrect answer is a useful chance to learn.",
    ]
    return tips[Calendar.current.component(.day, from: Date()) % tips.count]
  }
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          Button(action: profile) {
            HStack(spacing: 12) {
              Image(systemName: "leaf.circle.fill").font(.largeTitle).foregroundStyle(
                Color.arenaAccent
              ).accessibilityHidden(true)
              VStack(alignment: .leading, spacing: 3) {
                Text("Hello, \(learning.profile.nickname)").font(.title2.bold())
                Text(learning.equippedTitle).font(.subheadline).foregroundStyle(.secondary)
              }
            }
          }.buttonStyle(.plain).accessibilityLabel("Open profile for \(learning.profile.nickname)")
            .accessibilityValue(learning.equippedTitle)
          AdventureCard { LearningXPBar(profile: learning.profile) }
          AdventureCard {
            VStack(alignment: .leading, spacing: 16) {
              AdventureHeading(
                title: "One small step.\nA smarter move.",
                subtitle: "Learn with short, hands-on puzzles.")
              if let next = learning.nextLesson {
                Label("Up next: \(next.algorithm.shortName)", systemImage: next.algorithm.symbol)
                  .font(.subheadline)
                Button("Continue learning", systemImage: "arrow.right") { openLesson(next) }
                  .buttonStyle(
                    AdventureButtonStyle(large: learning.profile.preferences.largerControls))
              } else {
                Label("All beginner lessons complete", systemImage: "checkmark.seal.fill")
                Button("Try a practice puzzle", action: play).buttonStyle(AdventureButtonStyle())
              }
            }
          }
          Button(action: play) {
            HStack {
              Label("Play a challenge", systemImage: "play.fill")
              Spacer()
              Image(systemName: "chevron.right")
            }
          }.buttonStyle(AdventureButtonStyle(secondary: true))
          if let quest = LearningQuest.all.first(where: {
            !learning.profile.claimedQuests.contains($0.id)
          }) {
            Button(action: quests) {
              AdventureCard {
                VStack(alignment: .leading, spacing: 10) {
                  Label(quest.name, systemImage: "checkmark.seal").font(.headline)
                  Text(quest.instruction).font(.subheadline).foregroundStyle(.secondary)
                  ProgressView(
                    value: Double(quest.progress(in: learning.profile)), total: Double(quest.goal))
                  Text(
                    "\(quest.progress(in: learning.profile))/\(quest.goal) · \(quest.xp) XP reward"
                  ).font(.caption).foregroundStyle(.secondary)
                }
              }
            }.buttonStyle(.plain).accessibilityHint("Open Quests")
          }
          VStack(alignment: .leading, spacing: 6) {
            Label("Learning tip", systemImage: "lightbulb").font(.headline)
            Text(dailyTip).font(.body).foregroundStyle(.secondary)
          }.padding(.horizontal, 4)
        }.padding(20).frame(maxWidth: 650)
          .frame(maxWidth: .infinity)
      }.background(Color.arenaCanvas)
        .navigationTitle("Algorithm Arena").navigationBarTitleDisplayMode(.inline)
    }
  }
}
struct LearnLibrary: View {
  @Bindable var learning: LearningStore
  let mode: ActivityMode
  var dismissable = false
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          AdventureHeading(
            title: mode == .lesson ? "Learn by doing" : "Choose a puzzle",
            subtitle: mode == .lesson
              ? "Start anywhere. Go at your own pace."
              : "Practice indoors. No GPS or opponent needed.")
          ForEach(StudyAlgorithm.allCases) { algorithm in
            NavigationLink {
              AlgorithmModuleView(algorithm: algorithm, mode: mode, learning: learning)
            } label: {
              AdventureCard {
                HStack(spacing: 14) {
                  AlgorithmBadge(algorithm: algorithm)
                  VStack(alignment: .leading, spacing: 5) {
                    Text(algorithm.name).font(.headline)
                    Text(
                      mode == .lesson
                        ? "\(learning.profile.completedLessons(for: algorithm)) of 3 lessons complete"
                        : "3 practice puzzles · 20 XP each"
                    )
                    .font(.subheadline).foregroundStyle(.secondary)
                  }
                  Spacer(minLength: 0)
                  Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(
                    .secondary)
                }
              }
            }.buttonStyle(.plain)
          }
        }.padding(20).frame(maxWidth: 650).frame(maxWidth: .infinity)
      }.background(Color.arenaCanvas)
        .navigationTitle(mode == .lesson ? "Learn" : "Practice")
        .toolbar {
          if dismissable {
            ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
          }
        }
    }
  }
}
struct AlgorithmModuleView: View {
  let algorithm: StudyAlgorithm
  let mode: ActivityMode
  @Bindable var learning: LearningStore
  @State private var activity: StudyActivity?
  @State private var activities: [StudyActivity] = []
  @State private var loadError: String?
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        AlgorithmBadge(algorithm: algorithm)
        AdventureHeading(title: algorithm.name, subtitle: algorithm.rule)
        if let loadError { Text(loadError).foregroundStyle(.red) }
        ForEach(activities) { item in
          Button {
            activity = item
          } label: {
            AdventureCard {
              HStack(spacing: 14) {
                Image(
                  systemName: learning.profile.completedActivities.contains(item.id)
                    ? "checkmark.circle.fill" : "play.circle.fill"
                )
                .font(.title2).foregroundStyle(Color.arenaForest)
                VStack(alignment: .leading, spacing: 5) {
                  Text("\(item.ordinal+1). \(item.title)").font(.headline)
                  Text(
                    learning.profile.completedActivities.contains(item.id)
                      ? "Completed · review anytime" : "Earn \(item.reward) XP"
                  ).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
              }
            }
          }.buttonStyle(.plain)
        }
        if mode == .lesson {
          Text("Finish all 3 lessons for a one-time 100 XP module reward.").font(.subheadline)
            .foregroundStyle(.secondary)
        }
        DisclosureGroup("What this algorithm can do") { Text(algorithm.caveat).padding(.top, 8) }
      }.padding(20).frame(maxWidth: 650).frame(maxWidth: .infinity)
    }.background(Color.arenaCanvas)
      .navigationTitle(algorithm.shortName).navigationBarTitleDisplayMode(.inline)
      .task {
        do { activities = try StudyCatalog.activities(for: algorithm, mode: mode) } catch {
          loadError = "These lessons couldn’t be loaded. Go back and try again."
        }
      }
      .sheet(item: $activity) { StudySessionView(activity: $0, learning: learning) }
  }
}
struct AdventurePlay: View {
  let match: MatchStore
  @Bindable var learning: LearningStore
  @State private var showCampus = false
  @State private var showPractice = false
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          AdventureHeading(
            title: "Make your next move", subtitle: "A quick puzzle or a campus match?")
          Button {
            showPractice = true
          } label: {
            AdventureCard {
              VStack(alignment: .leading, spacing: 14) {
                Label("Practice puzzles", systemImage: "puzzlepiece.extension.fill").font(
                  .title2.bold())
                Text("All 5 algorithms. Hints when you need them. Play indoors.").foregroundStyle(
                  .secondary)
                Label("Choose a puzzle", systemImage: "arrow.right").font(.headline)
              }
            }
          }.buttonStyle(.plain)
          AdventureCard {
            VStack(alignment: .leading, spacing: 14) {
              Label("Campus match", systemImage: "map.fill").font(.title2.bold())
              Text("Two players. Three stops. Dijkstra or A*.").foregroundStyle(.secondary)
              Button("Open campus game") {
                learning.prepareCampusNickname()
                showCampus = true
              }.buttonStyle(AdventureButtonStyle())
              Text(
                "Create a room for a real teammate. Solo campus practice uses a simulated player."
              ).font(.caption).foregroundStyle(.secondary)
            }
          }
          Text(
            "Learn and Practice never need location. Younger learners should explore outdoors with a responsible adult."
          )
          .font(.footnote).foregroundStyle(.secondary)
        }.padding(20).frame(maxWidth: 650).frame(maxWidth: .infinity)
      }.background(Color.arenaCanvas).navigationTitle("Play")
        .sheet(isPresented: $showPractice) {
          LearnLibrary(learning: learning, mode: .practice, dismissable: true)
        }
        .sheet(isPresented: $showCampus) { HomeView(store: match) }
        .onChange(of: showCampus) { _, presented in if !presented { learning.syncCampusNickname() }
        }
        .onChange(of: match.route) { _, route in if route != .home { showCampus = false } }
    }
  }
}
