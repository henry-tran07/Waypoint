import Foundation

@MainActor
final class QueryHandler {
    let store: SceneStore
    let tts: TTSService

    init(store: SceneStore, tts: TTSService) {
        self.store = store
        self.tts = tts
    }

    func handle(transcript: String) {
        let noun = extractNoun(from: transcript)
        guard !noun.isEmpty else { return }

        if let record = store.find(label: noun) {
            store.activeTarget = (record.label, record.position)
            let direction = DirectionUtil.describeDirection(
                from: CameraReference.shared.current,
                to: record.position
            )
            tts.speak("Your \(record.label) is \(direction)")
        } else {
            store.clearTarget()
            tts.speak("I haven't seen your \(noun) yet — try walking around.")
        }
    }

    private func extractNoun(from transcript: String) -> String {
        let cleaned = transcript
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .punctuationCharacters)
        return cleaned.split(separator: " ").last.map(String.init) ?? ""
    }
}
