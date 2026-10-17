import SwiftUI

struct ProfileView: View {
    @Bindable var store: BattleStore
    @AppStorage("nickname") private var nickname = ""
    @AppStorage("battleAvatar") private var avatar = "person.crop.circle.fill"
    @State private var email = ""
    @State private var code = ""
    @State private var codeSent = false
    let avatars = ["person.crop.circle.fill", "hare.fill", "tortoise.fill", "bird.fill"]

    var body: some View {
        Form {
            Section("Player Profile") {
                Image(systemName: avatar).font(.system(size: 52)).foregroundStyle(.tint).frame(maxWidth: .infinity).padding()
                TextField("Nickname", text: $nickname).textContentType(.nickname)
                    .onChange(of: nickname) { nickname = String(nickname.prefix(20)) }
                Picker("Avatar", selection: $avatar) {
                    ForEach(avatars, id: \.self) { icon in Image(systemName: icon).tag(icon) }
                }
                if store.signedIn {
                    Button("Save Profile") { Task { await store.saveProfile(nickname: nickname, avatar: avatar) } }
                        .disabled(store.busy || nickname.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                    Label("Account connected · available on your other devices", systemImage: "checkmark.shield")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if !store.signedIn {
                Section {
                    TextField("Email", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button(codeSent ? "Send Another Code" : "Email a Sign-in Code") {
                        Task { await store.sendCode(email: email); codeSent = store.error == nil }
                    }.disabled(store.busy || !email.contains("@"))
                    if codeSent {
                        TextField("Email code", text: $code).textContentType(.oneTimeCode).keyboardType(.numberPad)
                        Button("Verify & Connect Account") {
                            Task {
                                await store.verify(email: email, code: code)
                                if store.signedIn {
                                    await store.stats()
                                    if store.statistics?.profile == nil && nickname.count >= 2 {
                                        await store.saveProfile(nickname: nickname, avatar: avatar)
                                    }
                                }
                            }
                        }.disabled(store.busy || code.count < 6)
                    }
                } header: { Text("Play Across Devices") } footer: {
                    Text("Use the same email on each device to restore your battle statistics. Email sign-in requires the Supabase email provider and code template described in the setup guide.")
                }
            }
            if let stats = store.statistics {
                Section("Battle Statistics") {
                    HStack {
                        metric("Wins", stats.wins); metric("Losses", stats.matches-stats.wins); metric("Matches", stats.matches)
                    }
                    LabeledContent("Win Rate", value: stats.matches == 0 ? "No matches yet" : "\(Int(Double(stats.wins)/Double(stats.matches)*100))%")
                    ProgressView(value: Double(stats.wins), total: Double(max(1,stats.matches))).accessibilityLabel("Wins out of all completed matches")
                    LabeledContent("Current Win Streak", value: "\(stats.currentStreak)")
                    LabeledContent("Best Win Streak", value: "\(stats.bestStreak)")
                }
                Section("Recent Matches") {
                    if stats.history.isEmpty { ContentUnavailableView("Your first battle awaits", systemImage: "flag.checkered", description: Text("Completed friend battles will appear here.")) }
                    ForEach(stats.history) { match in
                        HStack {
                            Image(systemName: match.won ? "trophy.fill" : "flag.checkered").foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(match.opponent).font(.headline)
                                Text("\(match.won ? "Win" : "Loss") · \(match.score) points · \(match.difficulty)").font(.caption)
                                Text(BattleTime.date(match.completedAt)?.formatted(date: .abbreviated, time: .shortened) ?? String(match.completedAt.prefix(10))).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            if store.busy { ProgressView() }
            if let error = store.error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("Profile")
        .task { await store.stats() }
        .refreshable { await store.stats() }
    }
    private func metric(_ title: String, _ value: Int) -> some View {
        VStack { Text("\(value)").font(.title.bold().monospacedDigit()); Text(title).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity)
    }
}
