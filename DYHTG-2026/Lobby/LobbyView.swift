import AlgorithmArenaCore
import SwiftUI

struct LobbyView: View {
    @Bindable var store: MatchStore

    @State private var location = LocationProvider()
    @State private var isCheckingIn = false
    @State private var isGettingReady = false
    @State private var checkInFailure: LocationProvider.Failure?
    @State private var isConfirmingLeave = false

    var body: some View {
        NavigationStack {
            if let room = store.snapshot?.room, let viewer = store.viewer {
                content(room, viewer: viewer)
            }
        }
    }

    private func content(_ room: PublicMatchState, viewer: PlayerProgress) -> some View {
        let opponent = store.opponent
        let host = room.players.first { $0.id == room.creatorID }
        let start = store.course.stops.start

        return List {
            if store.isReconnecting {
                ReconnectingRow()
            }

            if opponent == nil {
                Section {
                    RoomCodeRow(code: room.roomCode)
                } header: {
                    Text("Room Code")
                } footer: {
                    Text("The other player taps Join with Code and enters this code.")
                }
            }

            Section {
                if store.isCreator {
                    Picker("Algorithm", selection: algorithmBinding(room.algorithm)) {
                        ForEach(AlgorithmKind.allCases, id: \.self) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowSeparator(.hidden)
                } else {
                    LabeledContent("Algorithm", value: room.algorithm.title)
                }
                Text(room.algorithm.rule)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Algorithm")
            } footer: {
                if store.isCreator {
                    Text("You choose for both players. Changing it clears both players' readiness.")
                } else {
                    Text("\(host?.nickname ?? "The host") chooses the algorithm for this match.")
                }
            }

            Section {
                PlayerRow(player: viewer, isViewer: true, isHost: viewer.id == room.creatorID, start: start)
                if let opponent {
                    PlayerRow(player: opponent, isViewer: false, isHost: opponent.id == room.creatorID, start: start)
                } else {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Waiting for the other player to join")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Players")
            } footer: {
                Text("Check in outside the James McCune Smith Learning Hub. Arena uses your location only to confirm you're there.")
            }
        }
        .navigationTitle("Lobby")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: "Join my Arena room with the code \(room.roomCode).")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Leave Room", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                        isConfirmingLeave = true
                    }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
            }
        }
        .bottomActions {
            primaryAction(room: room, viewer: viewer, opponent: opponent, host: host)
            if viewer.ready {
                Button("I'm Not Ready") {
                    Task { await store.perform(.setReady(ready: false)) }
                }
                .buttonStyle(.borderless)
            }
        }
        .confirmationDialog("Leave this room?", isPresented: $isConfirmingLeave, titleVisibility: .visible) {
            Button("Leave Room", role: .destructive) {
                Task { await store.leave() }
            }
        } message: {
            Text("You'll need the code to join again.")
        }
        .actionErrorAlert(
            $store.actionError,
            retry: { Task { await store.retryPendingCommand() } },
            cancel: { store.discardPendingCommand() }
        )
        .alert(
            "Can't Check In",
            isPresented: Binding(get: { checkInFailure != nil }, set: { if !$0 { checkInFailure = nil } }),
            presenting: checkInFailure
        ) { failure in
            if failure == .denied {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            } else {
                Button("Try Again", action: checkIn)
            }
            Button("Cancel", role: .cancel) {}
        } message: { failure in
            switch failure {
            case .denied:
                Text("Location access is off for Arena. Allow it in Settings to check in at the start.")
            case .unavailable:
                Text("Your location isn't available yet. Move into the open and try again.")
            }
        }
    }

    @ViewBuilder
    private func primaryAction(
        room: PublicMatchState,
        viewer: PlayerProgress,
        opponent: PlayerProgress?,
        host: PlayerProgress?
    ) -> some View {
        let start = store.course.stops.start

        if !viewer.hasArrived(at: start) {
            PrimaryButton(title: "Check In at Start", busyTitle: "Checking In...", isBusy: isCheckingIn, action: checkIn)
        } else if !viewer.ready {
            PrimaryButton(title: "Ready with \(room.algorithm.title)", busyTitle: "Getting Ready...", isBusy: isGettingReady) {
                getReady(for: room.algorithm, viewer: viewer)
            }
        } else if store.isCreator {
            let blocker = startBlocker(opponent: opponent, start: start)
            if let blocker {
                Text(blocker)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            PrimaryButton(title: "Start Match", busyTitle: "Starting...", isBusy: store.isSending) {
                Task { await store.perform(.start) }
            }
            .disabled(blocker != nil)
        } else {
            HStack(spacing: 8) {
                ProgressView()
                Text("Waiting for \(host?.nickname ?? "the host") to start the match")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(minHeight: 44)
        }
    }

    private func startBlocker(opponent: PlayerProgress?, start: NodeID) -> String? {
        guard let opponent else { return "Waiting for the other player to join." }
        if !opponent.hasArrived(at: start) { return "\(opponent.nickname) hasn't checked in yet." }
        if !opponent.ready { return "Waiting for \(opponent.nickname) to get ready." }
        return nil
    }

    private func algorithmBinding(_ current: AlgorithmKind) -> Binding<AlgorithmKind> {
        Binding(
            get: { current },
            set: { selected in
                guard selected != current else { return }
                Task { await store.perform(.selectAlgorithm(algorithm: selected)) }
            }
        )
    }

    private func getReady(for algorithm: AlgorithmKind, viewer: PlayerProgress) {
        guard !isGettingReady else { return }
        isGettingReady = true
        Task {
            defer { isGettingReady = false }
            if !viewer.algorithmConfirmed {
                await store.perform(.confirmAlgorithm(algorithm: algorithm))
            }
            if store.viewer?.algorithmConfirmed == true {
                await store.perform(.setReady(ready: true))
            }
        }
    }

    private func checkIn() {
        guard !isCheckingIn else { return }
        isCheckingIn = true
        Task {
            defer { isCheckingIn = false }
            do {
                let fix = try await location.currentFix()
                await store.perform(.confirmArrival(nodeID: store.course.stops.start, evidence: .location(fix: fix)))
            } catch let failure as LocationProvider.Failure {
                checkInFailure = failure
            } catch {
                checkInFailure = .unavailable
            }
        }
    }
}

extension PlayerProgress {
    func hasArrived(at node: NodeID) -> Bool {
        arrivals.contains { $0.nodeID == node }
    }
}

#Preview {
    let store = MatchStore.demo(timing: .init(latency: .zero, opponent: .seconds(1)))
    LobbyView(store: store)
        .task { try? await store.createRoom(nickname: "Alex", algorithm: .dijkstra) }
}
