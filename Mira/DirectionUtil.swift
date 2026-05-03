import Foundation
import simd
import RealityKit

fileprivate extension simd_float4x4 {
    var forward: SIMD3<Float> {
        -SIMD3<Float>(columns.2.x, columns.2.y, columns.2.z)
    }
    var right: SIMD3<Float> {
        SIMD3<Float>(columns.0.x, columns.0.y, columns.0.z)
    }
}

enum DirectionUtil {
    static func describeDirection(from camera: Transform, to target: SIMD3<Float>) -> String {
        let to = target - camera.translation
        let fwd = camera.matrix.forward
        let right = camera.matrix.right
        let fDot = simd.dot(to, fwd)
        let rDot = simd.dot(to, right)
        let dist = simd.length(to)
        let lr = rDot >  0.5 ? "to your right"
               : rDot < -0.5 ? "to your left" : ""
        let fb = fDot >  0.5 ? "ahead"
               : fDot < -0.5 ? "behind you"  : ""
        let parts = [fb, lr].filter { !$0.isEmpty }
        let dirStr = parts.isEmpty ? "near you" : parts.joined(separator: " ")
        return "\(dirStr), about \(Int(dist.rounded())) meters away"
    }
}
