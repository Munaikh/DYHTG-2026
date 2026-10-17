import AlgorithmArenaCore
import Foundation

public struct StudyAttempt: Codable, Equatable, Sendable {
  public var mistakes = 0
  public var hints = 0
  public init() {}
}
public struct PracticeCompletion: Codable, Equatable, Sendable {
  public let activityID: String
  public let algorithm: StudyAlgorithm
  public let mistakes: Int
  public let hints: Int
}
public struct LearningPreferences: Codable, Equatable, Sendable {
  public var beginnerGuide = true
  public var reduceMotion = false
  public var largerControls = false
  public var appearance = "system"
  public init() {}
}
public struct LearningProfile: Codable, Equatable, Sendable {
  public var schemaVersion = 1
  public var nickname = "Explorer"
  public var completedLessons: Set<String> = []
  public var practice: [String: PracticeCompletion] = [:]
  public var attempts: [String: StudyAttempt] = [:]
  /// XP is derived from this exactly-once reward ledger, never stored as a second score.
  public var rewards: [String: Int] = [:]
  public var claimedQuests: Set<String> = []
  public var unlockedTitles: Set<String> = ["curious"]
  public var equippedTitle = "curious"
  public var achievements: Set<String> = []
  public var completedLiveMatches: Set<String> = []
  public var wonLiveMatches: Set<String> = []
  public var preferences = LearningPreferences()
  public init() {}
  public var xp: Int { rewards.values.reduce(0, +) }
  public var level: Int { LearningLevels.level(for: xp) }
  public var lessonCount: Int { completedLessons.count }
  public func completedLessons(for algorithm: StudyAlgorithm) -> Int {
    completedLessons.filter {
      $0.hasPrefix("\(StudyCatalog.contentVersion).\(algorithm.rawValue).lesson.")
    }.count
  }
  public var learnedAlgorithms: Set<StudyAlgorithm> {
    Set(StudyAlgorithm.allCases.filter { completedLessons(for: $0) > 0 })
  }
  public var completedModules: Set<StudyAlgorithm> {
    Set(StudyAlgorithm.allCases.filter { completedLessons(for: $0) == 3 })
  }
  public var completedActivities: Set<String> { completedLessons.union(practice.keys) }
}
public enum LearningLevels {
  public static func threshold(for level: Int) -> Int {
    let safe = min(1000, max(1, level))
    return 50 * (safe - 1) * safe
  }
  public static func level(for xp: Int) -> Int {
    var level = 1
    while level < 1000 && xp >= threshold(for: level + 1) { level += 1 }
    return level
  }
  public static func fraction(for xp: Int) -> Double {
    let level = level(for: xp)
    let lower = threshold(for: level)
    let upper = threshold(for: level + 1)
    return upper > lower ? min(1, max(0, Double(xp - lower) / Double(upper - lower))) : 1
  }
}
public struct LearningQuest: Identifiable, Sendable {
  public let id: String
  public let name: String
  public let instruction: String
  public let goal: Int
  public let xp: Int
  public func progress(in p: LearningProfile) -> Int {
    let current: Int =
      switch id {
      case "firstSteps": p.completedLessons.count
      case "nodeHunter": p.practice.count
      case "detective": p.completedLessons(for: .dijkstra)
      case "noHints": p.practice.values.filter { $0.hints == 0 }.count
      case "explorer": p.learnedAlgorithms.count
      case "campus": p.completedLiveMatches.count
      default: 0
      }
    return min(goal, current)
  }
  public func canClaim(in p: LearningProfile) -> Bool {
    progress(in: p) >= goal && !p.claimedQuests.contains(id)
  }
  public static let all: [LearningQuest] = [
    .init(
      id: "firstSteps", name: "First steps", instruction: "Finish your first lesson.", goal: 1,
      xp: 50),
    .init(
      id: "nodeHunter", name: "Node hunter", instruction: "Solve 3 different practice puzzles.",
      goal: 3, xp: 100),
    .init(
      id: "detective", name: "Shortest path detective",
      instruction: "Complete all 3 Dijkstra lessons.", goal: 3, xp: 150),
    .init(
      id: "noHints", name: "Think before you move",
      instruction: "Solve 2 practice puzzles without hints.", goal: 2, xp: 100),
    .init(
      id: "explorer", name: "Algorithm explorer",
      instruction: "Finish lessons in 3 different algorithms.", goal: 3, xp: 200),
    .init(
      id: "campus", name: "Campus challenger",
      instruction: "Finish a real two-player campus match.", goal: 1, xp: 50),
  ]
}
public struct LearningTitle: Identifiable, Sendable {
  public let id: String
  public let name: String
  public let requirement: String
  public func eligible(in p: LearningProfile) -> Bool {
    switch id {
    case "curious": true
    case "rookie": !p.completedLessons.isEmpty
    case "nodeExplorer": p.completedModules.contains(.bfs)
    case "depthDiver": p.completedModules.contains(.dfs)
    case "detective": p.completedModules.contains(.dijkstra)
    case "ace": p.completedModules.contains(.aStar)
    case "routeMaster": p.practice.count >= 6
    case "nodeHunter": p.claimedQuests.contains("nodeHunter")
    case "explorer": p.claimedQuests.contains("explorer")
    case "seeker": p.claimedQuests.count >= 3
    case "champion": !p.wonLiveMatches.isEmpty
    default: false
    }
  }
  public static let all: [LearningTitle] = [
    .init(id: "curious", name: "Curious learner", requirement: "Available from the start."),
    .init(id: "rookie", name: "Graph rookie", requirement: "Finish your first lesson."),
    .init(id: "nodeExplorer", name: "Node explorer", requirement: "Finish all 3 BFS lessons."),
    .init(id: "depthDiver", name: "Depth diver", requirement: "Finish all 3 DFS lessons."),
    .init(
      id: "detective", name: "Dijkstra detective", requirement: "Finish all 3 Dijkstra lessons."),
    .init(id: "ace", name: "A* ace", requirement: "Finish all 3 A* lessons."),
    .init(
      id: "routeMaster", name: "Route master", requirement: "Solve 6 different practice puzzles."),
    .init(id: "nodeHunter", name: "Node hunter", requirement: "Claim the Node hunter quest."),
    .init(
      id: "explorer", name: "Algorithm explorer", requirement: "Claim the Algorithm explorer quest."
    ),
    .init(id: "seeker", name: "Knowledge seeker", requirement: "Claim 3 different quests."),
    .init(
      id: "champion", name: "Algorithm champion", requirement: "Win a completed real campus match."),
  ]
}
public struct LearningAchievement: Identifiable, Sendable {
  public let id: String
  public let name: String
  public let requirement: String
  public func eligible(in p: LearningProfile) -> Bool {
    switch id {
    case "campus": p.claimedQuests.contains("campus")
    case "victory": !p.wonLiveMatches.isEmpty
    case "perfect": p.practice.values.contains { $0.mistakes == 0 }
    case "explorer": p.learnedAlgorithms.count == 5
    case "noHints": p.practice.values.contains { $0.hints == 0 }
    case "graphs": p.practice.values.filter { $0.activityID.hasSuffix(".2") }.count >= 3
    default: false
    }
  }
  public static let all: [LearningAchievement] = [
    .init(
      id: "campus", name: "Campus challenger", requirement: "Claim the Campus challenger quest."),
    .init(id: "victory", name: "First victory", requirement: "Win a completed real campus match."),
    .init(
      id: "perfect", name: "Perfect thinker",
      requirement: "Solve a practice puzzle without a mistake."),
    .init(
      id: "explorer", name: "Algorithm explorer",
      requirement: "Finish a lesson in all 5 algorithms."),
    .init(
      id: "noHints", name: "No hints needed", requirement: "Solve a practice puzzle without hints."),
    .init(
      id: "graphs", name: "Master of graphs",
      requirement: "Solve the final practice puzzle in 3 algorithms."),
  ]
}
