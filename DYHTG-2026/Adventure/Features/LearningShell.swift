import AlgorithmArenaProgression
import SwiftUI

/// A focused library presented from the Learn tab.
struct LearnLibrary: View {
    @Bindable var learning: LearningStore
    let mode: ActivityMode
    var dismissable = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(mode == .lesson
                         ? "Choose an algorithm. Each has three guided lessons with predictions and explanations."
                         : "Choose an algorithm to practice on a new graph. Each completed puzzle earns 20 XP.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ForEach(StudyAlgorithm.allCases) { algorithm in
                        NavigationLink {
                            AlgorithmModuleView(algorithm: algorithm, mode: mode, learning: learning)
                        } label: {
                            VStack(alignment: .leading, spacing: 16) {
                                HStack(spacing: 14) {
                                    AlgorithmBadge(algorithm: algorithm)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(algorithm.name).font(.headline)
                                        Text("\(completedCount(for: algorithm)) of 3 complete")
                                            .font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary)
                                }
                                ProgressView(value: Double(completedCount(for: algorithm)), total: 3)
                                    .tint(Color.arenaAccent)
                            }.arenaCard()
                        }
                        .buttonStyle(ArenaFeedbackButtonStyle())
                        .accessibilityIdentifier("library.\(mode.rawValue).\(algorithm.rawValue)")
                    }
                }
                .padding(20).frame(maxWidth: 650).frame(maxWidth: .infinity)
            }
            .background(ArenaPalette.canvas)
            .navigationTitle(mode == .lesson ? "Lessons" : "Practice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if dismissable {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }.accessibilityIdentifier("library.close")
                    }
                }
            }
        }
        .tint(Color.arenaAccent)
    }

    private func completedCount(for algorithm: StudyAlgorithm) -> Int {
        let activities = (try? StudyCatalog.activities(for: algorithm, mode: mode)) ?? []
        return activities.filter { learning.profile.completedActivities.contains($0.id) }.count
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
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 14) {
                    AlgorithmBadge(algorithm: algorithm)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(algorithm.name).font(.title2.bold())
                        Text(algorithm.rule).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                if mode == .lesson {
                    Label("Finish this module for 100 bonus XP", systemImage: "checkmark.seal")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Color.arenaAccent)
                }
                if let loadError {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(loadError).foregroundStyle(.secondary)
                        Button("Try again", action: load).buttonStyle(ArenaActionStyle())
                            .accessibilityIdentifier("module.retry")
                    }.arenaCard()
                }
                ForEach(activities) { item in
                    let complete = learning.profile.completedActivities.contains(item.id)
                    Button { activity = item } label: {
                        HStack(spacing: 14) {
                            Image(systemName: complete ? "checkmark.circle.fill" : "play.circle.fill")
                                .font(.title2).foregroundStyle(Color.arenaAccent)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(item.ordinal + 1). \(item.title)").font(.headline)
                                Text(complete ? "Completed · review anytime" : "+\(item.reward) XP")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary)
                        }.arenaCard()
                    }
                    .buttonStyle(ArenaFeedbackButtonStyle())
                    .accessibilityIdentifier("module.\(algorithm.rawValue).\(mode.rawValue).\(item.ordinal)")
                }
                VStack(alignment: .leading, spacing: 8) {
                    ArenaEyebrow(text: "Keep in mind")
                    Text(algorithm.caveat).font(.subheadline).foregroundStyle(.secondary)
                }.arenaCard()
            }.padding(20).frame(maxWidth: 650).frame(maxWidth: .infinity)
        }
        .background(ArenaPalette.canvas)
        .navigationTitle(algorithm.shortName).navigationBarTitleDisplayMode(.inline)
        .task { load() }
        .sheet(item: $activity) { StudySessionView(activity: $0, learning: learning) }
    }

    private func load() {
        do {
            activities = try StudyCatalog.activities(for: algorithm, mode: mode)
            loadError = nil
        } catch {
            loadError = "These activities couldn’t be loaded. Try again."
        }
    }
}
