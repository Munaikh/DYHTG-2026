import AlgorithmArenaCore
import SwiftUI

struct HomeView: View {
    let store: MatchStore

    @AppStorage("nickname") private var nickname = ""
    @State private var isJoining = false
    @State private var isCreating = false
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

                Section {
                } footer: {
                    Text("Pick Dijkstra or A*, then walk from the James McCune Smith Learning Hub to the Library. At each of three checkpoints, predict what the algorithm does next. Reasoning scores points; walking speed doesn't.")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("New Match")
            .bottomActions {
                Group {
                    PrimaryButton(title: "Create Room", busyTitle: "Creating Room...", isBusy: isCreating, action: createRoom)

                    Button {
                        nicknameFocused = false
                        isJoining = true
                    } label: {
                        Text("Join with Code")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isCreating)
                }
                .disabled(!nicknameIsValid)
            }
            .sheet(isPresented: $isJoining) {
                JoinRoomSheet(store: store, nickname: trimmedNickname)
            }
            .actionErrorAlert($failure, retry: createRoom)
        }
    }

    private func createRoom() {
        guard !isCreating else { return }
        nicknameFocused = false
        isCreating = true
        Task {
            defer { isCreating = false }
            do {
                try await store.createRoom(nickname: trimmedNickname, algorithm: .dijkstra)
            } catch let error as MatchServiceError {
                failure = ActionError(error, canRetry: true)
            } catch {
                failure = .connectionLost
            }
        }
    }
}

#Preview {
    HomeView(store: .demo())
}
