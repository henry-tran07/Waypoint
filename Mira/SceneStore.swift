import Foundation
import simd
import Combine

@MainActor
final class SceneStore: ObservableObject {
    @Published private(set) var objects: [String: ObjectRecord] = [:]
    @Published var activeTarget: (label: String, position: SIMD3<Float>)? = nil

    func upsert(label: String, position: SIMD3<Float>, confidence: Float) {
        objects[label] = ObjectRecord(
            label: label, position: position,
            lastSeen: Date(), confidence: confidence
        )
    }

    func clearTarget() { activeTarget = nil }
}
