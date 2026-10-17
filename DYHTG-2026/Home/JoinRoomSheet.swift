import AlgorithmArenaCore
import SwiftUI

struct JoinRoomSheet: View {
    let store: MatchStore
    let nickname: String

    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var failure: String?
    @State private var isJoining = false
    @FocusState private var codeFocused: Bool

    private var normalizedCode: String {
        String(code.uppercased().filter { $0.isLetter || $0.isNumber })
    }

    private var canJoin: Bool {
        normalizedCode.count == 6 && !isJoining
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("ABC123", text: $code)
                        .font(.title2.weight(.semibold))
                        .kerning(3)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .submitLabel(.join)
                        .focused($codeFocused)
                        .onChange(of: code) {
                            failure = nil
                            if code.count > 6 { code = String(code.prefix(6)) }
                        }
                        .onSubmit(join)
                        .accessibilityLabel("Room code")
                } footer: {
                    if let failure {
                        Text(failure)
                            .foregroundStyle(.red)
                    } else {
                        Text("Enter the six-character code from the host's lobby.")
                    }
                }
            }
            .navigationTitle("Join Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if #available(iOS 26, *) {
                        Button(role: .close) { dismiss() }
                    } else {
                        Button("Cancel") { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isJoining {
                        ProgressView()
                    } else {
                        Button("Join", action: join)
                            .disabled(!canJoin)
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled(isJoining)
        .onAppear { codeFocused = true }
    }

    private func join() {
        guard canJoin else { return }
        isJoining = true
        Task {
            defer { isJoining = false }
            do {
                try await store.joinRoom(code: normalizedCode, nickname: nickname)
                dismiss()
            } catch let error as MatchServiceError {
                show(error.code.guidance)
            } catch {
                show("Arena can't connect right now. Check your connection and try again.")
            }
        }
    }

    private func show(_ message: String) {
        failure = message
        AccessibilityNotification.Announcement(message).post()
    }
}
