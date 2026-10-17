import AlgorithmArenaCore
import AlgorithmArenaProgression
import Foundation
import Observation

@MainActor @Observable
final class LearningStore {
  struct RewardNotice: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
  }
  private(set) var profile = LearningProfile()
  private(set) var storageError: String?
  var notice: RewardNotice?
  private let repository: LearningProgressRepository
  private let defaults: UserDefaults
  private var loadSucceeded = false

  init(repository: LearningProgressRepository? = nil, defaults: UserDefaults = .standard) {
    let directory = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("AlgorithmArena", isDirectory: true)
    self.repository =
      repository
      ?? LearningProgressRepository(
        url: directory.appendingPathComponent("learning-progress-v1.json"))
    self.defaults = defaults
    reload()
  }
  var equippedTitle: String {
    LearningTitle.all.first { $0.id == profile.equippedTitle }?.name ?? "Curious learner"
  }
  var pendingQuests: Int { LearningQuest.all.filter { $0.canClaim(in: profile) }.count }
  var nextLesson: StudyActivity? {
    for algorithm in StudyAlgorithm.allCases {
      if let activities = try? StudyCatalog.activities(for: algorithm, mode: .lesson),
        let next = activities.first(where: { !profile.completedLessons.contains($0.id) })
      {
        return next
      }
    }
    return nil
  }
  func reload() {
    do {
      var loaded = try repository.load()
      if let nickname = defaults.string(forKey: "nickname"), (2...20).contains(nickname.count) {
        loaded.nickname = nickname
      }
      profile = loaded
      loadSucceeded = true
      storageError = nil
    } catch {
      loadSucceeded = false
      storageError =
        "Your saved progress couldn’t be opened. The file is unchanged. Try loading it again."
    }
  }
  @discardableResult
  private func commit(_ update: LearningUpdate) -> Bool {
    guard loadSucceeded else { return false }
    do {
      if update.profile != profile { try repository.save(update.profile) }
      let oldLevel = profile.level
      profile = update.profile
      if update.awardedXP > 0 || !update.newTitles.isEmpty || !update.newAchievements.isEmpty {
        let title =
          profile.level > oldLevel ? "Level \(profile.level)!" : "+\(update.awardedXP) learning XP"
        let names = update.newTitles.sorted().compactMap { id in
          LearningTitle.all.first { $0.id == id }?.name
        }
        let detail =
          names.isEmpty
          ? (update.newAchievements.isEmpty
            ? "Your progress is saved." : "New achievement earned. See Profile.")
          : "Title unlocked: \(names.joined(separator: ", "))."
        notice = RewardNotice(title: title, detail: detail)
      }
      storageError = nil
      return true
    } catch {
      storageError =
        "Progress wasn’t saved. Free some storage and try again; no reward has been added."
      return false
    }
  }
  func answer(_ node: NodeID, in activity: StudyActivity) -> Bool? {
    do {
      let update = try LearningJourney.answer(profile, activityID: activity.id, node: node)
      return commit(update) ? update.correct : nil
    } catch {
      storageError = "That answer isn’t available. Choose one of the labelled points."
      return nil
    }
  }
  func hint(for activity: StudyActivity) {
    do { _ = commit(try LearningJourney.hint(profile, activityID: activity.id)) } catch {
      storageError = "The hint couldn’t be opened. Try again."
    }
  }
  func claim(_ quest: LearningQuest) {
    do { _ = commit(try LearningJourney.claim(profile, questID: quest.id)) } catch {
      storageError = "Finish this quest before claiming its reward."
    }
  }
  func equip(_ title: LearningTitle) {
    do { _ = commit(try LearningJourney.equip(profile, titleID: title.id)) } catch {
      storageError = "This title is locked. Its card explains how to earn it."
    }
  }
  func savePreferences(_ preferences: LearningPreferences) {
    var copy = profile
    copy.preferences = preferences
    saveProfile(copy)
  }
  func saveNickname(_ nickname: String) -> Bool {
    let value = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
    guard (2...20).contains(value.count) else {
      storageError = "Choose a nickname with 2–20 characters."
      return false
    }
    var copy = profile
    copy.nickname = value
    guard saveProfile(copy) else { return false }
    defaults.set(value, forKey: "nickname")
    return true
  }
  @discardableResult
  private func saveProfile(_ copy: LearningProfile) -> Bool {
    guard loadSucceeded else { return false }
    do {
      try repository.save(copy)
      profile = copy
      storageError = nil
      return true
    } catch {
      storageError = "Changes couldn’t be saved. Please try again."
      return false
    }
  }
  func prepareCampusNickname() {
    defaults.set(profile.nickname, forKey: "nickname")
  }
  func syncCampusNickname() {
    guard
      let value = defaults.string(forKey: "nickname")?.trimmingCharacters(
        in: .whitespacesAndNewlines),
      (2...20).contains(value.count), value != profile.nickname
    else { return }
    _ = saveNickname(value)
  }
  func recordMatch(_ snapshot: MatchSnapshot?, live: Bool) {
    guard let snapshot else { return }
    _ = commit(LearningJourney.completedMatch(profile, snapshot: snapshot, live: live))
  }
}
