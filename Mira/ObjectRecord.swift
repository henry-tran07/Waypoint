import Foundation
import simd

struct ObjectRecord {
    let label: String
    var position: SIMD3<Float>
    var lastSeen: Date
    var confidence: Float
}
