import AlgorithmArenaCore
import AlgorithmArenaFixtures
import AlgorithmArenaProgression
import Foundation
import Testing

private func finish(
  _ p: LearningProfile, _ algorithm: StudyAlgorithm, _ mode: ActivityMode, _ ordinal: Int
) throws -> LearningUpdate {
  let activity = try StudyCatalog.activity(algorithm: algorithm, mode: mode, ordinal: ordinal)
  return try LearningJourney.answer(p, activityID: activity.id, node: activity.correct)
}

@Test func rewardsAreEarnedOnceAndModulesUnlockTitles() throws {
  var profile = LearningProfile()
  #expect(throws: StudyError.ineligibleReward) {
    try LearningJourney.claim(profile, questID: "firstSteps")
  }
  #expect(throws: StudyError.lockedTitle) {
    try LearningJourney.equip(profile, titleID: "champion")
  }
  for ordinal in 0..<3 {
    let update = try finish(profile, .bfs, .lesson, ordinal)
    #expect(update.correct == true)
    #expect(update.awardedXP == (ordinal == 2 ? 150 : 50))
    profile = update.profile
    #expect(try finish(profile, .bfs, .lesson, ordinal).awardedXP == 0)
  }
  #expect(profile.xp == 250)
  #expect(profile.unlockedTitles.isSuperset(of: ["curious", "rookie", "nodeExplorer"]))
  profile = try LearningJourney.equip(profile, titleID: "nodeExplorer").profile
  #expect(profile.equippedTitle == "nodeExplorer")
  profile = try LearningJourney.claim(profile, questID: "firstSteps").profile
  #expect(profile.xp == 300)
  #expect(profile.level == 3)
  #expect(try LearningJourney.claim(profile, questID: "firstSteps").awardedXP == 0)
  #expect(!profile.unlockedTitles.contains("champion"))
}

@Test func mistakesAndHintsDriveAchievementsAndQuestEligibility() throws {
  var profile = LearningProfile()
  let activity = try StudyCatalog.activity(algorithm: .aStar, mode: .practice, ordinal: 0)
  let wrong = try #require(activity.choices.first { $0 != activity.correct })
  profile = try LearningJourney.answer(profile, activityID: activity.id, node: wrong).profile
  for _ in 0..<5 { profile = try LearningJourney.hint(profile, activityID: activity.id).profile }
  #expect(profile.attempts[activity.id]?.mistakes == 1)
  #expect(profile.attempts[activity.id]?.hints == 3)
  #expect(profile.xp == 0)
  profile = try finish(profile, .aStar, .practice, 0).profile
  #expect(profile.practice[activity.id]?.mistakes == 1)
  #expect(profile.practice[activity.id]?.hints == 3)
  #expect(!profile.achievements.contains("perfect"))
  #expect(!profile.achievements.contains("noHints"))
  for ordinal in 1...2 { profile = try finish(profile, .aStar, .practice, ordinal).profile }
  #expect(profile.xp == 60)
  #expect(profile.achievements.isSuperset(of: ["perfect", "noHints"]))
  for questID in ["noHints", "nodeHunter"] {
    profile = try LearningJourney.claim(profile, questID: questID).profile
  }
  #expect(profile.xp == 260)
  #expect(profile.unlockedTitles.contains("nodeHunter"))
  #expect(try LearningJourney.hint(profile, activityID: activity.id).profile == profile)
  #expect(throws: StudyError.invalidAnswer) {
    try LearningJourney.answer(profile, activityID: activity.id, node: "INVALID")
  }
}

