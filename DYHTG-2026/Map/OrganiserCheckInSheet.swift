import SwiftUI

struct OrganiserCheckInSheet: View {
    let stopTitle: String
    let submit: (String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var isSubmitting = false
    @FocusState private var focused: Bool

    private var trimmed: String {
        code.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Approval code", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($focused)
                        .onSubmit(send)
                } footer: {
                    Text("If your location can't be confirmed at \(stopTitle), an organiser can approve your check-in with a one-time code.")
                }
            }
            .navigationTitle("Organiser Check-In")
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
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Button("Check In", action: send)
                            .disabled(trimmed.isEmpty)
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled(isSubmitting)
        .onAppear { focused = true }
    }

    private func send() {
        guard !trimmed.isEmpty, !isSubmitting else { return }
        isSubmitting = true
        Task {
            await submit(trimmed)
            isSubmitting = false
            dismiss()
        }
    }
}
