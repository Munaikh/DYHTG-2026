import AlgorithmArenaCore
import Foundation
import Supabase

struct ArrivalRequest: Codable, Equatable, Sendable {
    let matchID: String
    let playerID: String
    let nodeID: String

    private static let prefix = "arena-checkin:"

    var code: String {
        let json = (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        return Self.prefix + json
    }

    init(matchID: String, playerID: String, nodeID: String) {
        self.matchID = matchID
        self.playerID = playerID
        self.nodeID = nodeID
    }

    init?(code: String) {
        guard code.hasPrefix(Self.prefix),
            let data = code.dropFirst(Self.prefix.count).data(using: .utf8),
            let request = try? JSONDecoder().decode(Self.self, from: data)
        else { return nil }
        self = request
    }
}

struct ArrivalApproval: Decodable, Sendable {
    let approvalID: String
    let expiresAt: Date

    private static let prefix = "arena-approval:"

    var code: String { Self.prefix + approvalID }

    static func approvalID(from code: String) -> String? {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(prefix) else { return trimmed.isEmpty ? nil : trimmed }
        return String(trimmed.dropFirst(prefix.count))
    }
}

enum OrganiserService {
    static func userID(client: SupabaseClient = ArenaBackend.client) async -> String? {
        if let session = try? await client.auth.session {
            return session.user.id.uuidString.lowercased()
        }
        return try? await client.auth.signInAnonymously().user.id.uuidString.lowercased()
    }

    static func issueApproval(
        for request: ArrivalRequest,
        client: SupabaseClient = ArenaBackend.client
    ) async throws -> ArrivalApproval {
        _ = await userID(client: client)
        do {
            return try await client.rpc(
                "arena_issue_arrival_approval",
                params: ApprovalParameters(matchID: request.matchID, playerID: request.playerID, nodeID: request.nodeID)
            )
            .execute()
            .value
        } catch let error as PostgrestError {
            throw error.matchServiceError
        }
    }
}

extension PostgrestError {
    var matchServiceError: any Error {
        if let data = message.data(using: .utf8),
            let decoded = try? ContractJSON.decoder().decode(MatchServiceError.self, from: data)
        {
            return decoded
        }
        if code == "PGRST301" || code == "42501" {
            return MatchServiceError(code: .unauthenticated, message: message)
        }
        return self
    }
}

private struct ApprovalParameters: Encodable, Sendable {
    let matchID: String
    let playerID: String
    let nodeID: String

    enum CodingKeys: String, CodingKey {
        case matchID = "match_id"
        case playerID = "player_id"
        case nodeID = "node_id"
    }
}
