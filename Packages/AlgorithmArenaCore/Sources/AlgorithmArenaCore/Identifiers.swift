import Foundation

/// Opaque, case-sensitive identifiers encode as JSON strings, never display labels.
public struct Identifier<Tag>: RawRepresentable, Hashable, Comparable, Codable, Sendable,
  ExpressibleByStringLiteral
{
  public let rawValue: String

  public init(rawValue: String) { self.rawValue = rawValue }
  public init(stringLiteral value: String) { rawValue = value }
  public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
  public init(from decoder: any Decoder) throws {
    rawValue = try decoder.singleValueContainer().decode(String.self)
  }
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

public enum NodeTag: Sendable {}
public enum EdgeTag: Sendable {}
public enum CourseTag: Sendable {}
public enum ScenarioTag: Sendable {}
public enum ChallengeTag: Sendable {}
public enum MatchTag: Sendable {}
public enum PlayerTag: Sendable {}
public typealias NodeID = Identifier<NodeTag>
public typealias EdgeID = Identifier<EdgeTag>
public typealias CourseID = Identifier<CourseTag>
public typealias ScenarioID = Identifier<ScenarioTag>
public typealias ChallengeID = Identifier<ChallengeTag>
public typealias MatchID = Identifier<MatchTag>
public typealias PlayerID = Identifier<PlayerTag>

public enum ContractVersion: Int, Codable, Sendable { case v1 = 1 }
public enum AlgorithmKind: String, Codable, CaseIterable, Sendable { case dijkstra, aStar }
public enum RouteBranch: String, Codable, CaseIterable, Sendable { case standard, bonus }

/// Use this codec at the transport boundary; dates are UTC ISO-8601, to whole seconds.
public enum ContractJSON {
  public static func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return encoder
  }

  public static func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}
