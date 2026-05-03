# Mira-iPhone — Session Context Dump

> Snapshot of the build session. Self-contained — read this and you have everything needed to continue or hand off.

## What we're building

**Mira-iPhone** is a single iOS app for finding lost objects in a room by voice. User opens the app → ARKit + LiDAR + YOLOv8n silently scan and store object positions in 3D as the user walks around → user taps a mic button and asks "where is my bottle?" → an AR arrow drops at the bottle's last-known position and TTS speaks a direction string ("to your right, about 2 meters away").

- **Demo bar:** PRD §12 steps 1–5 pass on a LiDAR iPhone.
- **Repo:** `https://github.com/henry-tran07/Waypoint`
- **Local checkout:** `C:\Users\datct\CSProjects\henrysGithubRepos\Waypoint`
- **Specs:** `PRD.md` + `BUILD_PLAN.md` at repo root.
- **Build env:** I'm on Windows; partner has the Mac with Xcode. Dev loop = I write Swift here, you commit/push, partner pulls/builds on Mac.
- **You** = Person B (Voice/Interaction). **Partner** = Person A (Vision/Detection).

## Stack

| Concern | Choice |
|---|---|
| App shell + UI | Swift 5.9, SwiftUI |
| AR rendering | RealityKit |
| World tracking + scene mesh | ARKit (`ARWorldTrackingConfiguration` w/ `.meshWithClassification`) |
| Object detection | Vision + Core ML (YOLOv8n.mlpackage from HuggingFace `TheCluster/YOLOv8-CoreML`, AGPL-3.0) |
| Speech-to-text | `SFSpeechRecognizer` (en-US) |
| Text-to-speech | `AVSpeechSynthesizer` (en-US) |
| Storage | In-memory `[String: ObjectRecord]` on `SceneStore: ObservableObject` |
| Min target | iOS 18 (was 17 — partner bumped) |
| Build system | XcodeGen (`project.yml`) → `Mira.xcodeproj` |

## Key decisions made this session

1. **Demo target swapped from `keys` to `bottle`** — YOLOv8n's COCO 80 classes don't include "keys". `bottle`, `cup`, `book`, `remote`, `chair` are valid alternatives. PRD.md §1, §2, §6, §11 edited; demo script says "where is my bottle".
2. **Project layout is flat `Mira/*.swift`** (XcodeGen `sources: Mira`). My initial `Sources/Mira/{App,Model,Voice,Vision}/` tree was discarded after partner pushed flat layout to main first.
3. **YOLOv8n.mlpackage committed to repo** at `Mira/Models/YOLOv8n.mlpackage` (capital Y so Xcode autogenerates `class YOLOv8n` matching `DetectionService.swift`). 6.2 MB. AGPL-3.0 caveat for any commercial use.
4. **Branch policy:** Person B work goes through a feature branch (`feat/voice-ui`) and merges to `main` after the team has eyeballed it. Direct pushes to main happened a few times today to keep momentum on a 6-hour clock; rule applies to ongoing feature work.
5. **Pre-emptive contract additions to `SceneStore`** (additive, non-breaking):
   - `func find(label: String) -> ObjectRecord?` — case-insensitive lookup with whitespace + punctuation trim. Lets `QueryHandler` look up "Bottle." as `objects["bottle"]`.
   - `@Published var lastDetectedLabel: String?` — newest add, for `StatusOverlay` flash if we want.
6. **Camera transform plumbing:** `Mira/CameraReference.swift` is a single-instance bridge (`@unchecked Sendable`) so `QueryHandler` (Person B) can read the live camera Transform that Person A's ARSessionDelegate writes — without touching the frozen `SceneStore` contract.
7. **Defaults baked in:** confidence floor `< 0.5` drops in `DetectionService` (partner uses 0.4, fine); last-detection-wins per label; en-US locale; 1.5 s end-of-utterance silence; arrow = cyan cone (partner's `ArrowEntity` is shaft+tip+point-light w/ slow Y-axis spin); only test target = none yet (`MiraTests/DirectionUtilTests.swift` was skipped because `project.yml` doesn't have a test target).

## Architecture

