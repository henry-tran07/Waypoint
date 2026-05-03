import RealityKit

// Single-writer (Person A's ARSessionDelegate, ~60 Hz) / multi-reader (QueryHandler on main).
// Race window is microseconds; torn reads manifest as a one-frame stale direction. Acceptable.
final class CameraReference: @unchecked Sendable {
    static let shared = CameraReference()
    var current: Transform = Transform()
    private init() {}
}
