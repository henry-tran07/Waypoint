# Mira-iPhone — Product Requirements & Architecture

> Shared source-of-truth for the build. Read this before writing any code.
> Companion doc: `BUILD_PLAN.md` (split-work and merge strategy).

---

## 1. Product summary

**Mira-iPhone** is a single iOS app that helps a user find physical objects in their environment by voice. The user opens the app, walks around their room while Mira passively scans, then asks "where is my bottle?" — Mira drops an AR arrow at the bottle's last-known position and says "to your left, about 2 meters away."

Demo moment: tap the mic, ask, walk toward a glowing arrow that points at the real object. That's the entire pitch.

### User flow — always-on after launch

The product is **always-on while open**. There is no "start scan" / "stop scan" button. There is no indexing phase the user waits through. Detection runs continuously the entire time the app is in the foreground; the mic button is the only intentional user interaction.

1. **Launch.** User opens Mira → camera + ARKit + LiDAR + YOLO detection start immediately. No setup screen.
2. **Initial scan (~30s).** User walks around the room with the phone held up. Mira silently builds the 3D mesh and populates `SceneStore` with everything YOLO recognizes. Status overlay shows the growing list ("Seen: bottle, cup, book…") so the user has feedback that something's happening.
3. **Phone stays running.** User can prop it on a desk, hold it casually, or carry it around. As long as the camera sees the room, detection keeps refreshing positions in the background. There's no idle state.
4. **Query anytime.** User taps the mic and asks "where are my X?" — Mira responds with arrow + voice. They can ask again, ask about other things, ask about the same thing after they've moved — all without re-scanning.
5. **Passive refresh.** If an object moves and Mira sees it again, the dict updates automatically (newer overwrites older). No user action needed.

**UX implication for the build:** the AR session, detection loop, and store are all created at app launch and never paused. No play/stop UI. No mode switching. The mic button is literally the only button.

**Known tradeoff (acceptable for demo):** always-on camera + Core ML inference will warm the phone up and drain battery faster than a normal app. Fine for a 5-minute demo. Not a hackathon concern.

---

## 2. Scope (what's in)

Three capabilities. Nothing else:

1. **Scene understanding** — ARKit world tracking + LiDAR scene reconstruction builds a live 3D mesh as the user walks around.
2. **Object detection with 3D coordinates** — YOLOv8n (Core ML) runs on captured frames at 2 Hz; each detection is raycast into the scene mesh and stored with a real-world `SIMD3<Float>` position.
3. **Live voice query** — user taps a mic button, speaks ("where is my bottle"), Mira matches against the in-memory dict, drops an AR anchor with a glowing arrow at the match position, and speaks a direction string.

---

## 3. Scope (what's out — explicit non-goals)

- No backend, no accounts, no networking
- No persistence between sessions (in-memory dict only)
- No caregiver dashboard / second app surface
- No medical Q&A / LLM agent (keyword match against the dict is enough)
- No fall detection
- No custom-trained model — pretrained YOLOv8n COCO classes only

---

## 4. Stack

| Concern | Choice |
|---|---|
| App shell + UI | Swift, SwiftUI |
| AR rendering | RealityKit |
| World tracking + scene mesh | ARKit (`ARWorldTrackingConfiguration` w/ `.meshWithClassification`) |
| Object detection | Vision framework + Core ML (YOLOv8n `.mlpackage`) |
| Speech-to-text | Speech (`SFSpeechRecognizer`) |
| Text-to-speech | AVFoundation (`AVSpeechSynthesizer`) |
| Storage | In-memory `[String: ObjectRecord]` on an `ObservableObject` |
| Persistence | None |
| Min target | iOS 17, iPhone Pro / Pro Max (LiDAR required) |

---

## 5. Architecture (one-screen view)

```
┌──────────────────────────────────────────────────────────────┐
│                       iPhone (single app)                    │
│                                                              │
│   ARKit Session (60fps) ── world pose, mesh, camera frames   │
│             │                                                │
│      ┌──────┴───────┐                                        │
│      ▼              ▼                                        │
│   ARView         Detection Loop  (background, 2 Hz)          │
│   (RealityKit)   ─ snapshot frame                            │
│   renders arrow  ─ YOLO via Core ML                          │
│   on anchor      ─ raycast bbox center → 3D                  │
│        ▲         ─ SceneStore.upsert(label, pos, conf)       │
│        │                  │                                  │
│        │                  ▼                                  │
│        │         ┌───────────────────────┐                   │
│        │         │   SceneStore          │  ◀── shared       │
│        │         │   [label → record]    │      contract     │
│        │         │   activeTarget?       │                   │
│        │         └───────────────────────┘                   │
│        │                  ▲                                  │
│        │                  │ (read on query)                  │
│        │         ┌────────┴────────┐                         │
│        │         │  QueryHandler   │ ◀── Speech (mic tap)   │
│        └─────────│  match label    │                         │
│      sets        │  set activeTgt  │ ──▶ TTS speaks dir.    │
│      activeTarget│  compute dir.   │                         │
│                  └─────────────────┘                         │
└──────────────────────────────────────────────────────────────┘
```

---

## 6. The two loops

### Loop A — Detection (always-on from app launch, 2 Hz, background queue)

