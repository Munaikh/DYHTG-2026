import AlgorithmArenaCore
import AlgorithmArenaProgression
import Foundation
import Testing

private let roomID = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
private let viewerID = UUID(uuidString: "30000000-0000-0000-0000-000000000002")!
private let opponentID = UUID(uuidString: "30000000-0000-0000-0000-000000000003")!

private func duel(
  revision: Int = 20, phase: DuelPhase = .finished,
  roundIndex: Int = 2, roundCount: Int = 3,
  viewerScore: Int = 300, opponentScore: Int = 200,
  viewer: UUID = viewerID, playerCount: Int = 2,
  submitted: Bool = true, continued: Bool = true, released: Bool = true,
  duplicatePlayers: Bool = false, duplicateAnswers: Bool = false
) throws -> DuelSnapshot {
  let scenario = try StudyCatalog.scenario()
  let trace = try SearchEngine.search(scenario, algorithm: .dijkstra)
  let players = [
    DuelPlayer(id: viewerID, nickname: "One", ready: true, score: viewerScore,
      submitted: submitted, hasContinued: continued),
    DuelPlayer(id: duplicatePlayers ? viewerID : opponentID, nickname: "Two", ready: true,
      score: opponentScore, submitted: submitted, hasContinued: continued),
  ]
  let answers = [
    DuelAnswer(playerID: viewerID, answerNodeID: "C", correct: viewerScore > 0,
      points: viewerScore > 0 ? 100 : 0),
    DuelAnswer(playerID: duplicateAnswers ? viewerID : opponentID, answerNodeID: "B",
      correct: opponentScore == 300, points: opponentScore == 300 ? 100 : 0),
  ]
  return DuelSnapshot(id: roomID, roomCode: "ABC123", creatorID: viewerID, viewerID: viewer,
    revision: revision, phase: phase, roundIndex: roundIndex, roundCount: roundCount,
    algorithm: .dijkstra, players: Array(players.prefix(playerCount)),
    reveal: released ? DuelReveal(correctNodeID: "C", explanation: "Lowest cost.",
      trace: trace, answers: answers) : nil)
}

@Test func plotTwistWinDrawAndLossRewardsUseFinalServerScores() throws {
  for (score, won) in [(100, false), (200, false), (300, true)] {
    let snapshot = try duel(viewerScore: score)
    let update = LearningJourney.recordDuel(LearningProfile(), snapshot: snapshot)
    #expect(update.awardedXP == 60)
    #expect(update.profile.completedLiveMatches.count == 1)
    #expect(update.profile.wonLiveMatches.count == (won ? 1 : 0))
    #expect(update.profile.unlockedTitles.contains("champion") == won)
    #expect(update.profile.achievements.contains("victory") == won)
    #expect(LearningJourney.recordDuel(update.profile, snapshot: snapshot).awardedXP == 0)
    let claimed = try LearningJourney.claim(update.profile, questID: "campus")
    #expect(claimed.awardedXP == 50)
    #expect(claimed.profile.achievements.contains("campus"))
    #expect(try LearningJourney.claim(claimed.profile, questID: "campus").awardedXP == 0)
  }
}

@Test func onlyReleasedCompleteTwoPlayerDuelsEarnRewards() throws {
  let excluded = try [
    duel(phase: .lobby), duel(phase: .answering), duel(phase: .reveal),
    duel(phase: .incomplete), duel(roundIndex: 1), duel(roundCount: 2),
    duel(viewer: UUID()), duel(playerCount: 1), duel(submitted: false),
    duel(continued: false), duel(released: false), duel(duplicatePlayers: true),
    duel(duplicateAnswers: true), duel(viewerScore: 400), duel(viewerScore: -100),
    duel(viewerScore: 250), duel(revision: 0),
  ]
  for snapshot in excluded {
    let update = LearningJourney.recordDuel(LearningProfile(), snapshot: snapshot)
    #expect(update.awardedXP == 0)
    #expect(update.profile.completedLiveMatches.isEmpty)
    #expect(update.profile.wonLiveMatches.isEmpty)
    #expect(!update.profile.unlockedTitles.contains("champion"))
    #expect(!update.profile.achievements.contains("victory"))
  }
}

@Test func finalPollingRevisionsAndRelaunchNeverRepeatRewards() throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let repository = LearningProgressRepository(url: directory.appendingPathComponent("progress.json"))
  var profile = LearningJourney.recordDuel(LearningProfile(), snapshot: try duel()).profile
  try repository.save(profile)
  profile = try repository.load()
  // The current backend leaves a finished room finished while incrementing revision.
  for revision in [20, 21, 22, 30, 19, 20] {
    let update = LearningJourney.recordDuel(profile, snapshot: try duel(revision: revision))
    #expect(update.awardedXP == 0)
    profile = update.profile
  }
  #expect(profile.xp == 60)
  #expect(profile.completedLiveMatches.count == 1)
  // A stale lobby receipt must not be mistaken for a rematch.
  profile = LearningJourney.recordDuel(profile, snapshot: try duel(revision: 2, phase: .lobby)).profile
  #expect(LearningJourney.recordDuel(profile, snapshot: try duel(revision: 31)).awardedXP == 0)
}

