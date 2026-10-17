import AlgorithmArenaProgression
import SwiftUI

struct AdventureProfile: View {
  @Bindable var learning: LearningStore
  @State private var nickname = ""
  @State private var savedName = false
  @AppStorage(ArenaSoundPlayer.preferenceKey) private var soundsEnabled = true
  @State private var samplePlayed: Bool?
  var body: some View {
    NavigationStack {
      List {
        Section {
          VStack(alignment: .leading, spacing: 14) {
            Label(learning.profile.nickname, systemImage: "person.crop.circle.fill").font(
              .title2.bold())
            Text(learning.equippedTitle).font(.headline).foregroundStyle(.secondary)
            LearningXPBar(profile: learning.profile)
          }.padding(.vertical, 8)
        }
        Section("Your nickname") {
          TextField("Nickname", text: $nickname).textContentType(.nickname)
            .textInputAutocapitalization(.words).autocorrectionDisabled()
            .onChange(of: nickname) { _, value in
              if value.count > 20 { nickname = String(value.prefix(20)) }
              savedName = false
            }
          Button(savedName ? "Nickname saved" : "Save nickname") {
            savedName = learning.saveNickname(nickname)
          }
          .disabled(nickname.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
        }
        Section {
          NavigationLink("Choose your title") { TitleCollection(learning: learning) }
          NavigationLink("Achievements") { AchievementCollection(learning: learning) }
          LabeledContent(
            "Lessons complete", value: "\(learning.profile.completedLessons.count) / 15")
          LabeledContent(
            "Practice puzzles solved", value: "\(learning.profile.practice.count) / 15")
        } header: {
          Text("Your collection")
        } footer: {
          Text("Titles and badges are cosmetic. They never change match points.")
        }
        Section("Make it comfortable") {
          Toggle("Beginner guide", isOn: preference(\.beginnerGuide))
          Toggle("Reduce motion", isOn: preference(\.reduceMotion))
          Toggle("Larger controls", isOn: preference(\.largerControls))
          Picker(
            "Appearance",
            selection: Binding(
              get: { learning.profile.preferences.appearance },
              set: { value in
                var p = learning.profile.preferences
                p.appearance = value
                learning.savePreferences(p)
              })
          ) {
            Text("Use device setting").tag("system")
            Text("Light").tag("light")
            Text("Dark").tag("dark")
          }
          Text(
            "Text follows your iPhone’s text-size setting. Every graph also has a text description."
          ).font(.footnote).foregroundStyle(.secondary)
        }
        Section {
          Toggle("Button sounds", isOn: $soundsEnabled)
            .onChange(of: soundsEnabled) { _, enabled in
              samplePlayed = nil
              if !enabled { ArenaSoundPlayer.shared.stop() }
            }
          Button("Play sample sound", systemImage: "speaker.wave.2.fill") {
            samplePlayed = ArenaSoundPlayer.shared.play(.success)
          }.disabled(!soundsEnabled)
          if let samplePlayed {
            Label(
              samplePlayed ? "Sample played" : "Sound unavailable. Try again.",
              systemImage: samplePlayed ? "checkmark.circle" : "speaker.slash"
            )
            .font(.footnote).foregroundStyle(.secondary)
          }
        } header: {
          Text("Sound")
        } footer: {
          Text("Soft tap and reward sounds follow Silent Mode and your device volume.")
        }
        Section("Your privacy") {
          Text(
            "Learning progress is saved on this device. Learn and Practice do not request your location or create an online profile."
          )
          Text(
            "Campus multiplayer uses an anonymous player session. Campus mode uses location to help with check-ins."
          ).font(.footnote).foregroundStyle(.secondary)
        }
      }.navigationTitle("Profile")
        .onAppear { nickname = learning.profile.nickname }
    }
  }
  private func preference(_ keyPath: WritableKeyPath<LearningPreferences, Bool>) -> Binding<Bool> {
    Binding(
      get: { learning.profile.preferences[keyPath: keyPath] },
      set: { value in
        var p = learning.profile.preferences
        p[keyPath: keyPath] = value
        learning.savePreferences(p)
      })
  }
}
struct TitleCollection: View {
  @Bindable var learning: LearningStore
  var body: some View {
    ScrollView {
      VStack(spacing: 16) {
        Text("Earn a title, then choose it for your profile.").font(.body).foregroundStyle(
          .secondary
        ).frame(maxWidth: .infinity, alignment: .leading)
        ForEach(LearningTitle.all) { title in
          let unlocked = learning.profile.unlockedTitles.contains(title.id)
          let equipped = learning.profile.equippedTitle == title.id
          AdventureCard {
            VStack(alignment: .leading, spacing: 12) {
              Label(
                title.name,
                systemImage: equipped ? "checkmark.seal.fill" : unlocked ? "seal.fill" : "lock.fill"
              )
              .font(.headline)
              Text(title.requirement).font(.subheadline).foregroundStyle(.secondary)
              if unlocked {
                Button(equipped ? "Equipped" : "Equip title") { learning.equip(title) }
                  .buttonStyle(AdventureButtonStyle(secondary: !equipped)).disabled(equipped)
              } else {
                Text("Locked").font(.caption.bold()).foregroundStyle(.secondary)
              }
            }
          }
        }
      }.padding(20).frame(maxWidth: 650).frame(maxWidth: .infinity)
    }.background(Color.arenaCanvas).navigationTitle("Titles")
  }
}
struct AchievementCollection: View {
  let learning: LearningStore
  var body: some View {
    List(LearningAchievement.all) { badge in
      let unlocked = learning.profile.achievements.contains(badge.id)
      HStack(alignment: .top, spacing: 14) {
        Image(systemName: unlocked ? "medal.fill" : "lock.circle").font(.title2)
          .foregroundStyle(unlocked ? Color.primary : .secondary).accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 6) {
          Text(badge.name).font(.headline)
          Text(badge.requirement).font(.body).foregroundStyle(.secondary)
          Text(unlocked ? "Earned" : "Not earned yet").font(.caption.bold())
        }
      }.padding(.vertical, 8).accessibilityElement(children: .combine)
    }.navigationTitle("Achievements")
  }
}
