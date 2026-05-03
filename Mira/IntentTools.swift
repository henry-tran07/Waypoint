import Foundation
import simd

struct ListSeenObjectsResult: Codable {
    let labels: [String]
}

struct FindObjectResult: Codable {
    let found: Bool
    let label: String?
    let direction: String?
    let distanceMeters: Double?
}

struct ClearTargetResult: Codable {
    let cleared: Bool
}

struct DescribeSceneResult: Codable {
    let description: String?
    let seen: [String]
}

@MainActor
enum IntentTools {
    static func listSeenObjects(store: SceneStore) -> ListSeenObjectsResult {
        ListSeenObjectsResult(labels: store.objects.keys.sorted())
    }

    static func findObject(label: String, store: SceneStore) -> FindObjectResult {
        guard let record = store.find(label: label) else {
            return FindObjectResult(found: false, label: nil, direction: nil, distanceMeters: nil)
        }
        store.activeTarget = (record.label, record.position)
        let camera = CameraReference.shared.current
        let direction = DirectionUtil.describeDirection(from: camera, to: record.position)
        let dist = simd.length(record.position - camera.translation)
        return FindObjectResult(
            found: true,
            label: record.label,
            direction: direction,
            distanceMeters: Double(dist)
        )
    }

    static func clearTarget(store: SceneStore) -> ClearTargetResult {
        store.clearTarget()
        return ClearTargetResult(cleared: true)
    }

    static func describeScene(store: SceneStore) -> DescribeSceneResult {
        DescribeSceneResult(
            description: store.lastSceneDescription,
            seen: store.objects.keys.sorted()
        )
    }
}
