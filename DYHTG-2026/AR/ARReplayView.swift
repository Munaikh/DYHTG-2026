import ARKit
import AVFoundation
import AlgorithmArenaCore
import SwiftUI

struct ARReplayView: View {
    private enum CameraAccess {
        case checking
        case granted
        case denied
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var playback: ReplayPlayback
    @State private var access = CameraAccess.checking
    @State private var tracking = ARGraphView.Tracking.searching

    init(trace: SearchTrace, scenario: GraphScenario) {
        _playback = State(initialValue: ReplayPlayback(trace: trace, scenario: scenario))
    }

    static var isSupported: Bool {
        ARWorldTrackingConfiguration.isSupported
    }

    var body: some View {
        ZStack {
            switch access {
            case .checking:
                Color.black.ignoresSafeArea()
            case .granted:
                ARGraphView(
                    presentation: playback.presentation,
                    highlightedEdge: playback.highlightedEdge,
                    isActive: scenePhase == .active,
                    tracking: $tracking
                )
                .ignoresSafeArea()
            case .denied:
                ContentUnavailableView {
                    Label("Camera Access Is Off", systemImage: "camera")
                } description: {
                    Text("Allow camera access in Settings to place the replay on a table or floor, or use the 2D replay instead.")
                } actions: {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    Button("Use 2D Replay") { dismiss() }
                }
            }
        }
        .overlay(alignment: .topLeading) {
            Button("Close", systemImage: "xmark") {
                playback.isPlaying = false
                dismiss()
            }
            .labelStyle(.iconOnly)
            .font(.body.weight(.semibold))
            .buttonStyle(ArenaCompactButtonStyle(shape: .circle))
            .controlSize(.large)
            .padding(.leading, 16)
        }
        .overlay(alignment: .bottom) {
            if access == .granted {
                controls
            }
        }
        .task { await requestAccess() }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(statusTitle)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(playback.description)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
            ReplayControls(playback: playback)
        }
        .padding(16)
        .background(.regularMaterial, in: .rect(cornerRadius: 28))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var statusTitle: String {
        switch tracking {
        case .searching: "Point your iPhone at a table or the floor"
        case .limited: "Move slowly to keep the replay in place"
        case .ready: "Step \(playback.index + 1) of \(playback.trace.steps.count)"
        }
    }

    private func requestAccess() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            access = .granted
        case .notDetermined:
            access = await AVCaptureDevice.requestAccess(for: .video) ? .granted : .denied
        default:
            access = .denied
        }
    }
}
