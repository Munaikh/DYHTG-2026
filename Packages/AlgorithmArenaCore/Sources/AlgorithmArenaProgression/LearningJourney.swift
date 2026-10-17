import AlgorithmArenaCore
import Foundation

public struct LearningUpdate: Equatable, Sendable {
  public let profile: LearningProfile
  public let correct: Bool?
  public let awardedXP: Int
  public let newTitles: Set<String>
  public let newAchievements: Set<String>
}

public enum LearningJourney {
  public static func answer(_ profile: LearningProfile, activityID: String, node: NodeID) throws
    -> LearningUpdate
  {
    let activity = try StudyCatalog.activity(id: activityID)
    guard activity.choices.contains(node) else { throw StudyError.invalidAnswer }
    var p = profile
    let correct = node == activity.correct
    if !p.completedActivities.contains(activityID) {
      if correct {
        let attempt = p.attempts[activityID] ?? StudyAttempt()
        if activity.mode == .lesson {
          p.completedLessons.insert(activityID)
        } else {
          p.practice[activityID] = PracticeCompletion(
            activityID: activityID, algorithm: activity.algorithm, mistakes: attempt.mistakes,
            hints: attempt.hints)
        }
        p.rewards["activity:\(activityID)"] = activity.reward
        if p.completedModules.contains(activity.algorithm) {
          p.rewards["module:\(activity.algorithm.rawValue)"] = 100
        }
      } else {
        p.attempts[activityID, default: StudyAttempt()].mistakes += 1
      }
    }
    return update(old: profile, new: p, correct: correct)
  }
  public static func hint(_ profile: LearningProfile, activityID: String) throws -> LearningUpdate {
    _ = try StudyCatalog.activity(id: activityID)
    var p = profile
    if !p.completedActivities.contains(activityID) {
      p.attempts[activityID, default: StudyAttempt()].hints = min(
        3, (p.attempts[activityID]?.hints ?? 0) + 1)
    }
    return update(old: profile, new: p)
  }
  public static func claim(_ profile: LearningProfile, questID: String) throws -> LearningUpdate {
    guard let quest = LearningQuest.all.first(where: { $0.id == questID }) else {
      throw StudyError.ineligibleReward
    }
    if profile.claimedQuests.contains(questID) { return update(old: profile, new: profile) }
    guard quest.canClaim(in: profile) else { throw StudyError.ineligibleReward }
    var p = profile
    p.claimedQuests.insert(questID)
    p.rewards["quest:\(questID)"] = quest.xp
    return update(old: profile, new: p)
  }
  public static func equip(_ profile: LearningProfile, titleID: String) throws -> LearningUpdate {
    guard profile.unlockedTitles.contains(titleID),
      LearningTitle.all.contains(where: { $0.id == titleID })
    else { throw StudyError.lockedTitle }
    var p = profile
    p.equippedTitle = titleID
    return update(old: profile, new: p)
  }
  /// Call only with snapshots from the live DuelStore. Practice and legacy campus
  /// fixtures have no reward path. Match points stay entirely server-controlled.
  public static func recordDuel(_ profile: LearningProfile, snapshot: DuelSnapshot)
    -> LearningUpdate
  {
    let playerIDs = Set(snapshot.players.map(\.id))
    guard snapshot.revision > 0, playerIDs.contains(snapshot.viewerID),
      playerIDs.count == snapshot.players.count, (1...2).contains(playerIDs.count)
    else { return update(old: profile, new: profile) }

    // Finished is released only after both players continue the final shared reveal.
    // Incomplete/abandoned rooms and partial or malformed final payloads never qualify.
    if snapshot.phase == .finished {
      guard snapshot.roundCount == 3, snapshot.roundIndex == 2, playerIDs.count == 2,
        snapshot.players.allSatisfy({
          $0.submitted && $0.hasContinued && (0...300).contains($0.score) && $0.score % 100 == 0
        }),
        let reveal = snapshot.reveal, reveal.trace.algorithm == snapshot.algorithm,
        reveal.answers.count == 2, Set(reveal.answers.map(\.playerID)) == playerIDs,
        reveal.answers.allSatisfy({ $0.points == ($0.correct ? 100 : 0) })
      else { return update(old: profile, new: profile) }
    }

    var p = profile
    let roomID = snapshot.id.uuidString.lowercased()
    var session = p.duelSessions?[roomID] ?? DuelLearningSession()
    guard snapshot.revision >= session.lastRevision else {
      return update(old: profile, new: profile)
    }
    let isActive = [.lobby, .answering, .reveal].contains(snapshot.phase)
    if session.rewarded && isActive && snapshot.revision > session.lastRevision {
      session.cycleStartRevision = snapshot.revision
      session.rewarded = false
    }
    session.lastRevision = snapshot.revision
    if snapshot.phase == .finished && !session.rewarded {
      let id = "duel:\(roomID):\(session.cycleStartRevision)"
      if !p.completedLiveMatches.contains(id) {
        p.completedLiveMatches.insert(id)
        let viewerScore = snapshot.players.first { $0.id == snapshot.viewerID }!.score
        let opponentScore = snapshot.players.first { $0.id != snapshot.viewerID }!.score
        if viewerScore > opponentScore { p.wonLiveMatches.insert(id) }
        p.rewards[id] = 60
      }
      session.rewarded = true
    }
    if p.duelSessions == nil { p.duelSessions = [:] }
    p.duelSessions?[roomID] = session
    return update(old: profile, new: p)
  }
  private static func update(old: LearningProfile, new: LearningProfile, correct: Bool? = nil)
    -> LearningUpdate
  {
    var p = new
    for title in LearningTitle.all where title.eligible(in: p) { p.unlockedTitles.insert(title.id) }
    for badge in LearningAchievement.all where badge.eligible(in: p) {
      p.achievements.insert(badge.id)
    }
    return LearningUpdate(
      profile: p, correct: correct, awardedXP: p.xp - old.xp,
      newTitles: p.unlockedTitles.subtracting(old.unlockedTitles),
      newAchievements: p.achievements.subtracting(old.achievements))
  }
}

/// Atomic Codable persistence. A damaged/future-version save is never silently overwritten.
public struct LearningProgressRepository: Sendable {
  public let url: URL
  public init(url: URL) { self.url = url }
  public func load() throws -> LearningProfile {
    guard FileManager.default.fileExists(atPath: url.path) else { return LearningProfile() }
    let profile = try JSONDecoder().decode(LearningProfile.self, from: Data(contentsOf: url))
    guard profile.schemaVersion == 1 else { throw StudyError.unsupportedVersion }
    guard profile.rewards.values.allSatisfy({ (0...1000).contains($0) }),
      profile.equippedTitle.isEmpty == false,
      profile.unlockedTitles.contains(profile.equippedTitle)
    else { throw StudyError.invalidProfile }
    return profile
  }
  public func save(_ profile: LearningProfile) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(profile).write(to: url, options: .atomic)
  }
}