```
ARKit Session (60fps) ── world pose, mesh, camera frames
        │
   ┌────┴────┐
   ▼         ▼
ARView    DetectionService (background queue, 2 Hz)
(RealityKit)  - YOLO via Vision/CoreML
              - Raycaster: bbox → 3D world position
              - SceneStore.upsert(label, pos, conf)
                     │
                     ▼
            ┌────────────────────┐
            │   SceneStore       │ ◀── shared contract
            │   [label → record] │
            │   activeTarget?    │
            │   lastDetectedLabel│
            └────────────────────┘
                     ▲
                     │ (read on mic-release)
            ┌────────┴────────┐
            │  QueryHandler   │ ◀── SpeechService (mic tap)
            │  noun → find    │
            │  set activeTgt  │ ──▶ TTSService (speaks dir)
            │  describeDir    │     ↑
            └─────────────────┘     │
                     │              │
                     │      reads CameraReference.shared.current
                     │      (written by ARSessionDelegate.didUpdate)
                     ▼
            ARView observes activeTarget → drops AnchorEntity
            with ArrowEntity at world position
```

### Data contract (`Mira/SceneStore.swift`, frozen)

```swift
struct ObjectRecord {
    let label: String
    var position: SIMD3<Float>     // world coordinates
    var lastSeen: Date
    var confidence: Float
}

@MainActor
final class SceneStore: ObservableObject {
    @Published private(set) var objects: [String: ObjectRecord]
    @Published var activeTarget: (label: String, position: SIMD3<Float>)?
    @Published var lastDetectedLabel: String?

    func upsert(label:position:confidence:)
    func find(label:) -> ObjectRecord?      // ← my addition (case-insensitive)
    func clearTarget()
}
```

## Repo state right now

`main` HEAD: `eada818`. Linear history:

```
eada818  hours 2-4: MicButton + StatusOverlay + QueryHandler + camera reference   (me)
ba8f121  hour 1: voice services + sync (SceneStore additions + YOLOv8n model)     (me)
f9997c3  Bump deployment target to iOS 18, fix MainActor on Coordinator.configure (partner)
a35f688  Add Person A vision pipeline + foundation scaffolding                    (partner)
a1ea101  init files
dc8c38a  Initial commit
```

Working tree: clean. Local main = origin/main. No stashes. No unpushed commits. `feat/voice-ui` branch exists locally and on origin (already merged into main).

### File-by-file status (`Mira/`)

| File | Owner | Status |
|---|---|---|
| `MiraApp.swift` | foundation (mine) | Done — `@StateObject` for SceneStore + SpeechService + TTSService, env-objected to ContentView |
| `ContentView.swift` | foundation (partner) | Done — ZStack(ARViewContainer + StatusOverlay + MicButton) |
| `Info.plist` | foundation (partner) | Done — 3 perms |
| `Mira.entitlements` | foundation (partner) | Done — speech-recognition.full-access |
| `ObjectRecord.swift` | foundation (partner) | Done — matches PRD §7 |
| `SceneStore.swift` | foundation (mine) | Done — PRD §7 contract + `find(label:)` + `lastDetectedLabel` |
| `ARViewContainer.swift` | Person A (partner) | Done — ARWorldTrackingConfig with mesh, Coordinator, Combine sink on `activeTarget`, anchor add/remove |
| `DetectionService.swift` | Person A (partner) | Done — VNCoreMLRequest, 2 Hz, conf ≥ 0.4, raycaster pipe, store.upsert |
| `Raycaster.swift` | Person A (partner) | Done — bbox → screen → 3D, fallback camera-ray @ 2m |
| `ArrowEntity.swift` | Person A (partner) | Done — cyan shaft+tip+point-light, Y-spin animation |
| `SpeechService.swift` | Person B (mine) | Done — SFSpeechRecognizer en-US, AVAudioEngine tap, 1.5s silence debounce |
| `TTSService.swift` | Person B (mine) | Done — AVSpeechSynthesizer en-US, .playback/.duckOthers, cancels in-flight |
| `MicButton.swift` | Person B (mine) | Done — DragGesture push-to-talk, dispatches QueryHandler on release |
| `StatusOverlay.swift` | Person B (mine) | Done — sorted seen-list, "Seen: (none)" empty state |
| `QueryHandler.swift` | Person B (mine) | Done — noun extraction, hit/miss branches, full TTS direction speak |
| `DirectionUtil.swift` | Person B (mine) | Done — pure fn per PRD §8, with fileprivate `simd_float4x4` extension |
| `CameraReference.swift` | bridge (mine) | Done — singleton, partner needs to write to it (see below) |
| `Models/YOLOv8n.mlpackage` | (mine) | Committed |