@Test func allLearningContentCanCompleteAndUnlockItsRewards() throws {
  var profile = LearningProfile()
  for algorithm in StudyAlgorithm.allCases {
    for mode in [ActivityMode.lesson, .practice] {
      for ordinal in 0..<3 { profile = try finish(profile, algorithm, mode, ordinal).profile }
    }
  }
  #expect(profile.lessonCount == 15)
  #expect(profile.practice.count == 15)
  #expect(profile.xp == 1550)
  #expect(profile.completedModules.count == 5)
  #expect(profile.achievements.isSuperset(of: ["explorer", "graphs", "perfect", "noHints"]))
  for quest in LearningQuest.all where quest.id != "campus" {
    profile = try LearningJourney.claim(profile, questID: quest.id).profile
  }
  #expect(profile.xp == 2150)
  #expect(
    profile.unlockedTitles.isSuperset(of: [
      "seeker", "explorer", "routeMaster", "detective", "ace", "depthDiver",
    ]))
  #expect(!profile.achievements.contains("victory"))
}

@Test func onlyFinalRealMatchesAwardLocalXP() throws {
  let initial = LearningProfile()
  for fixture in MatchFixture.allCases {
    let snapshot = ArenaFixtures.snapshot(fixture, algorithm: .aStar)
    #expect(
      LearningJourney.completedMatch(initial, snapshot: snapshot, live: false).profile == initial)
    let update = LearningJourney.completedMatch(initial, snapshot: snapshot, live: true)
    if fixture == .finished || fixture == .draw {
      #expect(update.awardedXP == 60)
      #expect(
        LearningJourney.completedMatch(update.profile, snapshot: snapshot, live: true).awardedXP
          == 0)
      #expect(update.profile.unlockedTitles.contains("champion") == (fixture == .finished))
      #expect(update.profile.achievements.contains("victory") == (fixture == .finished))
      let claimed = try LearningJourney.claim(update.profile, questID: "campus")
      #expect(claimed.awardedXP == 50)
      #expect(claimed.profile.achievements.contains("campus"))
    } else {
      #expect(update.profile == initial)
    }
  }
}

@Test func levelThresholdsAreStable() {
  #expect(LearningLevels.level(for: 0) == 1)
  #expect(LearningLevels.level(for: 99) == 1)
  #expect(LearningLevels.level(for: 100) == 2)
  #expect(LearningLevels.level(for: 299) == 2)
  #expect(LearningLevels.level(for: 300) == 3)
  #expect(LearningLevels.fraction(for: 50) == 0.5)
  #expect(LearningLevels.fraction(for: 100) == 0)
}

@Test func persistenceRoundTripsAndPreservesDamagedOrFutureFiles() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let repository = LearningProgressRepository(
    url: directory.appendingPathComponent("nested/progress.json"))
  #expect(try repository.load() == LearningProfile())
  var profile = try finish(LearningProfile(), .dijkstra, .lesson, 0).profile
  profile.preferences.reduceMotion = true
  profile.preferences.largerControls = true
  profile.preferences.appearance = "dark"
  profile.nickname = "Tester"
  profile = try LearningJourney.equip(profile, titleID: "rookie").profile
  try repository.save(profile)
  #expect(try repository.load() == profile)
  #expect(try finish(repository.load(), .dijkstra, .lesson, 0).awardedXP == 0)
  profile.schemaVersion = 999
  try repository.save(profile)
  let future = try Data(contentsOf: repository.url)
  #expect(throws: StudyError.unsupportedVersion) { try repository.load() }
  #expect(try Data(contentsOf: repository.url) == future)
  let damaged = Data("damaged save".utf8)
  try damaged.write(to: repository.url)
  #expect(throws: (any Error).self) { try repository.load() }
  #expect(try Data(contentsOf: repository.url) == damaged)
}

@Test func contentIdentifiersCannotAliasDuplicateRewards() {
  for id in [
    "indoor-v1.bfs.lesson.00", "indoor-v1.bfs.lesson.-1", "indoor-v2.bfs.lesson.0",
    "indoor-v1.bfs.lesson.3", "indoor-v1.unknown.lesson.0",
  ] {
    #expect(throws: StudyError.unknownActivity) { try StudyCatalog.activity(id: id) }
  }
}
