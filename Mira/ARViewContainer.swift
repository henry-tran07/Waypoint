import SwiftUI
import ARKit
import RealityKit
import Combine

struct ARViewContainer: UIViewRepresentable {
    @EnvironmentObject var store: SceneStore

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic
        // LiDAR mesh reconstruction — only available on iPhone Pro/Max with LiDAR
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            config.sceneReconstruction = .meshWithClassification
        }
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        arView.session.delegate = context.coordinator

        context.coordinator.configure(store: store, arView: arView)
        return arView
    }

    // updateUIView intentionally empty — SwiftUI drives store changes via Combine, not re-renders
    func updateUIView(_ uiView: ARView, context: Context) {}

    // MARK: - Coordinator

    final class Coordinator: NSObject, ARSessionDelegate {
        private var cancellables = Set<AnyCancellable>()
        private weak var arView: ARView?
        private var detectionService: DetectionService?
        private var currentAnchor: AnchorEntity?

        @MainActor func configure(store: SceneStore, arView: ARView) {
            self.arView = arView
            detectionService = DetectionService(arView: arView, store: store)
            detectionService?.start()

            store.$activeTarget
                .receive(on: DispatchQueue.main)
                .sink { [weak self] target in self?.handleTargetChange(target) }
                .store(in: &cancellables)
        }

        private func handleTargetChange(_ target: (label: String, position: SIMD3<Float>)?) {
            guard let arView else { return }

            // Remove previous arrow anchor
            if let existing = currentAnchor {
                arView.scene.removeAnchor(existing)
                currentAnchor = nil
            }

            guard let target else { return }

            // Build world-space transform matrix at target position
            var matrix = float4x4(1) // 4×4 identity
            matrix.columns.3 = SIMD4<Float>(target.position.x, target.position.y, target.position.z, 1)

            let anchor = AnchorEntity(world: matrix)
            anchor.addChild(ArrowEntity.make())
            arView.scene.addAnchor(anchor)
            currentAnchor = anchor
        }

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            CameraReference.shared.current = Transform(matrix: frame.camera.transform)
        }
    }
}
