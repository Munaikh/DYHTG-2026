import AlgorithmArenaCore
import SwiftUI

struct HomeView: View {
    let store: MatchStore
    let battles: BattleStore

    @AppStorage("nickname") private var nickname = ""
    @State private var isJoining = false
    @State private var isShowingOrganiserTools = false
    @State private var isCreating = false
    @State private var lastMode = MatchStore.Mode.live
    @State private var failure: ActionError?
    @FocusState private var nicknameFocused: Bool

    private var trimmedNickname: String {
        nickname.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var nicknameIsValid: Bool {
        (2...20).contains(trimmedNickname.count)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nickname", text: $nickname)
                        .textContentType(.nickname)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($nicknameFocused)
                        .onChange(of: nickname) {
                            if nickname.count > 20 { nickname = String(nickname.prefix(20)) }
                        }
                } footer: {
                    Text("2-20 characters. Shown to the other player.")
                }

                Section("Explore More") {
                    NavigationLink { BattlesView(store: battles) } label: {
                        Label("Challenge a Friend", systemImage: "person.2.fill")
                    }
                    NavigationLink { PathfinderView(battles: battles) } label: {
                        Label("Explore Pathfinder", systemImage: "map")
                    }
                    NavigationLink { ProfileView(store: battles) } label: {
                        Label("Profile", systemImage: "person.crop.circle")
                    }
                }

                Section {
                } footer: {
                    Text("Pick Dijkstra or A*, then walk from the James McCune Smith Learning Hub to the Library. At each of three checkpoints, predict what the algorithm does next. Reasoning scores points; walking speed doesn't. Practice Solo pairs you with a simulated player.")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("New Match")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        NavigationLink { SettingsView() } label: { Label("Settings", systemImage: "gearshape") }
                        Button("Organiser Tools", systemImage: "person.badge.key") { isShowingOrganiserTools = true }
                    } label: {
                        Label("More", systemImage: "ellipsis")
                    }
                }
            }
            .sheet(isPresented: $isShowingOrganiserTools) {
                OrganiserView()
            }
            .bottomActions {
                Group {
                    PrimaryButton(title: "Create Room", busyTitle: "Creating Room...", isBusy: isCreating) {
                        createRoom(mode: .live)
                    }

                    Button {
                        nicknameFocused = false
                        isJoining = true
                    } label: {
                        Text("Join with Code")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isCreating)

                    Button("Practice Solo") { createRoom(mode: .practice) }
                        .buttonStyle(.borderless)
                        .disabled(isCreating)
                }
                .disabled(!nicknameIsValid)
            }
            .sheet(isPresented: $isJoining) {
                JoinRoomSheet(store: store, nickname: trimmedNickname)
            }
            .actionErrorAlert($failure, retry: { createRoom(mode: lastMode) })
        }
    }

    private func createRoom(mode: MatchStore.Mode) {
        guard !isCreating else { return }
        nicknameFocused = false
        isCreating = true
        lastMode = mode
        Task {
            defer { isCreating = false }
            do {
                try await store.createRoom(nickname: trimmedNickname, algorithm: .dijkstra, mode: mode)
            } catch let error as MatchServiceError {
                failure = ActionError(error, canRetry: true)
            } catch {
                failure = .connectionLost
            }
        }
    }
}

#Preview {
    HomeView(store: .preview(), battles: BattleStore())
}
