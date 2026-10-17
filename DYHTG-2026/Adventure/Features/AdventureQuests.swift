import AlgorithmArenaProgression
import SwiftUI

struct AdventureQuests: View {
    let learning: LearningStore
    var dismissable = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    header
                    ForEach(LearningQuest.all) { quest in
                        questCard(quest)
                    }
                }
                .padding(20)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .background(ArenaPalette.canvas)
            .navigationTitle("Quests")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if dismissable {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                            .accessibilityIdentifier("quests.close")
                    }
                }
            }
        }
        .modifier(LearningNoticeModifier(learning: learning))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            ArenaEyebrow(text: "Your next unlock", color: ArenaPalette.mint)
            Text("Small goals.\nSmarter moves.")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
            Text("Learn, practice and take on a Plot Twist Duel.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
            HStack {
                Label("\(learning.profile.claimedQuests.count)/\(LearningQuest.all.count) claimed", systemImage: "checkmark.seal.fill")
                Spacer(minLength: 8)
                if learning.pendingQuests > 0 {
                    Text("\(learning.pendingQuests) ready")
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ArenaPalette.mint)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ArenaPalette.ink, in: .rect(cornerRadius: 24))
    }

    private func questCard(_ quest: LearningQuest) -> some View {
        let progress = quest.progress(in: learning.profile)
        let claimed = learning.profile.claimedQuests.contains(quest.id)
        let canClaim = quest.canClaim(in: learning.profile)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Text(quest.name).font(.system(.title3, design: .rounded, weight: .bold))
                Spacer(minLength: 0)
                Image(systemName: claimed ? "checkmark.seal.fill" : "flag.fill")
                    .font(.headline)
                    .foregroundStyle(ArenaPalette.ink)
                    .frame(width: 38, height: 38)
                    .background(claimed ? ArenaPalette.mint : ArenaPalette.amber, in: .rect(cornerRadius: 12))
            }
            Text(quest.instruction).font(.subheadline).foregroundStyle(.secondary)
            ProgressView(value: Double(progress), total: Double(quest.goal))
                .tint(Color.arenaAccent)
                .accessibilityLabel("\(progress) of \(quest.goal)")
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: progress)
            HStack {
                Text("\(progress) / \(quest.goal)").monospacedDigit()
                Spacer()
                Text("+\(quest.xp) XP").fontWeight(.bold)
            }
            .font(.subheadline)
            if ["campus", "nodeHunter", "explorer"].contains(quest.id) {
                Label(
                    quest.id == "campus" ? "Achievement reward" : "Player title reward",
                    systemImage: quest.id == "campus" ? "medal.fill" : "seal.fill"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            }
            if claimed {
                Label("Reward claimed", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else if canClaim {
                Button("Claim reward", systemImage: "sparkles") { learning.claim(quest) }
                    .buttonStyle(ArenaActionStyle())
                    .accessibilityIdentifier("quests.claim.\(quest.id)")
            }
        }
        .arenaCard()
    }
}
