import AlgorithmArenaCore
import AlgorithmArenaProgression
import Foundation

private struct Failure: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) { self.description = description }
}

@MainActor private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
  if !condition() { throw Failure(message) }
}

@MainActor private struct Fixture {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent("learning-store-\(UUID())")
  let suite = "learning-store-\(UUID())"
  var defaults: UserDefaults { UserDefaults(suiteName: suite)! }
  var repository: LearningProgressRepository {
    LearningProgressRepository(url: directory.appendingPathComponent("nested/progress.json"))
  }
  func cleanup() {
    try? FileManager.default.removeItem(at: directory)
    defaults.removePersistentDomain(forName: suite)
  }
  func store() -> LearningStore { LearningStore(repository: repository, defaults: defaults) }
}

@MainActor private func correctAnswersAndQuestClaimsSaveOnce() throws {
  let fixture = Fixture()
  defer { fixture.cleanup() }
  let store = fixture.store()
  let activity = try StudyCatalog.activity(algorithm: .bfs, mode: .lesson, ordinal: 0)
  try expect(store.answer(activity.correct, in: activity) == true, "Correct answer should save")
  try expect(store.profile.xp == 50 && store.notice != nil, "Saved completion should publish its reward")
  let saved = try fixture.repository.load()
  try expect(saved == store.profile, "Published profile must already exist on disk")
  store.notice = nil
  try expect(store.answer(activity.correct, in: activity) == true, "Review accepts the correct answer")
  try expect(store.profile.xp == 50 && store.notice == nil, "Review must not repeat the reward notice")
  let quest = LearningQuest.all.first { $0.id == "firstSteps" }!
  store.claim(quest)
  try expect(store.profile.xp == 100 && store.pendingQuests == 0, "First lesson quest should claim once")
  let restored = fixture.store()
  restored.claim(quest)
  try expect(restored.profile.xp == 100 && restored.notice == nil, "Relaunch must preserve reward deduplication")
}

@MainActor private func failedWriteDoesNotPublishRewardsOrPreferences() throws {
  let fixture = Fixture()
  defer { fixture.cleanup() }
  let store = fixture.store()
  try FileManager.default.createDirectory(at: fixture.directory, withIntermediateDirectories: true)
  let blocker = fixture.repository.url.deletingLastPathComponent()
  try Data("not a directory".utf8).write(to: blocker)
  let activity = try StudyCatalog.activity(algorithm: .bfs, mode: .lesson, ordinal: 0)
  try expect(store.answer(activity.correct, in: activity) == nil, "Failed persistence must return no confirmed answer")
  try expect(store.profile.xp == 0 && store.notice == nil && store.storageError != nil,
    "Failed writes may not publish XP or celebrations")
  var preferences = store.profile.preferences
  preferences.beginnerGuide = false
  store.savePreferences(preferences)
  try expect(store.profile.preferences.beginnerGuide, "Failed preference write must leave the old setting")
  try FileManager.default.removeItem(at: blocker)
  try expect(store.answer(activity.correct, in: activity) == true, "Retry should save after storage recovers")
  try expect(store.profile.xp == 50 && store.storageError == nil, "Recovered write should award once and clear the error")
}

@MainActor private func damagedSaveRequiresExplicitReloadAndStaysUntouched() throws {
  let fixture = Fixture()
  defer { fixture.cleanup() }
  try FileManager.default.createDirectory(at: fixture.repository.url.deletingLastPathComponent(), withIntermediateDirectories: true)
  let damaged = Data("damaged save".utf8)
  try damaged.write(to: fixture.repository.url)
  let store = fixture.store()
  let activity = try StudyCatalog.activity(algorithm: .dijkstra, mode: .lesson, ordinal: 0)
  try expect(store.storageError != nil, "A damaged profile must show a recoverable error")
  try expect(store.answer(activity.correct, in: activity) == nil, "Do not save over unreadable progress")
  let unchanged = try Data(contentsOf: fixture.repository.url)
  try expect(unchanged == damaged, "Damaged data must remain intact for recovery")
  try fixture.repository.save(LearningProfile())
  store.reload()
  try expect(store.answer(activity.correct, in: activity) == true, "Reload should recover after a valid save is restored")
}

@MainActor private func nicknameComesOnlyFromExistingProfileEditor() throws {
  let fixture = Fixture()
  defer { fixture.cleanup() }
  var old = LearningProfile()
  old.nickname = "Old learning name"
  try fixture.repository.save(old)
  fixture.defaults.set("Current player", forKey: "nickname")
  let store = fixture.store()
  try expect(store.profile.nickname == "Current player", "Existing AppStorage identity is authoritative at launch")
  fixture.defaults.set("Edited player", forKey: "nickname")
  store.syncNickname()
  try expect(store.profile.nickname == "Edited player", "Sync should reflect the existing profile editor")
  try expect(fixture.defaults.string(forKey: "nickname") == "Edited player", "Learning may not overwrite AppStorage")
  store.reload()
  try expect(store.profile.nickname == "Edited player", "Reload must keep the same identity")
}

private let room = UUID(uuidString: "40000000-0000-0000-0000-000000000001")!
private let host = UUID(uuidString: "40000000-0000-0000-0000-000000000002")!
private let guest = UUID(uuidString: "40000000-0000-0000-0000-000000000003")!