This loop starts when `ARViewContainer` initializes and never stops while the app is in the foreground. There is no enable/disable toggle — Mira is detecting from the moment the camera turns on until the user backgrounds the app.

```
every 0.5s:
  frame = arView.session.currentFrame
  detections = yolo.predict(frame.capturedImage)
  for d in detections:
      hit = arView.raycast(from: d.bbox.center, .estimatedPlane, .any)
      pos = hit?.worldTransform.position
            ?? cameraRay(at: 2.0)        // fallback when no mesh hit
      store.upsert(d.label, pos, d.confidence)
```

### Loop B — Query (triggered by user mic tap)

```
mic tap
  → SFSpeechRecognizer transcribes
  → extract noun ("bottle")
  → record = store.objects["bottle"]
  → if record:
        store.activeTarget = (label, record.position)
        dir = describeDirection(camera, record.position)
        tts.speak("Your bottle is \(dir)")
     else:
        tts.speak("I haven't seen your bottle yet — try walking around.")
```

ARView observes `activeTarget` via Combine. When it flips non-nil, ARView adds an `ARAnchor` at the position and attaches a glowing arrow entity. Newer detections overwriting older entries means a moved object updates next time it's seen — passive scene refresh, no extra logic.

---

## 7. Shared data contract (frozen after foundation phase)

```swift
struct ObjectRecord {
    let label: String
    var position: SIMD3<Float>     // world coordinates
    var lastSeen: Date
    var confidence: Float
}

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
```

This is the **only** type both tracks share.

- **Track A (Detection)** writes to `objects` via `upsert`.
- **Track B (Voice/UI)** reads `objects` and writes `activeTarget`.
- **ARView** observes `activeTarget` and renders the anchor.

Nothing else crosses the boundary.

---

## 8. Direction string spec

```swift
func describeDirection(from camera: Transform, to target: SIMD3<Float>) -> String {
    let to = target - camera.translation
    let fwd = camera.matrix.forward      // -Z in ARKit
    let right = camera.matrix.right      // +X
    let fDot = dot(to, fwd), rDot = dot(to, right)
    let dist = length(to)
    let lr = rDot >  0.5 ? "to your right"
           : rDot < -0.5 ? "to your left" : ""
    let fb = fDot >  0.5 ? "ahead"
           : fDot < -0.5 ? "behind you"  : ""
    return "\(fb) \(lr), about \(Int(dist.rounded())) meters away"
}
```

Pure function. Lives in `DirectionUtil.swift`. Owned by Track B.

---

## 9. Permissions (Info.plist — set in foundation, never touch again)

| Key | Value |
|---|---|
| `NSCameraUsageDescription` | "Mira uses the camera to see the room around you." |
| `NSMicrophoneUsageDescription` | "Mira uses the mic to hear what you're looking for." |
| `NSSpeechRecognitionUsageDescription` | "Mira transcribes what you say to find objects." |

---

## 10. Known risks & mitigations

| Risk | Mitigation |
|---|---|
| Permissions surprise mid-debug at hour 4 | Add all three to Info.plist in foundation phase, hour 0 |
| YOLO blocks main thread → AR freezes | Detection loop runs on a dedicated background `DispatchQueue` |
| Raycast returns nil over empty space | Fallback: project camera ray to fixed 2m and use that |
| Speech recognition doesn't run on simulator | Both teammates test on real device from minute one |
| Core ML model is the wrong format | Use YOLOv8n `.mlpackage` (not ONNX). Drop into Xcode → autogenerated Swift class |
| AR anchor entity placed before mesh exists | OK — anchor still works; entity just floats. Acceptable for demo. |
| Both push to same file → conflict | File-ownership table in `BUILD_PLAN.md` §4 — only `ContentView.swift` is shared, and it's frozen after foundation |

---

## 11. Demo script (the bar to clear)

> "This is Mira. I open the app, the camera starts, I walk around my desk for 30 seconds — the app is silently building a 3D map and noting where everything is. Now I tap the mic and say 'where is my bottle?' [arrow appears, voice speaks] 'Your bottle is to your right, about 1 meter away.' I follow the arrow. There it is."

If your build at hour 5 can do exactly that paragraph, you're done.

---

## 12. End-to-end verification

Run on a real iPhone (LiDAR required). Verify in this order:

1. **App launches, camera feed visible** — foundation done correctly.
2. **Console prints `detected: bottle` etc. while pointing at objects** — Track A detection loop works.
3. **`StatusOverlay` shows a growing list of seen labels as you walk around** — Track A raycasting + SceneStore writes + Track B overlay reads work; contract is healthy.
4. **Tap mic, say "where is my bottle"; console logs the transcription** — Track B speech wiring works.
5. **After step 4, an anchor appears at the bottle's position; TTS speaks "your bottle is …"** — full loop closed.
6. **Walk to the other side of the room without asking again — arrow stays anchored to the bottle in 3D space, direction is now "behind you"** — proves the anchor is in world coords, not screen coords.
7. **Move the bottle, walk back into view — wait ~1s — ask again — new anchor appears at new spot** — proves the upsert/refresh story works.

If steps 1–5 work, you have a demo. Steps 6–7 are the "actually impressive" wins.
