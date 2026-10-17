import AlgorithmArenaCore
import Foundation
import Supabase

final class SupabaseMatchService: MatchService {
    private let client: SupabaseClient

    init(client: SupabaseClient = ArenaBackend.client) {
        self.client = client
    }

    func send(_ command: MatchCommand) async throws -> CommandReceipt {
        try await authenticate()
        return try await call("arena_command", params: CommandParameters(command: command))
    }

    func snapshot(for matchID: MatchID) async throws -> MatchSnapshot {
        try await authenticate()
        return try await call("arena_snapshot", params: SnapshotParameters(matchID: matchID.rawValue))
    }

    func invalidations(for matchID: MatchID) async throws -> AsyncThrowingStream<SnapshotInvalidation, any Error> {
        try await authenticate()
        let channel = client.channel("arena-\(matchID.rawValue)")
        let changes = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "arena_invalidations",
            filter: .eq("matchID", value: matchID.rawValue)
        )
        try await channel.subscribeWithError()

        let (stream, continuation) = AsyncThrowingStream<SnapshotInvalidation, any Error>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        let listener = Task {
            for await change in changes {
                if let invalidation = Self.invalidation(from: change) {
                    continuation.yield(invalidation)
                }
            }
            continuation.finish()
        }
        continuation.onTermination = { [client] _ in
            listener.cancel()
            Task { await client.removeChannel(channel) }
        }
        return stream
    }

    private func authenticate() async throws {
        do {
            _ = try await client.auth.session
        } catch {
            _ = try await client.auth.signInAnonymously()
        }
    }

    private func call<Parameters: Encodable & Sendable, Result: Decodable>(
        _ function: String,
        params: Parameters
    ) async throws -> Result {
        do {
            return try await client.rpc(function, params: params).execute().value
        } catch let error as PostgrestError {
            throw error.matchServiceError
        }
    }

    private static func invalidation(from change: AnyAction) -> SnapshotInvalidation? {
        let record: [String: AnyJSON]
        switch change {
        case .insert(let action): record = action.record
        case .update(let action): record = action.record
        case .delete: return nil
        }
        guard let matchID = record["matchID"]?.stringValue, let revision = record["revision"]?.intValue else {
            return nil
        }
        return SnapshotInvalidation(matchID: MatchID(rawValue: matchID), revision: revision)
    }
}

private struct CommandParameters: Encodable, Sendable {
    let command: MatchCommand
}

private struct SnapshotParameters: Encodable, Sendable {
    let matchID: String

    enum CodingKeys: String, CodingKey {
        case matchID = "match_id"
    }
}
