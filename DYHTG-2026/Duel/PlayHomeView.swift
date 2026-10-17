import AlgorithmArenaCore
import SwiftUI

struct PlayHomeView: View {
    @Bindable var store: DuelStore
    @AppStorage("nickname") private var nickname = ""
    @State private var algorithm = AlgorithmKind.dijkstra
    @State private var joinCode = ""
    @State private var joining = false
    @State private var leaving = false
    @FocusState private var nicknameFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                ToolbarItem(placement: .topBarTrailing) { ProfileButton() }
                if let snapshot = store.snapshot, snapshot.phase != .finished && snapshot.phase != .incomplete {
                    ToolbarItem(placement: .topBarTrailing) {
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
            .sheet(isPresented: $joining) { joinSheet }
            .alert(item: $store.error) { error in
                if error.canRetry {
                    Alert(title: Text(error.title), message: Text(error.message),
                          primaryButton: .default(Text("Retry")) { Task { await store.retry() } },
                          secondaryButton: .cancel(Text("Keep Trying")))
                } else {
                    Alert(title: Text(error.title), message: Text(error.message), dismissButton: .default(Text("OK")))
                }
            }
        }
    }

    private var entry: some View {
        VStack(spacing: 24) {
            DuelHero()
            HStack(spacing: 0) {
                fact("2", caption: "players")
                Spacer()
                fact("3", caption: "rounds")
                Spacer()
                fact("1", caption: "plot twist")
            }
            .padding(.horizontal, 12)

            VStack(alignment: .leading, spacing: 16) {
                ArenaEyebrow(text: "Enter the arena")
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
                    Text("Dijkstra").tag(AlgorithmKind.dijkstra)
                    Text("A*").tag(AlgorithmKind.aStar)
                }
                .pickerStyle(.segmented)
                Text(algorithm == .dijkstra ? "Follow the cheapest known cost." : "Balance the cost so far with an estimate ahead.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    nicknameFocused = false
                    Task { await store.create(nickname: cleanNickname, algorithm: algorithm) }
                } label: {
                    HStack {
                        Text(store.isBusy ? "Creating room…" : "Create a Duel")
                        if store.isBusy { ProgressView() }
                        else { Image(systemName: "arrow.up.right") }
                    }
                }
                .buttonStyle(ArenaActionStyle())
                .disabled(!validNickname || !store.canAct)
                .accessibilityIdentifier("duel.create")

                Button("Join with a Code") { nicknameFocused = false; joining = true }
                    .buttonStyle(ArenaActionStyle(prominent: false))
                    .disabled(!validNickname || !store.canAct)
                    .accessibilityIdentifier("duel.join")
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
        }
    }

    private var joinSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                Text("Meet in the same arena.")
                    .font(.largeTitle.bold())
                Text("Enter the six-character code on your friend's screen.")
                    .foregroundStyle(.secondary)
                TextField("ROOM CODE", text: $joinCode)
                    .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                    .keyboardType(.asciiCapable)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .padding(20)
                    .background(ArenaPalette.canvas, in: .rect(cornerRadius: 18))
                    .accessibilityIdentifier("duel.code")
                    .onChange(of: joinCode) { _, value in
                        let normalized = String(value.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(6))
                        if normalized != value { joinCode = normalized }
                    }
                Button("Join Duel") {
                    joining = false
                    Task { await store.join(nickname: cleanNickname, code: joinCode) }
                }
                .buttonStyle(ArenaActionStyle())
                .disabled(joinCode.count != 6 || !store.canAct)
                .accessibilityIdentifier("duel.confirmJoin")
                Spacer()
            }
            .padding(24)
            .navigationTitle("Join a Duel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { joining = false } } }
        }
        .presentationDetents([.medium, .large])
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

    private func fact(_ value: String, caption: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.system(.title, design: .rounded).bold())
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct DuelHero: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                ArenaEyebrow(text: "Think together. Compete.", color: ArenaPalette.mint)
                Spacer(minLength: 4)
                Image(systemName: "bolt.shield.fill").foregroundStyle(ArenaPalette.mint)
            }
            Text("Plot Twist\nDuel")
                .font(.system(size: 43, weight: .bold, design: .rounded))
                .tracking(-1.5)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(ArenaPalette.mint)
                    .accessibilityHidden(true)
                Text("Predict the next move.\nThen the world changes.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .padding(26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ArenaPalette.ink.gradient, in: .rect(cornerRadius: 28))
    }
}
