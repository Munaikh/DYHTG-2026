import AlgorithmArenaCore
import SwiftUI

struct PlayHomeView: View {
    @Bindable var store: DuelStore
    @AppStorage("nickname") private var nickname = ""
    @State private var algorithm = StudyAlgorithm.dijkstra
    @State private var joining = false
    @State private var leaving = false
    @FocusState private var nicknameFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(LearningStore.self) private var learning
    @State private var showingPractice = false

    private var cleanNickname: String { nickname.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var validNickname: Bool { (2...20).contains(cleanNickname.count) }

    // Polling, a submitted answer, and ready-state changes keep the user's place.
    // A new room, round, or phase starts a new reading context.
    private var scrollResetID: String {
        guard let snapshot = store.snapshot else { return "entry" }
        return "\(snapshot.id)-\(snapshot.roundIndex)-\(snapshot.phase.rawValue)"
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 20) {
                        if store.isOffline || store.pending != nil {
                            connectionBanner
                        }
                        if let snapshot = store.snapshot {
                            DuelRoomView(store: store, snapshot: snapshot)
                        } else {
                            entry
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 12)
                    .frame(maxWidth: 650)
                    .frame(maxWidth: .infinity)
                    .id("duel-top")
                }
                .onChange(of: scrollResetID) { _, _ in
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                        proxy.scrollTo("duel-top", anchor: .top)
                    }
                }
            }
            .background(ArenaPalette.canvas)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(store.snapshot == nil ? "Play" : "Plot Twist Duel")
            .navigationBarTitleDisplayMode(store.snapshot == nil ? .large : .inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    ProfileButton()
                    if let snapshot = store.snapshot, snapshot.phase != .finished && snapshot.phase != .incomplete {
                        Button("Leave", systemImage: "rectangle.portrait.and.arrow.right") { leaving = true }
                            .labelStyle(.iconOnly)
                            .disabled(!store.canAct)
                    }
                }
            }
            .confirmationDialog("Leave this duel?", isPresented: $leaving, titleVisibility: .visible) {
                Button("Leave Duel", role: .destructive) { Task { await store.perform(.leave) } }
            } message: {
                Text("The match will end as incomplete for both players.")
            }
            .sheet(isPresented: $joining, onDismiss: { store.error = nil }) {
                DuelJoinSheet(nickname: cleanNickname, store: store)
            }
            .sheet(isPresented: $showingPractice) {
                LearnLibrary(learning: learning, mode: .practice, dismissable: true)
            }
            .alert(item: Binding(get: { joining ? nil : store.error }, set: { store.error = $0 })) { error in
                if error.canRetry {
                    Alert(title: Text(error.title), message: Text(error.message),
                          primaryButton: .default(Text("Retry")) { Task { await store.retry() } },
                          secondaryButton: .cancel(Text("Dismiss")))
                } else {
                    Alert(title: Text(error.title), message: Text(error.message), dismissButton: .default(Text("OK")))
                }
            }
        }
    }

    private var entry: some View {
        VStack(spacing: 24) {
            DuelHero()
            VStack(alignment: .leading, spacing: 16) {
                Text("Set up a duel").font(.headline)
                TextField("Your nickname", text: $nickname)
                    .font(.title3.weight(.semibold))
                    .textContentType(.nickname)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($nicknameFocused)
                    .onSubmit { nicknameFocused = false }
                    .padding(16)
                    .background(ArenaPalette.canvas, in: .rect(cornerRadius: 14))
                    .accessibilityIdentifier("duel.nickname")
                    .onChange(of: nickname) { _, value in
                        if value.count > 20 { nickname = String(value.prefix(20)) }
                    }
                Picker("Algorithm", selection: $algorithm) {
                    ForEach(StudyAlgorithm.allCases) { kind in
                        Label(kind.name, systemImage: kind.symbol).tag(kind)
                    }
                }
                .pickerStyle(.menu)
                Text(algorithm.rule)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ArenaGlassGroup(spacing: 12) {
                    VStack(spacing: 12) {
                        Button {
                            nicknameFocused = false
                            Task { await store.create(nickname: cleanNickname, algorithm: algorithm) }
                        } label: {
                            HStack {
                                Text(store.isBusy ? "Creating room…" : "Create a duel")
                                if store.isBusy { ProgressView() }
                                else { Image(systemName: "chevron.right") }
                            }
                        }
                        .buttonStyle(ArenaActionStyle())
                        .disabled(!validNickname || !store.canAct)
                        .accessibilityIdentifier("duel.create")

                        Button("Join a duel", systemImage: "qrcode.viewfinder") { nicknameFocused = false; joining = true }
                            .buttonStyle(ArenaActionStyle(prominent: false))
                            .disabled(!validNickname || !store.canAct)
                            .accessibilityIdentifier("duel.join")
                    }
                }
                if !validNickname {
                    Text("Choose a nickname with 2–20 characters.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .arenaCard()
            Label("Reasoning wins. There’s no speed bonus.", systemImage: "brain")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button { showingPractice = true } label: {
                HStack(spacing: 14) {
                    Image(systemName: "puzzlepiece.extension.fill").font(.title2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Warm up with a puzzle").font(.headline)
                        Text("15 solo challenges · all 5 algorithms")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                }.arenaCard()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("duel.practice")
        }
    }

    private var connectionBanner: some View {
        HStack(spacing: 12) {
            ProgressView()
            VStack(alignment: .leading, spacing: 3) {
                Text(store.isBusy ? "Syncing your action" : "Reconnecting to your duel")
                    .font(.subheadline.weight(.semibold))
                Text("Your progress is saved.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .arenaCard()
        .accessibilityElement(children: .combine)
    }

}

private struct DuelHero: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Plot Twist Duel")
                .font(.title2.bold())
            Text("Challenge a friend over three rounds. Predict each move, then adapt when a bridge closes.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
