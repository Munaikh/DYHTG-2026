import AlgorithmArenaProgression
import SwiftUI

struct AdventureQuests: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Bindable var learning: LearningStore
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          AdventureHeading(
            title: "Small goals.\nReal progress.",
            subtitle: "No timers. No streaks to lose. Learn your way.")
          ForEach(LearningQuest.all) { quest in
            let progress = quest.progress(in: learning.profile)
            let claimed = learning.profile.claimedQuests.contains(quest.id)
            AdventureCard {
              VStack(alignment: .leading, spacing: 12) {
                HStack {
                  Text(quest.name).font(.title3.bold())
                  Spacer()
                  Image(systemName: claimed ? "checkmark.seal.fill" : "flag.fill").foregroundStyle(
                    .secondary)
                }
                Text(quest.instruction).foregroundStyle(.secondary)
                ProgressView(value: Double(progress), total: Double(quest.goal)).accessibilityLabel(
                  "\(progress) of \(quest.goal)"
                )
                .animation(
                  reduceMotion || learning.profile.preferences.reduceMotion
                    ? nil : .easeInOut(duration: 0.4), value: progress)
                HStack {
                  Text("\(progress) / \(quest.goal)").monospacedDigit()
                  Spacer()
                  Text("+\(quest.xp) XP").fontWeight(.semibold)
                }.font(.subheadline)
                if ["campus", "nodeHunter", "explorer"].contains(quest.id) {
                  Label(
                    quest.id == "campus"
                      ? "Includes a cosmetic achievement" : "Includes a player title",
                    systemImage: "seal.fill"
                  ).font(.caption).foregroundStyle(.secondary)
                }
                if claimed {
                  Label("Reward claimed", systemImage: "checkmark.circle.fill").font(.subheadline)
                    .foregroundStyle(.secondary)
                } else if quest.canClaim(in: learning.profile) {
                  Button("Claim reward") { learning.claim(quest) }.buttonStyle(
                    AdventureButtonStyle())
                } else {
                  Text("Keep learning to unlock this reward.").font(.footnote).foregroundStyle(
                    .secondary)
                }
              }
            }
          }
        }.padding(20).frame(maxWidth: 650).frame(maxWidth: .infinity)
      }.background(Color.arenaCanvas).navigationTitle("Quests")
    }
  }
}