## Outstanding integration items (partner-side)

**Critical for the demo loop to work end-to-end:**

1. **`xcodegen generate`** on the Mac after pulling — regenerates `.xcodeproj` to pick up the 6 new/modified files (`CameraReference.swift` + 5 Voice files) and the `YOLOv8n.mlpackage` resource.
2. **One line in `ARViewContainer.Coordinator`** — implement `session(_ session: ARSession, didUpdate frame: ARFrame)` and write:
   ```swift
   CameraReference.shared.current = Transform(matrix: frame.camera.transform)
   ```
   Without this, `QueryHandler` reads an identity Transform and every direction string is "ahead".
3. **Verify `YOLOv8n` class autogeneration.** `DetectionService.swift:17` uses `YOLOv8n(configuration: ...)`. The `.mlpackage` was renamed to `YOLOv8n` (capital Y) to match. If Xcode produces a different class name, this won't compile.

## What's left in the build plan

- **Hour 5 polish (paired):** stage props (place a real bottle visibly), arrow visual sanity (color contrast, fixed-size at 1m vs 5m), tune speech 1.5s → 2s if it cuts people off, miss-path copy verification, rapid double-tap mic edge case, demo script sweep.
- **Hour 6 buffer:** record backup demo video on partner's phone while the other does live runs.

End-to-end demo verification (PRD §12, repeated for clarity):

1. Cold-launch → camera live, 3 perms granted, no crash.
2. Walk past bottle ~10s → `StatusOverlay` shows `Seen: bottle, …`.
3. Tap mic + say "where is my bottle" → console `transcribed: bottle`.
4. ~1s later: cyan cone at bottle + TTS speaks `"Your bottle is <dir>, about <n> meters away"`.
5. Walk to opposite side, ask again → arrow stays world-locked, direction now `"behind you"`.
6. Move bottle ~2m, walk back, wait 1s, ask again → new cone at new spot.
7. Ask "where is my elephant" → TTS speaks miss copy.
8. Battery + thermal sane to do it again.

Pass 1–4 = demo. Pass 5–7 = impressive. Pass 8 = can do twice.

## Useful pointers

- **PRD source of truth:** `PRD.md` — §7 contract, §8 direction spec, §9 perms, §12 verification.
- **Build plan:** `BUILD_PLAN.md` — §4 file ownership, §5 foundation steps, §7 sync protocol.
- **Active session plan:** `C:\Users\datct\.claude\plans\ultrathink-c-users-datct-csprojects-henr-humble-galaxy.md` — hour-by-hour playbook with parallel-dispatch protocol.
- **Saved feedback (persistent across sessions):** `C:\Users\datct\.claude\projects\C--Users-datct-CSProjects-henrysGithubRepos-Waypoint\memory\feedback_branch_policy.md` — branch policy rule.
- **YOLOv8 source clone:** `C:\Users\datct\CSProjects\henrysGithubRepos\YOLOv8-CoreML\` — has all variants (n/s/m/l/x); we use `yolov8n.mlpackage` only.

## Build/run quickstart (for partner on Mac)

```bash
git clone https://github.com/henry-tran07/Waypoint
cd Waypoint
brew install xcodegen           # if not installed
xcodegen generate
open Mira.xcodeproj
# In Xcode: select your dev team, plug in LiDAR iPhone, ⌘R
```

## Quick sanity questions to ask before demoing

- Is `Mira/Models/YOLOv8n.mlpackage` part of the Mira target? (Build phases → Copy Bundle Resources)
- Did Xcode autogenerate a `YOLOv8n` class? (Check the `Models/YOLOv8n.mlpackage` group in the navigator — there's an icon "Model Class".)
- Did `session(_:didUpdate:)` get the CameraReference write?
- Does asking "where is my elephant" actually trigger the miss path? (Sanity check that `QueryHandler.find(label:)` is being called.)
