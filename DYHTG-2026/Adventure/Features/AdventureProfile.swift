import AlgorithmArenaProgression
import SwiftUI

/// Learning rewards share the existing profile editor and player identity.
struct AdventureProfile: View {
    let learning: LearningStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ArenaEyebrow(text: "Your progress")
            LearningXPBar(profile: learning.profile)
            Divider()
            NavigationLink {
                TitleCollection(learning: learning)
            } label: {
                collectionRow(
                    "Player titles", detail: "\(learning.profile.unlockedTitles.count) of \(LearningTitle.all.count) unlocked",
                    symbol: "seal.fill"
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.titles")
            NavigationLink {
                AchievementCollection(learning: learning)
            } label: {
                collectionRow(
                    "Achievements", detail: "\(learning.profile.achievements.count) of \(LearningAchievement.all.count) earned",
                    symbol: "medal.fill"
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile.achievements")
            HStack(spacing: 14) {
                Text("\(learning.profile.completedLessons.count)/15 lessons")
                Text("\(learning.profile.practice.count)/15 practice")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            Toggle("Beginner tips", isOn: Binding(
                get: { learning.profile.preferences.beginnerGuide },
                set: { enabled in
                    var preferences = learning.profile.preferences
                    preferences.beginnerGuide = enabled
                    learning.savePreferences(preferences)
                }
            ))
            .tint(Color.arenaAccent)
            .accessibilityIdentifier("profile.beginnerTips")
        }
        .arenaCard()
    }

    private func collectionRow(_ title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(ArenaPalette.ink)
                .frame(width: 42, height: 42)
                .background(ArenaPalette.mint, in: .rect(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}

struct TitleCollection: View {
    let learning: LearningStore

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    ArenaEyebrow(text: "\(learning.profile.unlockedTitles.count) of \(LearningTitle.all.count) unlocked")
                    Text("A title worth earning.")
                        .font(.system(.title, design: .rounded, weight: .bold))
                    Text("Choose a title to show on your profile.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 4)
                ForEach(LearningTitle.all) { title in
                    titleCard(title)
                }
                Text("Cosmetics never change your duel score.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .background(ArenaPalette.canvas)
        .navigationTitle("Player titles")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func titleCard(_ title: LearningTitle) -> some View {
        let unlocked = learning.profile.unlockedTitles.contains(title.id)
        let equipped = learning.profile.equippedTitle == title.id
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: equipped ? "checkmark.seal.fill" : unlocked ? "seal.fill" : "lock.fill")
                    .font(.title2)
                    .foregroundStyle(unlocked ? ArenaPalette.ink : Color.secondary)
                    .frame(width: 48, height: 48)
                    .background(unlocked ? ArenaPalette.mint : ArenaPalette.canvas, in: .rect(cornerRadius: 15))
                VStack(alignment: .leading, spacing: 6) {
                    Text(title.name).font(.headline)
                    Text(title.requirement).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            if unlocked {
                Button(equipped ? "Equipped" : "Equip title", systemImage: equipped ? "checkmark" : "sparkles") {
                    learning.equip(title)
                }
                .buttonStyle(ArenaActionStyle(prominent: !equipped))
                .disabled(equipped)
                .accessibilityIdentifier("profile.title.\(title.id)")
            } else {
                Text("Keep learning to unlock")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .arenaCard()
    }
}

struct AchievementCollection: View {
    let learning: LearningStore

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    ArenaEyebrow(text: "\(learning.profile.achievements.count) of \(LearningAchievement.all.count) earned")
                    Text("Make your mark.")
                        .font(.system(.title, design: .rounded, weight: .bold))
                    Text("Milestones from your lessons, practice and duels.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 4)
                ForEach(LearningAchievement.all) { badge in
                    achievementCard(badge)
                }
            }
            .padding(20)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .background(ArenaPalette.canvas)
        .navigationTitle("Achievements")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func achievementCard(_ badge: LearningAchievement) -> some View {
        let unlocked = learning.profile.achievements.contains(badge.id)
        return HStack(alignment: .top, spacing: 14) {
            Image(systemName: unlocked ? "medal.fill" : "lock.fill")
                .font(.title2)
                .foregroundStyle(unlocked ? ArenaPalette.ink : Color.secondary)
                .frame(width: 52, height: 52)
                .background(unlocked ? ArenaPalette.amber : ArenaPalette.canvas, in: .rect(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 7) {
                Text(badge.name).font(.headline)
                Text(badge.requirement).font(.subheadline).foregroundStyle(.secondary)
                Label(unlocked ? "Earned" : "Not earned yet", systemImage: unlocked ? "checkmark.circle.fill" : "circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .arenaCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("profile.achievement.\(badge.id)")
    }
}
