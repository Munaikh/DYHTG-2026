import ARKit
import AlgorithmArenaCore
import RealityKit
import SwiftUI

struct ARGraphView: UIViewRepresentable {
    enum Tracking: Equatable {
        case searching
        case limited
        case ready
    }

    let presentation: SearchPresentation
    let highlightedEdge: (from: NodeID, to: NodeID)?
    let isActive: Bool
    @Binding var tracking: Tracking

    func makeCoordinator() -> Coordinator {
        Coordinator(tracking: $tracking)
    }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        view.session.delegate = context.coordinator
        context.coordinator.run(view.session)

        let coaching = ARCoachingOverlayView()
        coaching.session = view.session
        coaching.goal = .horizontalPlane
        coaching.activatesAutomatically = true
        coaching.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(coaching)

        let anchor = AnchorEntity(.plane(.horizontal, classification: .any, minimumBounds: [0.3, 0.3]))
        view.scene.addAnchor(anchor)
        context.coordinator.build(presentation, on: anchor)
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {
        context.coordinator.update(presentation, highlightedEdge: highlightedEdge)
        if isActive {
            context.coordinator.resume(view.session)
        } else {
            view.session.pause()
            context.coordinator.isPaused = true
        }
    }

    static func dismantleUIView(_ view: ARView, coordinator: Coordinator) {
        view.session.pause()
    }

    @MainActor
    final class Coordinator: NSObject, ARSessionDelegate {
        @Binding var tracking: Tracking
        var isPaused = false
        private let scene = ARGraphScene()

        init(tracking: Binding<Tracking>) {
            _tracking = tracking
        }

        func run(_ session: ARSession) {
            let configuration = ARWorldTrackingConfiguration()
            configuration.planeDetection = [.horizontal]
            session.run(configuration)
        }

        func resume(_ session: ARSession) {
            guard isPaused else { return }
            isPaused = false
            run(session)
        }

        func build(_ presentation: SearchPresentation, on anchor: AnchorEntity) {
            scene.build(presentation, on: anchor)
        }

        func update(_ presentation: SearchPresentation, highlightedEdge: (from: NodeID, to: NodeID)?) {
            scene.update(presentation, highlightedEdge: highlightedEdge)
        }

        nonisolated func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
            let state: Tracking = switch camera.trackingState {
            case .normal: .ready
            case .limited: .limited
            case .notAvailable: .searching
            }
            MainActor.assumeIsolated {
                if tracking != state { tracking = state }
            }
        }
    }
}
