import SwiftUI

struct OrganiserCheckInSheet: View {
    let stopTitle: String
    let request: ArrivalRequest?
    let submit: (String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var isSubmitting = false
    @State private var isScanning = false

    private var approvalID: String? {
        ArrivalApproval.approvalID(from: code)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let request {
                    Section {
                        QRCodeView(text: request.code)
                            .frame(maxWidth: 240)
                            .frame(maxWidth: .infinity)
                            .listRowBackground(Color.clear)
                    } header: {
                        Text("Show This to an Organiser")
                    } footer: {
                        Text("They scan it to approve your check-in at \(stopTitle).")
                    }

                    if CodeScanner.isAvailable {
                        Section {
                            Button("Scan Their Approval", systemImage: "qrcode.viewfinder") { isScanning = true }
                        } footer: {
                            Text("Approvals expire after two minutes and work once.")
                        }
                    }
                }

                Section {
                    TextField("Approval code", text: $code)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit(send)
                } header: {
                    Text(request == nil ? "Approval Code" : "Or Enter the Code")
                } footer: {
                    if request == nil {
                        Text("If your location can't be confirmed at \(stopTitle), an organiser can approve your check-in with a one-time code.")
                    }
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
                            .disabled(approvalID == nil)
                    }
                }
            }
            .sheet(isPresented: $isScanning) {
                CodeScannerSheet(
                    title: "Scan Approval",
                    instructions: "Point the camera at the organiser's approval code."
                ) { payload in
                    code = payload
                    send()
                }
            }
        }
        .interactiveDismissDisabled(isSubmitting)
    }

    private func send() {
        guard let approvalID, !isSubmitting else { return }
        isSubmitting = true
        Task {
            await submit(approvalID)
            isSubmitting = false
            dismiss()
        }
    }
}
