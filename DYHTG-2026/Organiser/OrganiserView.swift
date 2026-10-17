import AlgorithmArenaCore
import SwiftUI

struct OrganiserView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var organiserID: String?
    @State private var requestText = ""
    @State private var approval: ArrivalApproval?
    @State private var failure: String?
    @State private var isIssuing = false
    @State private var isScanning = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button("Scan Check-In Request", systemImage: "qrcode.viewfinder") { isScanning = true }
                        .disabled(!CodeScanner.isAvailable || isIssuing)
                } footer: {
                    Text("Scan the code on the player's Organiser Check-In screen, then let them scan your approval.")
                }

                Section("Or Paste a Request") {
                    TextField("Request", text: $requestText, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Approve Check-In") { issue(requestText) }
                        .disabled(ArrivalRequest(code: requestText) == nil || isIssuing)
                }

                if isIssuing {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Approving")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if let approval {
                    Section {
                        QRCodeView(text: approval.code)
                            .frame(maxWidth: 240)
                            .frame(maxWidth: .infinity)
                            .listRowBackground(Color.clear)
                        LabeledContent("Code") {
                            Text(approval.approvalID)
                                .font(.footnote)
                                .textSelection(.enabled)
                        }
                        LabeledContent("Expires") {
                            Text(approval.expiresAt, style: .relative)
                        }
                    } header: {
                        Text("Approval")
                    } footer: {
                        Text("Single use. The player scans this or enters the code.")
                    }
                } else if let failure {
                    Section {
                        Text(failure)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    LabeledContent("Organiser ID") {
                        Text(organiserID ?? "Loading...")
                            .font(.footnote)
                            .textSelection(.enabled)
                    }
                } footer: {
                    Text("An administrator grants organiser access to this ID. Only organisers can approve check-ins.")
                }
            }
            .navigationTitle("Organiser Tools")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $isScanning) {
                CodeScannerSheet(
                    title: "Scan Request",
                    instructions: "Point the camera at the player's check-in code."
                ) { payload in
                    issue(payload)
                }
            }
            .task { organiserID = await OrganiserService.userID() }
        }
    }

    private func issue(_ code: String) {
        guard let request = ArrivalRequest(code: code.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            failure = "That isn't an Arena check-in request."
            approval = nil
            return
        }
        isIssuing = true
        Task {
            defer { isIssuing = false }
            do {
                approval = try await OrganiserService.issueApproval(for: request)
                failure = nil
            } catch let error as MatchServiceError {
                approval = nil
                failure = error.message
            } catch {
                approval = nil
                failure = "Arena can't connect right now. Check your connection and try again."
            }
        }
    }
}
