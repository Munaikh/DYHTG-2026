import AlgorithmArenaCore
import Foundation

public enum LearningDocuments {
  /// Two deliberately separate directories. Only individually unlocked prompts
  /// may be served; `server` contains keys and future replays and is never a CDN resource.
  public static func documents() throws -> [String: Data] {
    var documents: [String: Data] = [:]
    for algorithm in AlgorithmKind.allCases {
      for challenge in try LearningCatalog.challenges(algorithm: algorithm) {
        let path = "\(algorithm.rawValue)/\(challenge.definition.slot.rawValue).json"
        documents["prompts/\(path)"] =
          try ContractJSON.encoder().encode(challenge.definition) + Data([0x0A])
        documents["server/\(path)"] =
          try ContractJSON.encoder().encode(challenge) + Data([0x0A])
      }
    }
    return documents
  }
}
