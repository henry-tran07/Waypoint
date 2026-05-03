import Foundation
import AVFoundation
import Combine
import os.log

// Gemini 2.5 Multimodal Live client.
// Endpoint: wss://generativelanguage.googleapis.com/ws/.../BidiGenerateContent?key=KEY
// Audio in: 16 kHz signed-int16 mono PCM, base64 inside realtimeInput.audio.
// Audio out: 24 kHz signed-int16 mono PCM, base64 inside serverContent.modelTurn.parts[].inlineData.
// Tools dispatched via toolCall.functionCalls[]; respond with toolResponse.functionResponses[]
// echoing the call id. Server-side VAD is on by default.

@MainActor
final class GeminiLiveService: ObservableObject {

    enum Status: Equatable {
        case disconnected
        case connecting
        case live
        case error(String)
    }

    @Published private(set) var status: Status = .disconnected
    @Published private(set) var userTranscript: String = ""
    @Published private(set) var miraTranscript: String = ""
    @Published private(set) var inputLevel: Float = 0

    private let apiKey: String
    private let store: SceneStore
    private let logger = Logger(subsystem: "com.evacab.mira", category: "GeminiLive")

    private static let model = "models/gemini-2.5-flash-native-audio-preview-12-2025"
    private static let systemInstruction = """
    You are Mira, a concise spatial-vision assistant. You can see what objects are \
    in the user's room via tools. When asked to find something, call find_object \
    with the label; then announce the direction and distance from the result. \
    Keep replies short — one sentence is ideal. If asked what you see, call \
    list_seen_objects or describe_scene.
    """

    // Networking
    private let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()
    private let sender = WSSender()
    private var receiveLoopTask: Task<Void, Never>?

