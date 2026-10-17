import AlgorithmArenaCore
import AlgorithmArenaProgression
import SwiftUI

/// Learning home lives inside the original Learn tab; Play and Visualize keep their own state.
struct LearnHomeView: View {
    let learning: LearningStore
    let openPlay: () -> Void
    @State private var progress = LearnProgressStore()
    @State private var path: [AlgorithmKind] = []
    @State private var destination: LearningDestination?

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    hero
                    LearningXPBar(profile: learning.profile).arenaCard()
                    HStack {
                        Text("Make it click").font(.title2.bold())
                        Spacer()
                        Text("5 algorithms").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    VStack(spacing: 12) {
                        destinationCard("Lessons", detail: "15 small steps. Five ways to think.",
                                        symbol: "book.closed.fill", progress: "\(learning.profile.lessonCount)/15") {
                            destination = .lessons
                        }
                        .accessibilityIdentifier("home.lessons")
                        destinationCard("Practice", detail: "15 puzzles. Your next move is yours.",
                                        symbol: "puzzlepiece.extension.fill", progress: "\(learning.profile.practice.count)/15") {
                            destination = .practice
                        }
                        .accessibilityIdentifier("home.practice")
                    }
                    questCard
                    if learning.profile.preferences.beginnerGuide {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Start with BFS", systemImage: "lightbulb.fill")
                                .font(.headline).foregroundStyle(LearnStyle.teal)
                            Text("Pick a point, check your prediction, then watch the search. Hints are always there when you need them.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }.arenaCard()
                    }
                    warmups
                    Button(action: openPlay) {
                        Label("Ready for a Plot Twist Duel?", systemImage: "bolt.shield.fill")
                    }
                    .buttonStyle(ArenaActionStyle(prominent: false))
                    .accessibilityIdentifier("home.play")
                    Text("Learning XP and collections save on this device.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                .padding(20)
                .frame(maxWidth: 650)
                .frame(maxWidth: .infinity)
            }
            .background(ArenaPalette.canvas)
            .navigationTitle("Home")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { destination = .quests } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "flag.checkered").font(.headline).padding(5)
                            if learning.pendingQuests > 0 {
                                Circle().fill(ArenaPalette.amber).frame(width: 8, height: 8)
                            }
                        }
                    }
                    .accessibilityLabel("Quests")
                    .accessibilityIdentifier("home.quests")
                }
                ToolbarItem(placement: .topBarTrailing) { ProfileButton() }
            }
            .navigationDestination(for: AlgorithmKind.self) { algorithm in
                LessonSessionView(algorithm: algorithm, progress: progress) { next in path = [next] }
                    .id(algorithm)
            }
            .sheet(item: $destination) { selected in
                switch selected {
                case .lessons: LearnLibrary(learning: learning, mode: .lesson, dismissable: true)
                case .practice: LearnLibrary(learning: learning, mode: .practice, dismissable: true)
                case .quests: AdventureQuests(learning: learning, dismissable: true)
                case .activity(let activity): StudySessionView(activity: activity, learning: learning)
                }
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                ArenaEyebrow(text: learning.equippedTitle, color: ArenaPalette.mint)
                Spacer(minLength: 0)
                Image(systemName: "sparkles").foregroundStyle(ArenaPalette.mint)
            }
            Text("Think like\nan algorithm.")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text(learning.nextLesson.map { "Up next: \($0.algorithm.shortName) · \($0.title)" }
                 ?? "All 15 lessons complete. Put your thinking to the test.")
                .font(.subheadline).foregroundStyle(.white.opacity(0.85))
            Button {
                if let next = learning.nextLesson { destination = .activity(next) }
                else { destination = .practice }
            } label: {
                HStack {
                    Text(learning.nextLesson == nil ? "Try a practice puzzle" : "Continue learning")
                    Image(systemName: "arrow.right")
                }
            }
            .buttonStyle(ArenaActionStyle())
            .accessibilityIdentifier("home.continue")
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ArenaPalette.ink, in: .rect(cornerRadius: 28))
    }

    private func destinationCard(_ title: String, detail: String, symbol: String,
                                 progress: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title2).foregroundStyle(ArenaPalette.ink)
                    .frame(width: 50, height: 50)
                    .background(ArenaPalette.mint, in: .rect(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.headline)
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                VStack(spacing: 6) {
                    Text(progress).font(.caption.weight(.bold)).monospacedDigit()
                    Image(systemName: "arrow.up.right").font(.caption.weight(.bold))
                }.foregroundStyle(LearnStyle.teal)
            }
            .arenaCard()
        }.buttonStyle(.plain)
    }

    private var questCard: some View {
        let quest = LearningQuest.all.first { $0.canClaim(in: learning.profile) }
            ?? LearningQuest.all.first { !learning.profile.claimedQuests.contains($0.id) }
        return Button { destination = .quests } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    ArenaEyebrow(text: learning.pendingQuests > 0 ? "Reward ready" : "Your next quest")
                    Spacer()
                    Image(systemName: "flag.checkered").foregroundStyle(LearnStyle.teal)
                }
                Text(quest?.name ?? "Every quest, conquered.").font(.title3.bold())
                Text(quest?.instruction ?? "Explore your titles and achievements in Profile.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if let quest {
                    ProgressView(value: Double(quest.progress(in: learning.profile)), total: Double(quest.goal))
                        .tint(LearnStyle.teal)
                    HStack {
                        Text("\(quest.progress(in: learning.profile))/\(quest.goal)").monospacedDigit()
                        Spacer()
                        Text(quest.canClaim(in: learning.profile) ? "Claim \(quest.xp) XP →" : "+\(quest.xp) XP")
                    }.font(.caption.weight(.semibold)).foregroundStyle(LearnStyle.teal)
                }
            }.arenaCard()
        }.buttonStyle(.plain).accessibilityIdentifier("home.questCard")
    }

    private var warmups: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Duel warm-ups").font(.title2.bold())
            Text("Our original guided lessons: predict, calculate, replay, and try a new graph.")
                .font(.subheadline).foregroundStyle(.secondary)
            ForEach(AlgorithmKind.allCases, id: \.self) { algorithm in
                Button { path.append(algorithm) } label: {
                    HStack {
                        Text(algorithm == .dijkstra ? "Dijkstra" : "A*").font(.headline)
                        Spacer()
                        let record = progress.progress(for: algorithm)
                        Text(record.isComplete ? "Explored" : record.hasStarted ? "Continue" : "Explore")
                            .font(.subheadline)
                        Image(systemName: record.isComplete ? "checkmark.circle.fill" : "arrow.right")
                    }.padding(18)
                        .background(ArenaPalette.surface, in: .rect(cornerRadius: 18))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("learn.lesson.\(algorithm.rawValue)")
            }
        }
    }
}

private enum LearningDestination: Identifiable {
    case lessons, practice, quests, activity(StudyActivity)
    var id: String {
        switch self {
        case .lessons: "lessons"
        case .practice: "practice"
        case .quests: "quests"
        case .activity(let activity): activity.id
        }
    }
}
