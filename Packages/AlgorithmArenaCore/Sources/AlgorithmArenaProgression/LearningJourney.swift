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
  /// Only the live adapter's released, final snapshot qualifies. Solo fixtures never do.
  public static func completedMatch(_ profile: LearningProfile, snapshot: MatchSnapshot, live: Bool)
    -> LearningUpdate
  {
    guard live, snapshot.room.phase == .finished, snapshot.room.players.count == 2,
      snapshot.room.players.allSatisfy({ $0.stage == .finished }),
      snapshot.room.players.contains(where: { $0.id == snapshot.viewer.playerID })
    else { return update(old: profile, new: profile) }
    let didWin: Bool
    switch snapshot.room.result {
    case .winner(let winner, _): didWin = winner == snapshot.viewer.playerID
    case .draw: didWin = false
    case .incomplete, .none: return update(old: profile, new: profile)
    }
    var p = profile
    let id = snapshot.room.matchID.rawValue
    guard !p.completedLiveMatches.contains(id) else { return update(old: profile, new: profile) }
    p.completedLiveMatches.insert(id)
    if didWin { p.wonLiveMatches.insert(id) }
    p.rewards["match:\(id)"] = 60
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
