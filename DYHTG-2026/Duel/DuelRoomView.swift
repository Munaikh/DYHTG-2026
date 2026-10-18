import AlgorithmArenaCore
import SwiftUI

struct DuelRoomView: View {
    @Bindable var store: DuelStore
    let snapshot: DuelSnapshot

    var body: some View {
        VStack(spacing: 20) {
            switch snapshot.phase {
            case .lobby:
                lobby
            case .answering, .reveal:
                scores
                if let round = snapshot.currentRound {
                    DuelRoundView(store: store, snapshot: snapshot, round: round)
                        .id("\(snapshot.id)-\(snapshot.roundIndex)-\(snapshot.phase.rawValue)")
                }
            case .finished, .incomplete:
                result
            }
        }
    }

    private var lobby: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Invite a friend").font(.title2.bold())
                Text("Open Play on another device, choose Join a duel, then scan this code.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if let payload = DuelInvitation.payload(for: snapshot.roomCode) {
                    QRCodeView(text: payload)
                        .frame(width: 184, height: 184)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("Room invitation QR code")
                        .accessibilityIdentifier("duel.roomQR")
                }
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Or enter the room code").font(.caption).foregroundStyle(.secondary)
                        Text(snapshot.roomCode)
                            .font(.system(.title, design: .monospaced).bold())
                            .textSelection(.enabled)
                            .accessibilityLabel("Room code")
                            .accessibilityValue(snapshot.roomCode.map(String.init).joined(separator: " "))
                            .accessibilityIdentifier("duel.roomCode")
                    }
                    Spacer(minLength: 8)
                    ShareLink(item: "Join my Plot Twist Duel in Algorithm Arena. Room code: \(snapshot.roomCode)") {
                        Image(systemName: "square.and.arrow.up")
                            .frame(width: 28, height: 32)
                    }
                    .buttonStyle(ArenaCompactButtonStyle())
                    .accessibilityLabel("Share room code")
                }
            }
            .arenaCard()

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(snapshot.algorithm.title).font(.title2.bold())
                    Spacer()
                    Text("3 rounds").font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(snapshot.players) { player in
                    playerRow(player)
                }
                if snapshot.players.count < 2 {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.title2).foregroundStyle(.secondary)
                        Text("Waiting for your opponent…")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
                if store.viewer?.ready == false {
                    Button("I'm Ready") { Task { await store.perform(.ready) } }
                        .buttonStyle(ArenaActionStyle())
                        .disabled(!store.canAct)
                        .accessibilityIdentifier("duel.ready")
                } else if store.isCreator {
                    Button("Start Duel") { Task { await store.perform(.start) } }
                        .buttonStyle(ArenaActionStyle())
                        .disabled(!store.canAct || snapshot.players.count != 2 || !snapshot.players.allSatisfy(\.ready))
                        .accessibilityIdentifier("duel.start")
                } else {
                    Label("Ready. The host will start the duel.", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.medium)).foregroundStyle(ArenaPalette.teal)
                }
            }
            .arenaCard()
            Text("Predict privately. Reveal together.\nA surprise changes the second round.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var scores: some View {
        HStack(spacing: 12) {
            ForEach(snapshot.players) { player in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(player.id == snapshot.viewerID ? "You" : player.nickname)
                            .font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(player.submitted ? "Locked in" : "Thinking")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Text(player.score, format: .number)
                        .font(.system(.title2, design: .rounded).bold())
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .padding(14)
                .background(ArenaPalette.surface, in: .rect(cornerRadius: 18))
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var result: some View {
        VStack(spacing: 22) {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: snapshot.phase == .incomplete ? "flag.slash.fill" : "sparkles")
                    .font(.largeTitle).foregroundStyle(ArenaPalette.mint)
                ArenaEyebrow(text: snapshot.phase == .incomplete ? "Duel ended" : "Three rounds. Sharper thinking.", color: ArenaPalette.mint)
                Text(resultTitle)
                    .font(.system(.largeTitle, design: .rounded).bold())
                    .foregroundStyle(.white)
                Text(snapshot.phase == .incomplete ? "A player left before the duel finished." : "You saw the world change—and learned how the algorithm responds.")
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ArenaPalette.ink, in: .rect(cornerRadius: 26))
            VStack(spacing: 16) {
                ForEach(snapshot.players.sorted { $0.score > $1.score }) { player in
                    HStack {
                        Text(player.nickname).font(.headline)
                        if player.id == snapshot.viewerID { Text("YOU").font(.caption2.bold()).foregroundStyle(.secondary) }
                        Spacer()
                        Text("\(player.score) pts").font(.system(.title2, design: .rounded).bold()).monospacedDigit()
                    }
                }
            }
            .arenaCard()

            VStack(alignment: .leading, spacing: 10) {
                Label("Take it with you", systemImage: "lightbulb.fill").font(.headline)
                Text(snapshot.algorithm.rule).font(.subheadline)
                Text("When a connection closes, start a fresh search on the changed graph.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .arenaCard()
            if !store.isCreator && snapshot.phase == .finished {
                Text("Your host can start a rematch in this room.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ArenaGlassGroup(spacing: 12) {
                VStack(spacing: 12) {
                    if store.isCreator && snapshot.phase == .finished {
                        Button("Play Again") { Task { await store.perform(.rematch) } }
                            .buttonStyle(ArenaActionStyle())
                            .disabled(!store.canAct)
                            .accessibilityIdentifier("duel.rematch")
                    }
                    Button("Back to Play") { store.closeResult() }
                        .buttonStyle(ArenaActionStyle(prominent: false))
                        .disabled(store.isBusy || store.pending != nil)
                }
            }
        }
    }

    private var resultTitle: String {
        guard snapshot.phase != .incomplete else { return "Until next time." }
        let scores = snapshot.players.map(\.score)
        if Set(scores).count == 1 { return "Great minds.\nIt's a draw." }
        let winner = snapshot.players.max { $0.score < $1.score }
        return winner?.id == snapshot.viewerID ? "You won\nthe duel." : "\(winner?.nickname ?? "Your opponent")\ntakes the win."
    }

    private func playerRow(_ player: DuelPlayer) -> some View {
        HStack(spacing: 12) {
            Image(systemName: player.id == snapshot.viewerID ? "person.crop.circle.fill" : "person.crop.circle")
                .font(.title).foregroundStyle(ArenaPalette.teal)
            VStack(alignment: .leading, spacing: 3) {
                Text(player.nickname).font(.headline)
                Text(player.id == snapshot.viewerID ? "You" : "Your opponent")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Label(player.ready ? "Ready" : "Not ready", systemImage: player.ready ? "checkmark.circle.fill" : "circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(player.ready ? ArenaPalette.teal : .secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
