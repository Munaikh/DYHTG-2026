import Foundation
import Observation
import Supabase

struct BattlePlayer: Decodable, Identifiable {
    let id: UUID
    let nickname: String
    let avatar: String
    let ready: Bool
    let score: Int
    let round: Int
    let correct: Int
    let attempts: Int
    let online: Bool
}
struct BattleChallenge: Decodable {
    struct Node: Decodable, Identifiable { let id: Int; let x: Double; let y: Double }
    struct Edge: Decodable { let a: Int; let b: Int; let weight: Int }
    let round: Int
    let kind: String
    let title: String
    let rule: String
    let difficulty: String
    let nodes: [Node]
    let edges: [Edge]
    let values: [Int]
}
struct SharedPosition: Codable { let latitude: Double; let longitude: Double }
struct BattleSharing: Decodable {
    let requester: UUID
    let accepted: Bool
    let expiresAt: String
    let positions: [String: SharedPosition]
}
struct BattleFeedback: Decodable {
    let correct: Bool
    let earned: Int
    let explanation: String
    let solution: [Int]
}
struct BattleState: Decodable, Identifiable {
    let id: UUID
    let code: String
    let revision: Int
    let host: UUID
    let phase: String
    let winner: UUID?
    let startedAt: String?
    let finishedAt: String?
    let viewer: UUID
    let rematch: UUID?
    let players: [BattlePlayer]
    let challenge: BattleChallenge?
    let sharing: BattleSharing?
    let feedback: BattleFeedback?
    var me: BattlePlayer? { players.first { $0.id == viewer } }
    var opponent: BattlePlayer? { players.first { $0.id != viewer } }
}
struct BattleStatistics: Decodable {
    struct Profile: Decodable { let nickname: String; let avatar: String }
    let profile: Profile?
    struct Match: Decodable, Identifiable {
        let id: UUID; let opponent: String; let won: Bool; let score: Int
        let difficulty: String; let completedAt: String
    }
    let matches: Int
    let wins: Int
    let currentStreak: Int
    let bestStreak: Int
    let history: [Match]
}

@MainActor @Observable
final class BattleStore {
    var state: BattleState?
    var statistics: BattleStatistics?
    var signedIn = false
    var busy = false
    var error: String?
    var disconnected = false
    var feedback: BattleFeedback?
    var feedbackChallenge: BattleChallenge?
    var opponentNotice: String?
    private var channel: RealtimeChannelV2?
    private var listener: Task<Void, Never>?
    private var heartbeat: Task<Void, Never>?
    private let client = ArenaBackend.client
    private var inFlight = false

