import RealityKit
import UIKit

enum ArrowEntity {
    static func make() -> Entity {
        let root = Entity()

        let shaftMesh = MeshResource.generateCylinder(height: 0.08, radius: 0.012)
        let shaft = ModelEntity(mesh: shaftMesh, materials: [UnlitMaterial(color: .cyan)])
        shaft.position = [0, 0, 0]
        root.addChild(shaft)

        // cone center = shaft top (0.04) + half-cone height (0.025) = 0.065
        let tipMesh = MeshResource.generateCone(height: 0.05, radius: 0.025)
        let tip = ModelEntity(mesh: tipMesh, materials: [UnlitMaterial(color: .cyan)])
        tip.position = [0, 0.065, 0]
        root.addChild(tip)

        root.components.set(PointLightComponent(color: .cyan, intensity: 200, attenuationRadius: 0.5))

        // Float 15 cm above the detected surface
        root.position = [0, 0.15, 0]

        // Slow Y-axis spin
        var spinTransform = root.transform
        spinTransform.rotation = simd_quatf(angle: .pi * 2, axis: [0, 1, 0])
        if let anim = try? AnimationResource.generate(with: FromToByAnimation<Transform>(
            to: spinTransform,
            duration: 3.0,
            timing: .linear,
            isAdditive: false,
            bindTarget: .transform,
            repeatMode: .repeat
        )) {
            root.playAnimation(anim)
        }

        return root
    }
}
