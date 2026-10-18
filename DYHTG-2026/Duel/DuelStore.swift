import AlgorithmArenaCore
import Foundation
import Observation

@MainActor
@Observable
final class DuelStore {
    private(set) var snapshot: DuelSnapshot?
    private(set) var pending: DuelCommand?
    private(set) var isBusy = false
    private(set) var isOffline = false
    var error: ActionError?

    private let service: any DuelService
    private let persistenceURL: URL?
    private var generation = UUID()

    init(service: any DuelService = SupabaseDuelService(), persistenceURL: URL? = URL.applicationSupportDirectory.appending(path: "ActiveDuel.json")) {
        self.service = service
        self.persistenceURL = persistenceURL
        if let persistenceURL, let data = try? Data(contentsOf: persistenceURL),
           let saved = try? ContractJSON.decoder().decode(SavedDuel.self, from: data) {
            snapshot = saved.snapshot
            pending = saved.pending
            isOffline = snapshot != nil || pending != nil
        }
    }

    var viewer: DuelPlayer? { snapshot?.players.first { $0.id == snapshot?.viewerID } }
    var opponent: DuelPlayer? { snapshot?.players.first { $0.id != snapshot?.viewerID } }
    var isCreator: Bool { snapshot != nil && snapshot?.creatorID == snapshot?.viewerID }
    var canAct: Bool { !isBusy && pending == nil && !isOffline }

    func create(nickname: String, algorithm: StudyAlgorithm) async {
        await deliver(DuelCommand(action: .create, nickname: nickname, algorithm: algorithm))
    }

    func join(nickname: String, code: String) async {
        await deliver(DuelCommand(action: .join, nickname: nickname, code: code.uppercased()))
    }

    func perform(_ action: DuelAction, answer: NodeID? = nil) async {
        guard let snapshot else { return }
        await deliver(DuelCommand(action: action, matchID: snapshot.id, revision: snapshot.revision, answerNodeID: answer))
    }

    func retry() async {
        guard let pending, !isBusy else { return }
        await deliver(pending, retrying: true)
    }

    /// Runs only while the app is foregrounded. Tab changes never abandon a room.
    func observe() async {
        while !Task.isCancelled {
            if !isBusy {
                if pending != nil { await retry() }
                else { await refresh() }
            }
            do { try await Task.sleep(for: .seconds(isOffline ? 3 : 1)) }
            catch { return }
        }
    }

    func refresh() async {
        guard let id = snapshot?.id else { return }
        let requestedGeneration = generation
        do {
            let latest = try await service.snapshot(id: id)
            guard generation == requestedGeneration, snapshot?.id == id else { return }
            apply(latest)
            isOffline = false
        } catch is CancellationError {
        } catch let failure as MatchServiceError where failure.code == .notMember || failure.code == .roomNotFound {
            guard generation == requestedGeneration, snapshot?.id == id else { return }
            clear()
            error = ActionError(title: "Room unavailable", message: "This room is no longer available. Create or join another duel.")
        } catch {
            guard generation == requestedGeneration else { return }
            isOffline = true
        }
    }

    func closeResult() {
        guard snapshot?.phase == .finished || snapshot?.phase == .incomplete else { return }
        clear()
    }

    private func deliver(_ command: DuelCommand, retrying: Bool = false, reconciliation: Bool = false) async {
        guard !isBusy, retrying || pending == nil else { return }
        isBusy = true
        error = nil
        pending = command
        save()
        let requestedGeneration = generation
        let previousRound = snapshot?.roundIndex
        do {
            let latest = try await service.send(command)
            guard generation == requestedGeneration else { return }
            pending = nil
            isOffline = false
            if command.action == .leave { clear() }
            else { apply(latest) }
            save()
            isBusy = false
        } catch let failure as MatchServiceError {
            guard generation == requestedGeneration else { return }
            isBusy = false
            // A structured server rejection means the command was not accepted.
            pending = nil
            isOffline = false
            save()
            if failure.code == .staleRevision, !reconciliation, let id = command.matchID {
                await refresh()
                guard generation == requestedGeneration else { return }
                let isRoundBound = command.action == .submit || command.action == .advance
                if !isOffline, let current = snapshot, current.id == id,
                   (!isRoundBound || current.roundIndex == previousRound),
                   stillApplies(command.action, in: current) {
                    await deliver(DuelCommand(action: command.action, matchID: id, revision: current.revision,
                                              answerNodeID: command.answerNodeID), reconciliation: true)
                    return
                }
                return
            }
            await refresh()
            guard generation == requestedGeneration else { return }
            error = ActionError(title: failure.code.title, message: failure.message)
        } catch {
            guard generation == requestedGeneration else { return }
            // Keep the exact UUID and payload until the uncertain result is reconciled.
            isBusy = false
            isOffline = true
        }
    }

    private func stillApplies(_ action: DuelAction, in state: DuelSnapshot) -> Bool {
        let me = state.players.first { $0.id == state.viewerID }
        switch action {
        case .ready: return state.phase == .lobby && me?.ready == false
        case .start: return state.phase == .lobby && state.players.count == 2 && state.players.allSatisfy(\.ready)
        case .submit: return state.phase == .answering && me?.submitted == false
        case .advance: return state.phase == .reveal && me?.hasContinued == false
        case .leave: return true
        case .rematch: return state.phase == .finished
        case .create, .join: return false
        }
    }

    private func apply(_ latest: DuelSnapshot) {
        if let current = snapshot, current.id == latest.id, current.revision > latest.revision { return }
        snapshot = latest
        save()
    }

    private func clear() {
        generation = UUID()
        snapshot = nil
        pending = nil
        isBusy = false
        isOffline = false
        error = nil
        if let persistenceURL { try? FileManager.default.removeItem(at: persistenceURL) }
    }

    private func save() {
        guard let persistenceURL,
              let data = try? ContractJSON.encoder().encode(SavedDuel(snapshot: snapshot, pending: pending)) else { return }
        try? FileManager.default.createDirectory(at: persistenceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: persistenceURL, options: [.atomic, .completeFileProtection])
    }

    private struct SavedDuel: Codable {
        let snapshot: DuelSnapshot?
        let pending: DuelCommand?
    }
}
