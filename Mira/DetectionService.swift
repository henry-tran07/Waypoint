import ARKit
import RealityKit
import SwiftAnthropic
import UIKit

@MainActor
final class DetectionService {
    private weak var arView: ARView?
    private let store: SceneStore
    private let service: AnthropicService
    private var loopTask: Task<Void, Never>?
    private let ciContext = CIContext()

    init(arView: ARView, store: SceneStore) {
        self.arView = arView
        self.store = store
        self.service = AnthropicServiceFactory.service(apiKey: anthropicAPIKey, betaHeaders: nil)
    }

    func start() {
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.runDetection()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func stop() { loopTask?.cancel(); loopTask = nil }

    private func runDetection() async {
        guard let arView,
              let frame = arView.session.currentFrame,
              let jpegData = captureJPEG(from: frame) else { return }

        let base64 = jpegData.base64EncodedString()
        let imageContent = MessageParameter.Message.Content.ContentObject.image(
            .init(type: .base64, mediaType: .jpeg, data: base64)
        )
        let prompt = """
        List all visible everyday objects. For each, output exactly one JSON line:
        {"label":"<name>","bbox":[x,y,w,h]}
        x,y = top-left corner, w,h = size, all normalized 0-1.
        Also output one line: SCENE: <one sentence describing the overall setting and notable objects>.
        Output only JSON lines and the SCENE line, nothing else.
        """
        let textContent = MessageParameter.Message.Content.ContentObject.text(prompt)
        let message = MessageParameter.Message(role: .user, content: .list([imageContent, textContent]))
        let params = MessageParameter(
            model: .other("claude-haiku-4-5-20251001"),
            messages: [message],
            maxTokens: 500
        )

        guard let response = try? await service.createMessage(params) else { return }

        let fullText = response.content.compactMap { item -> String? in
            if case .text(let t, _) = item { return t }
            return nil
        }.joined(separator: "\n")

        for line in fullText.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("SCENE:") {
                store.lastSceneDescription = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                continue
            }
            guard trimmed.hasPrefix("{"),
                  let data = trimmed.data(using: .utf8),
                  let obj = try? JSONDecoder().decode(Detection.self, from: data) else { continue }
            guard obj.bbox.count == 4 else { continue }
            let bbox = CGRect(x: obj.bbox[0], y: obj.bbox[1],
                              width: obj.bbox[2], height: obj.bbox[3])
            let pos = Raycaster.raycastFromTopLeft(in: frame, arView: arView, bbox: bbox)
            print("detected: \(obj.label) @ \(pos)")
            store.upsert(label: obj.label.lowercased(), position: pos, confidence: 0.9)
        }
    }

    private func captureJPEG(from frame: ARFrame) -> Data? {
        let ci = CIImage(cvPixelBuffer: frame.capturedImage).oriented(.right)
        guard let cg = ciContext.createCGImage(ci, from: ci.extent) else { return nil }
        return UIImage(cgImage: cg).jpegData(compressionQuality: 0.4)
    }

    private struct Detection: Decodable {
        let label: String
        let bbox: [Double]
    }
}