    // Audio
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var inputConverter: AVAudioConverter?
    private nonisolated(unsafe) let inputTargetFormat: AVAudioFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16_000,
        channels: 1,
        interleaved: true
    )!
    private nonisolated(unsafe) let outputFormat: AVAudioFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 24_000,
        channels: 1,
        interleaved: true
    )!

    init(apiKey: String, store: SceneStore) {
        self.apiKey = apiKey
        self.store = store
    }

    // MARK: - Public

    func start() {
        guard case .disconnected = status else { return }
        status = .connecting
        do {
            try configureAudioSession()
            try setupAudioEngine()
            openWebSocket()
        } catch {
            logger.error("start failed: \(String(describing: error))")
            status = .error("\(error)")
            teardownAudio()
        }
    }

    func stop() {
        receiveLoopTask?.cancel()
        receiveLoopTask = nil
        sender.close()
        teardownAudio()
        userTranscript = ""
        miraTranscript = ""
        inputLevel = 0
        if status != .disconnected {
            status = .disconnected
        }
    }

    // MARK: - Audio session

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP]
        )
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Audio engine

    private func setupAudioEngine() throws {
        let inputNode = engine.inputNode
        let nativeFormat = inputNode.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: nativeFormat, to: inputTargetFormat) else {
            throw GeminiLiveError.audioConverterFailed
        }
        inputConverter = converter

        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: outputFormat)

        let target = inputTargetFormat
        let convCapture = converter
        let senderCapture = sender

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nativeFormat) { [weak self] buffer, _ in
            guard let out = GeminiLiveService.convert(buffer: buffer, converter: convCapture, targetFormat: target),
                  out.frameLength > 0 else { return }
            let lvl = GeminiLiveService.computeLevel(buffer: out)
            Task { @MainActor in self?.inputLevel = lvl }
            let bytes = Int(out.frameLength) * MemoryLayout<Int16>.size
            guard let ptr = out.int16ChannelData?[0] else { return }
            let data = Data(bytes: ptr, count: bytes)
            senderCapture.sendAudioChunk(data.base64EncodedString())
        }

        engine.prepare()
        try engine.start()
        playerNode.play()
    }

    private func teardownAudio() {
        if engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            playerNode.stop()
            engine.stop()
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        inputConverter = nil
    }

    // MARK: - WebSocket

    private func openWebSocket() {
        var components = URLComponents(string: "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent")!
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components.url else {
            status = .error("Bad WS URL")
            return
        }
        let task = urlSession.webSocketTask(with: url)
        task.maximumMessageSize = 16 * 1024 * 1024
        sender.setTask(task)
        task.resume()
        sendSetupMessage()
        receiveLoopTask = Task { [weak self] in
            await self?.runReceiveLoop()
        }
    }

    private func sendSetupMessage() {
        let setup: [String: Any] = [
            "setup": [
                "model": Self.model,
                "generationConfig": [
                    "responseModalities": ["AUDIO"],
                    "speechConfig": [
                        "voiceConfig": ["prebuiltVoiceConfig": ["voiceName": "Aoede"]],
                        "languageCode": "en-US"
                    ],
                    "temperature": 0.7
                ],
                "systemInstruction": [
                    "parts": [["text": Self.systemInstruction]]
                ],
                "tools": [
                    [
                        "functionDeclarations": [
                            Self.toolDecl(name: "list_seen_objects",
                                          desc: "Returns the list of object labels Mira has seen in the user's room.",
                                          props: [:],
                                          required: []),
                            Self.toolDecl(name: "find_object",
                                          desc: "Locate a labeled object in the user's room and drop an AR arrow at its position. Returns direction and distance.",
                                          props: ["label": ["type": "STRING", "description": "Object class to find, e.g. 'bottle'."]],
                                          required: ["label"]),
                            Self.toolDecl(name: "clear_target",
                                          desc: "Remove the AR arrow from the scene.",
                                          props: [:],
                                          required: []),
                            Self.toolDecl(name: "describe_scene",
                                          desc: "Returns Mira's most recent multi-object scene description plus the seen list.",
                                          props: [:],
                                          required: [])
                        ]
                    ]
                ],
                "inputAudioTranscription": [:],
                "outputAudioTranscription": [:],
                "realtimeInputConfig": [
                    "automaticActivityDetection": [
                        "disabled": false,
                        "startOfSpeechSensitivity": "START_SENSITIVITY_HIGH",
                        "endOfSpeechSensitivity": "END_SENSITIVITY_HIGH",
                        "silenceDurationMs": 800
                    ]
                ]
            ]
        ]
        sender.sendJSON(setup)
    }

    private static func toolDecl(name: String, desc: String, props: [String: [String: String]], required: [String]) -> [String: Any] {
        var schema: [String: Any] = ["type": "OBJECT"]
        if !props.isEmpty { schema["properties"] = props }
        if !required.isEmpty { schema["required"] = required }
        return [
            "name": name,
            "description": desc,
            "parameters": schema
        ]
    }

    // MARK: - Receive loop

    private func runReceiveLoop() async {
        while !Task.isCancelled, let task = sender.task, task.state == .running {
            do {
                let message = try await task.receive()
                await handleIncoming(message)
            } catch {
                logger.error("receive failed: \(String(describing: error))")
                await MainActor.run { [weak self] in
                    if let self, self.status != .disconnected {
                        self.status = .error("Connection lost")
                    }
                }
                break
            }
        }
    }

    private func handleIncoming(_ message: URLSessionWebSocketTask.Message) async {
        let data: Data
        switch message {
        case .string(let s):
            guard let d = s.data(using: .utf8) else { return }
            data = d
        case .data(let d):
            data = d
        @unknown default:
            return
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        if obj["setupComplete"] != nil {
            status = .live
            return
        }
        if let serverContent = obj["serverContent"] as? [String: Any] {
            handleServerContent(serverContent)
        }
        if let toolCall = obj["toolCall"] as? [String: Any] {
            handleToolCall(toolCall)
        }
        if let _ = obj["goAway"] as? [String: Any] {
            // 10-min connection cap warning. For hackathon: stop and let user re-tap.
            logger.notice("goAway received; stopping")
            stop()
        }
    }

    private func handleServerContent(_ content: [String: Any]) {
        if let interrupted = content["interrupted"] as? Bool, interrupted {
            playerNode.stop()
            playerNode.play()
        }
        if let inputTr = content["inputTranscription"] as? [String: Any],
           let text = inputTr["text"] as? String {
            userTranscript = text
        }
        if let outputTr = content["outputTranscription"] as? [String: Any],
           let text = outputTr["text"] as? String {
            miraTranscript = (miraTranscript.isEmpty ? "" : miraTranscript) + text
        }
        if let modelTurn = content["modelTurn"] as? [String: Any],
           let parts = modelTurn["parts"] as? [[String: Any]] {
            for part in parts {
                if let inline = part["inlineData"] as? [String: Any],
                   let b64 = inline["data"] as? String,
                   let raw = Data(base64Encoded: b64) {
                    schedulePlayback(int16PCM: raw)
                }
            }
        }
        if let turnComplete = content["turnComplete"] as? Bool, turnComplete {
            // Reset transcript accumulator on next turn.
            // Leave miraTranscript visible for the chat strip's fade window.
        }
    }

    private func schedulePlayback(int16PCM: Data) {
        let frameCount = AVAudioFrameCount(int16PCM.count / MemoryLayout<Int16>.size)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount
        int16PCM.withUnsafeBytes { raw in
            guard let src = raw.baseAddress?.assumingMemoryBound(to: Int16.self),
                  let dst = buffer.int16ChannelData?[0] else { return }
            memcpy(dst, src, int16PCM.count)
        }
        playerNode.scheduleBuffer(buffer, completionCallbackType: .dataConsumed) { _ in }
    }

    // MARK: - Tools

    private func handleToolCall(_ payload: [String: Any]) {
        guard let calls = payload["functionCalls"] as? [[String: Any]] else { return }
        var responses: [[String: Any]] = []
        for call in calls {
            guard let id = call["id"] as? String,
                  let name = call["name"] as? String else { continue }
            let args = call["args"] as? [String: Any] ?? [:]
            let result = dispatchTool(name: name, args: args)
            responses.append([
                "id": id,
                "name": name,
                "response": ["result": result]
            ])
        }
        guard !responses.isEmpty else { return }
        sender.sendJSON(["toolResponse": ["functionResponses": responses]])
    }

    private func dispatchTool(name: String, args: [String: Any]) -> [String: Any] {
        switch name {
        case "list_seen_objects":
            return ["labels": IntentTools.listSeenObjects(store: store).labels]
        case "find_object":
            let label = (args["label"] as? String) ?? ""
            let r = IntentTools.findObject(label: label, store: store)
            return [
                "found": r.found,
                "label": r.label as Any,
                "direction": r.direction as Any,
                "distanceMeters": r.distanceMeters as Any
            ]
        case "clear_target":
            _ = IntentTools.clearTarget(store: store)
            return ["cleared": true]
        case "describe_scene":
            let r = IntentTools.describeScene(store: store)
            return [
                "description": r.description as Any,
                "seen": r.seen
            ]
        default:
            return ["error": "unknown tool: \(name)"]
        }
    }

    // MARK: - Audio helpers

    private nonisolated static func convert(buffer: AVAudioPCMBuffer,
                                            converter: AVAudioConverter,
                                            targetFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outCapacity) else { return nil }
        var error: NSError?
        var consumed = false
        let convStatus = converter.convert(to: outBuffer, error: &error) { _, inputStatus in
            if consumed { inputStatus.pointee = .noDataNow; return nil }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard convStatus != .error, error == nil else { return nil }
        return outBuffer
    }

    private nonisolated static func computeLevel(buffer: AVAudioPCMBuffer) -> Float {
        guard let ptr = buffer.int16ChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sumSq: Float = 0
        for i in 0..<count {
            let v = Float(ptr[i]) / 32768.0
            sumSq += v * v
        }
        let rms = (sumSq / Float(count)).squareRoot()
        return min(1.0, rms * 8)
    }
}

