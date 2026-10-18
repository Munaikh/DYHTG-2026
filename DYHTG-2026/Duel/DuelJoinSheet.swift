import AlgorithmArenaCore
import AVFoundation
import SwiftUI

struct DuelJoinSheet: View {
    let nickname: String
    @Bindable var store: DuelStore
    @Environment(\.dismiss) private var dismiss
    @FocusState private var codeFocused: Bool
    @State private var code = ""
    @State private var showingScanner = false
    @State private var requestingCamera = false
    @State private var scannedPayload: String?
    @State private var scannerMessage: String?

    private var cleanNickname: String { nickname.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var roomCode: String? { DuelInvitation.roomCode(from: code) }
    private var canJoin: Bool {
        roomCode != nil && (2...20).contains(cleanNickname.count) && store.canAct
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Enter the six-character room code, or scan the QR code on your friend’s screen.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Room code").font(.headline)
                        TextField("ABC123", text: $code)
                            .font(.system(.title, design: .monospaced).weight(.semibold))
                            .keyboardType(.asciiCapable)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .submitLabel(.join)
                            .focused($codeFocused)
                            .padding(16)
                            .background(ArenaPalette.surface, in: .rect(cornerRadius: 14))
                            .accessibilityLabel("Room code")
                            .accessibilityIdentifier("duel.code")
                            .disabled(!store.canAct)
                            .onSubmit { join() }
                            .onChange(of: code) { _, value in
                                let normalized = String(value.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(6))
                                if code != normalized { code = normalized }
                                scannerMessage = nil
                            }
                        if code.count == 6 && roomCode == nil {
                            Text("Room codes use letters A–F and numbers 0–9.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Button(action: join) {
                        HStack {
                            Text(store.isBusy ? "Joining…" : "Join duel")
                            if store.isBusy { ProgressView() }
                        }
                    }
                    .buttonStyle(ArenaActionStyle())
                    .disabled(!canJoin)
                    .accessibilityIdentifier("duel.confirmJoin")

                    Button {
                        codeFocused = false
                        Task { await scan() }
                    } label: {
                        Label(requestingCamera ? "Checking camera…" : "Scan QR code", systemImage: "qrcode.viewfinder")
                    }
                    .buttonStyle(ArenaActionStyle(prominent: false))
                    .disabled(requestingCamera || !store.canAct)
                    .accessibilityIdentifier("duel.scan")

                    if let scannerMessage {
                        Text(scannerMessage)
                            .font(.subheadline).foregroundStyle(.secondary)
                            .accessibilityIdentifier("duel.scanMessage")
                    }
                    if let error = store.error {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(error.title).font(.headline)
                            Text(error.message).font(.subheadline).foregroundStyle(.secondary)
                        }
                        .accessibilityIdentifier("duel.joinError")
                    }
                    if store.pending != nil && store.isOffline {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Waiting for a connection") .font(.headline)
                            Text("Your join request is saved. We’ll retry it when the connection returns.")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Button("Retry now") { Task { await store.retry() } }
                                .disabled(store.isBusy)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: 650)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(ArenaPalette.canvas)
            .navigationTitle("Join a duel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showingScanner, onDismiss: consumeScan) {
                CodeScannerSheet(
                    title: "Scan room code",
                    instructions: "Point the camera at the QR code in your friend’s duel lobby.",
                    onScan: { scannedPayload = $0 },
                    onFailure: { scannerMessage = $0 + " You can enter the room code instead." }
                )
            }
            .onChange(of: store.snapshot?.id) { _, roomID in
                if roomID != nil { dismiss() }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(ArenaPalette.canvas)
    }

    private func join() {
        guard canJoin, let roomCode else { return }
        codeFocused = false
        Task { await store.join(nickname: cleanNickname, code: roomCode) }
    }

    private func scan() async {
        scannerMessage = nil
        #if targetEnvironment(simulator)
        scannerMessage = "QR scanning isn’t available in the simulator. Enter the room code instead."
        #else
        requestingCamera = true
        defer { requestingCamera = false }
        let authorized: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            authorized = true
        case .notDetermined:
            authorized = await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            authorized = false
        @unknown default:
            authorized = false
        }
        guard authorized else {
            scannerMessage = "Camera access is unavailable. Enter the room code instead, or allow camera access in Settings."
            return
        }
        guard CodeScanner.isAvailable else {
            scannerMessage = "QR scanning isn’t available on this device right now. Enter the room code instead."
            return
        }
        showingScanner = true
        #endif
    }

    private func consumeScan() {
        guard let payload = scannedPayload else { return }
        scannedPayload = nil
        guard let scannedCode = DuelInvitation.roomCode(from: payload) else {
            scannerMessage = "That QR code isn’t a valid duel invitation. Scan the code in your friend’s lobby, or enter their room code."
            return
        }
        code = scannedCode
    }
}
