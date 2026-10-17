import AlgorithmArenaCore
import Foundation
import Supabase

@MainActor
protocol DuelService {
    func send(_ command: DuelCommand) async throws -> DuelSnapshot
    func snapshot(id: UUID) async throws -> DuelSnapshot
}

@MainActor
final class SupabaseDuelService: DuelService {
    private let client: SupabaseClient
    private var authentication: Task<Void, any Error>?

    init(client: SupabaseClient = ArenaBackend.client) {
        self.client = client
    }

    func send(_ command: DuelCommand) async throws -> DuelSnapshot {
        try await authenticate()
        do {
            return try await client.rpc("arena_duel_command", params: CommandParameters(command: command)).execute().value
        } catch let error as PostgrestError {
            throw failure(from: error)
        }
    }

    func snapshot(id: UUID) async throws -> DuelSnapshot {
        try await authenticate()
        do {
            return try await client.rpc("arena_duel_snapshot", params: SnapshotParameters(match_id: id)).execute().value
        } catch let error as PostgrestError {
            throw failure(from: error)
        }
    }

    private func authenticate() async throws {
        if let authentication { return try await authentication.value }
        let task = Task { [client] in
            do {
                _ = try await client.auth.session
            } catch AuthError.sessionMissing {
                _ = try await client.auth.signInAnonymously()
            }
        }
        authentication = task
        defer { authentication = nil }
        try await task.value
    }

    private func failure(from error: PostgrestError) -> any Error {
        if let data = error.message.data(using: .utf8),
           let failure = try? ContractJSON.decoder().decode(RPCFailure.self, from: data) {
            return MatchServiceError(code: MatchErrorCode(rawValue: failure.code) ?? .invalidCommand,
                                     message: failure.message, currentRevision: failure.currentRevision)
        }
        if error.code == "PGRST202" {
            return MatchServiceError(code: .serviceUnavailable, message: "The duel service is not available yet. Please try again shortly.")
        }
        return error.matchServiceError
    }

    private struct RPCFailure: Decodable { let code: String; let message: String; let currentRevision: Int? }
    private struct CommandParameters: Encodable { let command: DuelCommand }
    private struct SnapshotParameters: Encodable { let match_id: UUID }
}