private enum GeminiLiveError: Error {
    case audioConverterFailed
}

// Owns the WebSocket task and serializes outbound sends off the audio thread.
// Sendable: state is mutated only inside the serial queue.
private final class WSSender: @unchecked Sendable {
    private let queue = DispatchQueue(label: "mira.gemini.ws.send")
    private var _task: URLSessionWebSocketTask?

    var task: URLSessionWebSocketTask? {
        queue.sync { _task }
    }

    func setTask(_ task: URLSessionWebSocketTask?) {
        queue.async { self._task = task }
    }

    func close() {
        queue.async {
            self._task?.cancel(with: .goingAway, reason: nil)
            self._task = nil
        }
    }

    func sendJSON(_ obj: [String: Any]) {
        queue.async {
            guard let task = self._task else { return }
            guard let data = try? JSONSerialization.data(withJSONObject: obj),
                  let str = String(data: data, encoding: .utf8) else { return }
            task.send(.string(str)) { _ in }
        }
    }

    func sendAudioChunk(_ base64: String) {
        queue.async {
            guard let task = self._task else { return }
            let json = "{\"realtimeInput\":{\"audio\":{\"mimeType\":\"audio/pcm;rate=16000\",\"data\":\"\(base64)\"}}}"
            task.send(.string(json)) { _ in }
        }
    }
}
