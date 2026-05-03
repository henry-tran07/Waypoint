import ARKit
import RealityKit

enum Raycaster {
    static func raycast(in frame: ARFrame, arView: ARView, bbox: CGRect) -> SIMD3<Float> {
        let screenPoint = visionToScreen(bbox: bbox, viewBounds: arView.bounds)
        return worldPosition(screenPoint: screenPoint, frame: frame, arView: arView)
    }

    // Vision bbox: normalized, origin bottom-left, Y-up
    // ARView screen: pixels, origin top-left, Y-down
    private static func visionToScreen(bbox: CGRect, viewBounds: CGRect) -> CGPoint {
        CGPoint(
            x: (bbox.origin.x + bbox.width  / 2) * viewBounds.width,
            y: (1.0 - (bbox.origin.y + bbox.height / 2)) * viewBounds.height
        )
    }

    // Claude Vision bbox: normalized, origin top-left, Y-down — no Y-flip needed
    static func raycastFromTopLeft(in frame: ARFrame, arView: ARView, bbox: CGRect) -> SIMD3<Float> {
        let screenPoint = CGPoint(
            x: (bbox.origin.x + bbox.width  / 2) * arView.bounds.width,
            y: (bbox.origin.y + bbox.height / 2) * arView.bounds.height
        )
        return worldPosition(screenPoint: screenPoint, frame: frame, arView: arView)
    }

    static func worldPosition(screenPoint: CGPoint, frame: ARFrame, arView: ARView) -> SIMD3<Float> {
        let hits = arView.raycast(from: screenPoint, allowing: .estimatedPlane, alignment: .any)
        if let hit = hits.first {
            let c = hit.worldTransform.columns.3
            return SIMD3<Float>(c.x, c.y, c.z)
        }
        // Fallback: project camera forward vector to 2 m (ARKit -Z = forward in world)
        let cam = frame.camera.transform
        let pos = SIMD3<Float>(cam.columns.3.x, cam.columns.3.y, cam.columns.3.z)
        let fwd = SIMD3<Float>(-cam.columns.2.x, -cam.columns.2.y, -cam.columns.2.z)
        return pos + fwd * 2.0
    }
}