    func checkAccount() async {
        signedIn = (try? await client.auth.session.user.isAnonymous) == false
    }
    func sendCode(email: String) async {
        await run { try await self.client.auth.signInWithOTP(email: email.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }
    func verify(email: String, code: String) async {
        await run {
            _ = try await self.client.auth.verifyOTP(email: email.trimmingCharacters(in: .whitespacesAndNewlines), token: code.trimmingCharacters(in: .whitespacesAndNewlines), type: .email)
            self.signedIn = true
        }
    }
    func saveProfile(nickname: String, avatar: String) async {
        guard (2...20).contains(nickname.trimmingCharacters(in: .whitespacesAndNewlines).count) else {
            error = "Choose a nickname with 2–20 characters in Profile before creating or joining a battle."
            return
        }
        await run {
            _ = try await self.request("profile", ["nickname": .string(nickname.trimmingCharacters(in: .whitespacesAndNewlines)), "avatar": .string(avatar)])
        }
    }
    func stats() async {
        await checkAccount()
        guard signedIn else { return }
        await run {
            let response = try await self.request("stats")
            self.statistics = try JSONDecoder().decode(BattleStatistics.self, from: response)
            if let profile = self.statistics?.profile {
                UserDefaults.standard.set(profile.nickname, forKey: "nickname")
                UserDefaults.standard.set(profile.avatar, forKey: "battleAvatar")
            }
        }
    }
    func recover() async {
        await checkAccount()
        guard signedIn, state == nil else { return }
        await run {
            let data = try await self.request("recover")
            guard String(data: data, encoding: .utf8) != "null" else { return }
            self.state = try JSONDecoder().decode(BattleState.self, from: data)
            await self.subscribe()
        }
    }
    func act(_ action: String, fields: [String: AnyJSON] = [:]) async {
        guard !inFlight else { return }
        inFlight = true
        defer { inFlight = false }
        await run {
            var payload = fields
            if let state = self.state { payload["id"] = .string(state.id.uuidString) }
            let data = try await self.request(action, payload)
            let next = try JSONDecoder().decode(BattleState.self, from: data)
            if next.feedback != nil { self.feedbackChallenge = self.state?.challenge }
            self.apply(next)
            if let result = next.feedback { self.feedback = result }
            if action == "rematch", let id = next.rematch {
                let data = try await self.request("snapshot", ["id": .string(id.uuidString)])
                self.state = try JSONDecoder().decode(BattleState.self, from: data)
                self.feedback = nil
            }
            if self.channel == nil || action == "rematch" { await self.subscribe() }
        }
    }
    func refresh() async {
        guard let state, !inFlight else { return }
        do {
            let data = try await request("snapshot", ["id": .string(state.id.uuidString)])
            // Do not overwrite a newer answer with a snapshot started before it.
            guard !inFlight else { return }
            apply(try JSONDecoder().decode(BattleState.self, from: data))
            disconnected = false
        } catch { disconnected = true }
    }
    func close() async {
        if let state, ["lobby", "playing"].contains(state.phase) {
            await act("leave")
            guard error == nil else { return }
        }
        heartbeat?.cancel(); heartbeat = nil
        listener?.cancel(); listener = nil
        if let channel { await client.removeChannel(channel) }
        channel = nil; state = nil; feedback = nil; feedbackChallenge = nil
    }
    private func apply(_ next: BattleState) {
        if let current = state, current.id == next.id, current.revision > next.revision { return }
        if let previous = state?.opponent, let opponent = next.opponent, opponent.score > previous.score {
            opponentNotice = "\(opponent.nickname) earned \(opponent.score - previous.score) progress."
        }
        state = next
        if ["finished", "abandoned"].contains(next.phase) {
            heartbeat?.cancel(); heartbeat = nil
        }
    }
    private func request(_ action: String, _ payload: [String: AnyJSON] = [:]) async throws -> Data {
        struct Params: Encodable { let action: String; let payload: [String: AnyJSON] }
        return try await client.rpc("friend_battle", params: Params(action: action, payload: payload)).execute().data
    }
    private func run(_ operation: () async throws -> Void) async {
        busy = true; error = nil
        defer { busy = false }
        do { try await operation() }
        catch let failure as PostgrestError {
            self.error = failure.code == "PGRST202" ? "Friend battles need the new Supabase migration. Follow docs/EXPANSION.md to enable them." : failure.message
        }
        catch { self.error = error.localizedDescription }
    }
    private func subscribe() async {
        if heartbeat == nil {
            heartbeat = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.refresh()
                    try? await Task.sleep(for: .seconds(5))
                }
            }
        }
        listener?.cancel()
        if let channel { await client.removeChannel(channel) }
        guard let state else { return }
        let channel = client.channel("friend-battle-\(state.id)")
        self.channel = channel
        let changes = channel.postgresChange(AnyAction.self, schema: "public", table: "battle_invalidations", filter: .eq("id", value: state.id.uuidString))
        do { try await channel.subscribeWithError() }
        catch { disconnected = true; return }
        listener = Task { [weak self] in
            for await _ in changes { await self?.refresh() }
        }
        await refresh()
    }
}

/// Postgres may omit fractional seconds when they are zero.
enum BattleTime {
    static func date(_ text: String) -> Date? {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = parser.date(from: text) { return date }
        parser.formatOptions = [.withInternetDateTime]
        return parser.date(from: text)
    }
}