private func snapshot(_ revision: Int, _ phase: DuelPhase = .finished) throws -> DuelSnapshot {
  let trace = try SearchEngine.search(StudyCatalog.scenario(), algorithm: .dijkstra)
  return DuelSnapshot(id: room, roomCode: "ABC123", creatorID: host, viewerID: host,
    revision: revision, phase: phase, roundIndex: 2, roundCount: 3, algorithm: .dijkstra,
    players: [DuelPlayer(id: host, nickname: "Host", ready: true, score: 300, submitted: true, hasContinued: true),
      DuelPlayer(id: guest, nickname: "Guest", ready: true, score: 200, submitted: true, hasContinued: true)],
    reveal: DuelReveal(correctNodeID: "C", explanation: "Lowest cost", trace: trace, answers: [
      DuelAnswer(playerID: host, answerNodeID: "C", correct: true, points: 100),
      DuelAnswer(playerID: guest, answerNodeID: "B", correct: false, points: 0)]))
}

@MainActor private func liveDuelResultsAndRematchesPersistWithoutDuplicateRewards() throws {
  let fixture = Fixture()
  defer { fixture.cleanup() }
  let first = fixture.store()
  first.recordDuel(nil)
  first.recordDuel(try snapshot(10, .incomplete))
  try expect(first.profile.xp == 0, "An absent or incomplete duel earns no XP")
  first.recordDuel(try snapshot(20))
  try expect(first.profile.xp == 60 && first.profile.unlockedTitles.contains("champion"), "A final real win earns its local rewards")
  let restored = fixture.store()
  restored.recordDuel(try snapshot(20))
  restored.recordDuel(try snapshot(21))
  try expect(restored.profile.xp == 60 && restored.notice == nil, "Relaunch and post-finish revisions must not repeat rewards")
  restored.recordDuel(try snapshot(22, .lobby))
  let rematchRestored = fixture.store()
  rematchRestored.recordDuel(try snapshot(40))
  try expect(rematchRestored.profile.xp == 120, "A rematch in the same room should get its own completion reward")
  let persisted = try fixture.repository.load()
  try expect(persisted.completedLiveMatches.count == 2 && persisted.xp == 120, "Both result identities must persist")
}

@MainActor private func failedFinalRewardRetriesWhenProgressReloads() throws {
  let fixture = Fixture()
  defer { fixture.cleanup() }
  let store = fixture.store()
  try FileManager.default.createDirectory(at: fixture.directory, withIntermediateDirectories: true)
  let blocker = fixture.repository.url.deletingLastPathComponent()
  try Data("not a directory".utf8).write(to: blocker)
  store.recordDuel(try snapshot(20))
  try expect(store.profile.xp == 0 && store.storageError != nil && store.notice == nil,
    "A failed final reward write must leave XP and celebrations unchanged")
  store.recordDuel(nil)
  try FileManager.default.removeItem(at: blocker)
  store.reload()
  try expect(store.profile.xp == 60 && store.storageError == nil && store.notice != nil,
    "Loading again must reconcile the retained final without another server snapshot")
  let saved = try fixture.repository.load()
  try expect(saved.xp == 60 && saved.completedLiveMatches.count == 1,
    "Recovered final reward must be persisted once")
  store.notice = nil
  store.reload()
  try expect(store.profile.xp == 60 && store.notice == nil,
    "Repeated loading must not repeat the recovered reward")
}

@MainActor private func failedFinalSurvivesStartingARematchBeforeRecovery() throws {
  let fixture = Fixture()
  defer { fixture.cleanup() }
  let store = fixture.store()
  try FileManager.default.createDirectory(at: fixture.directory, withIntermediateDirectories: true)
  let blocker = fixture.repository.url.deletingLastPathComponent()
  try Data("not a directory".utf8).write(to: blocker)
  store.recordDuel(try snapshot(20))
  store.recordDuel(try snapshot(21, .lobby))
  try expect(store.profile.xp == 0 && store.storageError != nil,
    "Unwritable storage must not publish either queued transition")
  try FileManager.default.removeItem(at: blocker)
  store.reload()
  try expect(store.profile.xp == 60 && store.profile.completedLiveMatches.count == 1,
    "Recovery must save the failed finish before the newer rematch lobby")
  store.recordDuel(try snapshot(40))
  try expect(store.profile.xp == 120 && store.profile.completedLiveMatches.count == 2,
    "The rematch must still receive a separate reward after ordered recovery")
  store.notice = nil
  store.reload()
  try expect(store.profile.xp == 120 && store.notice == nil,
    "Repeated recovery must not replay either queued reward")
}

@main @MainActor struct LearningStoreChecks {
  static func main() throws {
    let checks: [(String, () throws -> Void)] = [
      ("answers, quests, relaunch and duplicate rewards", correctAnswersAndQuestClaimsSaveOnce),
      ("save-before-publish and storage recovery", failedWriteDoesNotPublishRewardsOrPreferences),
      ("damaged save preservation and explicit reload", damagedSaveRequiresExplicitReloadAndStaysUntouched),
      ("existing nickname authority", nicknameComesOnlyFromExistingProfileEditor),
      ("finished duel and rematch persistence", liveDuelResultsAndRematchesPersistWithoutDuplicateRewards),
      ("failed final reward reload recovery", failedFinalRewardRetriesWhenProgressReloads),
      ("failed final preserved across rematch", failedFinalSurvivesStartingARematchBeforeRecovery),
    ]
    for (name, check) in checks {
      try check()
      print("PASS: \(name)")
    }
    print("LearningStore: \(checks.count)/\(checks.count) checks passed")
  }
}