@Test func observedRematchesGetSeparateExactlyOnceRewardsAcrossRelaunches() throws {
  var profile = LearningJourney.recordDuel(LearningProfile(), snapshot: try duel()).profile
  let rematch = LearningJourney.recordDuel(profile, snapshot: try duel(revision: 21, phase: .lobby))
  #expect(rematch.awardedXP == 0)
  profile = try JSONDecoder().decode(LearningProfile.self, from: JSONEncoder().encode(rematch.profile))
  let second = LearningJourney.recordDuel(profile, snapshot: try duel(revision: 40, viewerScore: 200))
  #expect(second.awardedXP == 60)
  #expect(second.profile.completedLiveMatches.count == 2)
  #expect(second.profile.wonLiveMatches.count == 1)
  #expect(LearningJourney.recordDuel(second.profile, snapshot: try duel(revision: 41, viewerScore: 200)).awardedXP == 0)
  // Rejoining during a rematch can miss the lobby but still observes a new active cycle.
  profile = LearningJourney.recordDuel(second.profile, snapshot: try duel(revision: 48, phase: .answering)).profile
  let third = LearningJourney.recordDuel(profile, snapshot: try duel(revision: 60))
  #expect(third.awardedXP == 60)
  #expect(third.profile.completedLiveMatches.count == 3)
  #expect(third.profile.wonLiveMatches.count == 2)
  #expect(third.profile.xp == 180)
}

@Test func missedWholeRematchIsConservativeWithoutWireGeneration() throws {
  let first = LearningJourney.recordDuel(LearningProfile(), snapshot: try duel()).profile
  // Without any intervening active snapshot, a higher final revision could be a
  // post-finish leave. Do not invent a new match or award duplicate XP.
  let later = LearningJourney.recordDuel(first, snapshot: try duel(revision: 100))
  #expect(later.awardedXP == 0)
  #expect(later.profile.completedLiveMatches.count == 1)
}

@Test func hostedDuelCorpusAwardsEachPlayersReleasedResultsExactlyOnce() throws {
  guard let path = ProcessInfo.processInfo.environment["DUEL_WIRE_PATH"] else { return }
  struct Corpus: Decodable { let snapshots: [DuelSnapshot] }
  let corpus = try ContractJSON.decoder().decode(
    Corpus.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
  let finished = corpus.snapshots.filter { $0.phase == .finished }
  let expected: Set<StudyAlgorithm> = corpus.snapshots.contains { $0.currentRound?.questionID != nil }
    ? Set(StudyAlgorithm.allCases) : [.dijkstra, .aStar]
  #expect(Set(finished.map(\.algorithm)) == expected)
  #expect(Set(finished.map(\.viewerID)).count >= 2)

  // The hosted fixture deliberately interleaves both players' server views.
  // Each installation has its own profile; mixing them into one profile would
  // incorrectly transfer the winner's title to the opponent or duplicate XP.
  var profiles: [UUID: LearningProfile] = [:]
  var completedRooms: [UUID: Set<UUID>] = [:]
  var wonRooms: [UUID: Set<UUID>] = [:]
  for snapshot in corpus.snapshots {
    let viewer = snapshot.viewerID
    let previous = profiles[viewer] ?? LearningProfile()
    let update = LearningJourney.recordDuel(previous, snapshot: snapshot)
    var expectedXP = 0
    if snapshot.phase == .finished,
      completedRooms[viewer, default: []].insert(snapshot.id).inserted
    {
      expectedXP = 60
      let own = try #require(snapshot.players.first { $0.id == viewer })
      let other = try #require(snapshot.players.first { $0.id != viewer })
      if own.score > other.score { wonRooms[viewer, default: []].insert(snapshot.id) }
    }
    #expect(update.awardedXP == expectedXP)
    profiles[viewer] = update.profile
  }
  for (viewer, profile) in profiles {
    let completed = completedRooms[viewer, default: []].count
    let wins = wonRooms[viewer, default: []].count
    #expect(profile.xp == 60 * completed)
    #expect(profile.completedLiveMatches.count == completed)
    #expect(profile.wonLiveMatches.count == wins)
    #expect(profile.unlockedTitles.contains("champion") == (wins > 0))
    #expect(profile.achievements.contains("victory") == (wins > 0))
    // Actual repeated reads/command receipts stay harmless after disk round-trip,
    // including old finished results from a room whose rematch was abandoned.
    var restored = try JSONDecoder().decode(
      LearningProfile.self, from: JSONEncoder().encode(profile))
    for snapshot in finished where snapshot.viewerID == viewer {
      let replayed = LearningJourney.recordDuel(restored, snapshot: snapshot)
      #expect(replayed.awardedXP == 0)
      #expect(replayed.profile.xp == profile.xp)
      #expect(replayed.profile.wonLiveMatches == profile.wonLiveMatches)
      restored = replayed.profile
    }
  }
}
