import SwiftUI
import Supabase

struct BattlesView: View {
    @Bindable var store: BattleStore
    @AppStorage("nickname") private var nickname = ""
    @AppStorage("battleAvatar") private var avatar = "person.crop.circle.fill"
    @State private var roomCode = ""
    @State private var showingProfile = false
    @State private var confirmingLeave = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        List {
            if let state = store.state {
                Section {
                    if store.disconnected { Label("Reconnecting… Your match is saved.", systemImage: "wifi.exclamationmark").foregroundStyle(.orange) }
                    if state.phase == "lobby" {
                        LabeledContent("Private Room", value: state.code).font(.headline.monospaced())
                        ShareLink(item: "Join my Algorithm Arena battle. In Challenge a Friend, enter room code \(state.code).") { Label("Share Room Code", systemImage: "square.and.arrow.up") }
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 24) { ForEach(state.players) { meter($0) } }
                        VStack(spacing: 16) { ForEach(state.players) { meter($0) } }
                    }
                    if state.players.count < 2 { Label("Waiting for your friend…", systemImage: "person.badge.clock") }
                    if let opponent = state.opponent, !opponent.online, state.phase == "playing" {
                        Text("Your friend is offline. Scoring pauses until they return. After five minutes this match is abandoned without affecting statistics.").font(.caption).foregroundStyle(.secondary)
                    }
                    if let notice = store.opponentNotice { Text(notice).font(.caption).foregroundStyle(.tint) }
                }
                if state.phase == "lobby" {
                    Section {
                        Text("Race to 100 through shared, progressively harder challenges. Correct solutions earn 12–24 progress; a fast first attempt can earn 3 extra. Incorrect attempts earn nothing.").font(.subheadline).foregroundStyle(.secondary)
                        PrimaryButton(title: state.me?.ready == true ? "Not Ready" : "I'm Ready", isBusy: store.busy) {
                            Task { await store.act("ready", fields: ["ready": .bool(state.me?.ready != true)]) }
                        }
                    } footer: { Text("Both players must be ready. The match starts automatically.") }
                } else if state.phase == "playing" {
                    if let feedback = store.feedback {
                        Section(feedback.correct ? "+\(feedback.earned) Progress" : "Try Again") {
                            Label(feedback.correct ? "Correct solution" : "Keep exploring", systemImage: feedback.correct ? "checkmark.circle.fill" : "arrow.trianglehead.clockwise")
                            Text(feedback.explanation)
                            if !feedback.solution.isEmpty { Text("Solution: " + feedback.solution.map(String.init).joined(separator: " → ")).font(.caption.monospaced()) }
                            Button(feedback.correct ? "Next Challenge" : "Continue") { store.feedback = nil }
                        }
                        if feedback.correct, let challenge = store.feedbackChallenge {
                            BattleChallengeView(challenge: challenge, busy: false, replay: feedback.solution) { _ in }
                        }
                    } else if let challenge = state.challenge {
                        BattleChallengeView(challenge: challenge, busy: store.busy) { answer in
                            Task { await store.act("submit", fields: ["round": .integer(challenge.round), "answer": .array(answer.map { .integer($0) })]) }
                        }.id(challenge.round)
                    }
                } else {
                    Section {
                        Image(systemName: state.winner == state.viewer ? "trophy.fill" : "flag.checkered").font(.system(size: 56)).foregroundStyle(.tint).symbolEffect(.pulse, options: .nonRepeating, isActive: !reduceMotion && state.winner == state.viewer).frame(maxWidth: .infinity).padding()
                        Text(state.phase == "abandoned" ? "Match Abandoned" : state.winner == state.viewer ? "VICTORY!" : "GOOD GAME!").font(.largeTitle.bold()).frame(maxWidth: .infinity)
                        if let winner = state.players.first(where: { $0.id == state.winner }) { Label("\(winner.nickname) wins", systemImage: winner.avatar) }
                        if let me = state.me {
                            LabeledContent("Final Score", value: "\(me.score)")
                            LabeledContent("Challenges Completed", value: "\(me.correct)")
                            LabeledContent("Accuracy", value: me.attempts == 0 ? "—" : "\(me.correct*100/me.attempts)%")
                            LabeledContent("Difficulty Reached", value: difficulty(me.round))
                        }
                        if let start = state.startedAt, let finish = state.finishedAt, let seconds = duration(start, finish) { LabeledContent("Match Duration", value: "\(seconds/60)m \(seconds%60)s") }
                        PrimaryButton(title: "Play Again", isBusy: store.busy) { Task { await store.act("rematch") } }
                        Button("Return Home") { Task { await store.close(); if store.state == nil { dismiss() } } }
                        NavigationLink("View Profile") { ProfileView(store: store) }
                    }
                }
                Section {
                    NavigationLink { PathfinderView(battles: store) } label: { Label("Find My Friend", systemImage: "location.circle") }
                    if ["lobby","playing"].contains(state.phase) { Button("Leave Room", role: .destructive) { confirmingLeave = true } }
                }
            } else {
                Section {
                    Label("Challenge a Friend", systemImage: "person.2.fill").font(.title2.bold())
                    Text("Solve paths, explore graphs, sort values and search efficiently. The first to 100 wins.").foregroundStyle(.secondary)
                    if !store.signedIn { NavigationLink("Connect Your Player Account") { ProfileView(store: store) } }
                    else {
                        NavigationLink("Player Profile") { ProfileView(store: store) }
                        Button("Resume My Room") { Task { await store.recover() } }
                        PrimaryButton(title: "Create Private Room", isBusy: store.busy) { enter("create") }
                        TextField("Room code", text: $roomCode).textInputAutocapitalization(.characters).autocorrectionDisabled()
                        Button("Join Room") { enter("join", fields: ["code": .string(roomCode)]) }.disabled(roomCode.trimmingCharacters(in: .whitespacesAndNewlines).count != 10 || store.busy)
                    }
                } footer: { Text("A private code connects two players on any device. Location is never shared by joining a room.") }
            }
            if let error = store.error { Section { Text(error).foregroundStyle(.red); Button("Dismiss") { store.error = nil } } }
        }
        .navigationTitle("Battles")
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: store.state?.me?.score)
        .task { await store.recover() }
        .refreshable { await store.refresh() }
        .confirmationDialog("Leave this match? Unfinished matches do not affect statistics.", isPresented: $confirmingLeave, titleVisibility: .visible) {
            Button("Leave Room", role: .destructive) { Task { await store.close() } }
        }
    }
    private func enter(_ action: String, fields: [String: AnyJSON] = [:]) {
        Task {
            await store.saveProfile(nickname: nickname, avatar: avatar)
            guard store.error == nil else { return }
            await store.act(action, fields: fields)
        }
    }
    private func meter(_ player: BattlePlayer) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(player.nickname, systemImage: player.avatar).font(.headline)
            HStack { Text("\(player.score)%").font(.title2.bold().monospacedDigit()); Spacer(); Text(player.ready ? "Ready" : player.online ? "Connected" : "Offline").font(.caption).foregroundStyle(.secondary) }
            ProgressView(value: Double(player.score), total: 100).tint(.accentColor)
            Text("Round \(player.round) · \(difficulty(player.round))").font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: player.score)
    }
    private func difficulty(_ round: Int) -> String { round <= 2 ? "Easy" : round <= 4 ? "Medium" : round == 5 ? "Hard" : "Advanced" }
    private func duration(_ start: String, _ end: String) -> Int? {
        guard let a = BattleTime.date(start), let b = BattleTime.date(end) else { return nil }
        return max(0,Int(b.timeIntervalSince(a)))
    }
}
