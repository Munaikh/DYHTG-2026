import SwiftUI
import VisionKit

struct CodeScanner: UIViewControllerRepresentable {
    let onScan: (String) -> Void
    var onFailure: (String) -> Void = { _ in }

    static var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan, onFailure: onFailure)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        do {
            try scanner.startScanning()
        } catch {
            // Defer presentation changes until the representable has been mounted.
            Task { @MainActor in context.coordinator.fail() }
        }
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onScan: (String) -> Void
        private let onFailure: (String) -> Void
        private var didScan = false

        init(onScan: @escaping (String) -> Void, onFailure: @escaping (String) -> Void) {
            self.onScan = onScan
            self.onFailure = onFailure
        }

        func fail() {
            guard !didScan else { return }
            didScan = true
            onFailure("The camera couldn’t start.")
        }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            dataScanner.stopScanning()
            fail()
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !didScan else { return }
            for case .barcode(let barcode) in addedItems {
                guard let payload = barcode.payloadStringValue else { continue }
                didScan = true
                dataScanner.stopScanning()
                onScan(payload)
                return
            }
        }
    }
}

struct CodeScannerSheet: View {
    let title: String
    let instructions: String
    let onScan: (String) -> Void
    var onFailure: (String) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            CodeScanner(onScan: { payload in
                onScan(payload)
                dismiss()
            }, onFailure: { message in
                onFailure(message)
                dismiss()
            })
            .ignoresSafeArea()
            .overlay(alignment: .bottom) {
                Text(instructions)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .padding(16)
                    .background(.regularMaterial, in: .rect(cornerRadius: 16))
                    .padding(20)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if #available(iOS 26, *) {
                        Button(role: .close) { dismiss() }
                    } else {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
    }
}
