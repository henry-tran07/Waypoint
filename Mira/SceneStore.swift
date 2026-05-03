import Foundation
import simd
import Combine

@MainActor
final class SceneStore: ObservableObject {
    @Published private(set) var objects: [String: ObjectRecord] = [:]
    @Published var activeTarget: (label: String, position: SIMD3<Float>)? = nil
    @Published var lastDetectedLabel: String? = nil
    @Published var lastSceneDescription: String? = nil

    func upsert(label: String, position: SIMD3<Float>, confidence: Float) {
        objects[label] = ObjectRecord(
            label: label,
            position: position,
            lastSeen: Date(),
            confidence: confidence
        )
        lastDetectedLabel = label
    }

    func find(label: String) -> ObjectRecord? {
        let key = label
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .punctuationCharacters)
        return objects[key]
    }

    func clearTarget() { activeTarget = nil }
}
