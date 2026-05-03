# Mira-iPhone — Parallel Build Plan

> Two-person, ~6 hour hackathon execution plan. Designed for zero merge headaches.
> Companion doc: `PRD.md` (architecture, contract, features).

---

## 1. Goal

Two people, ~6 hours, zero merge pain. Achieved by:

1. A short **foundation phase** (both at one keyboard, ~45 min) that locks the shared contract and creates empty placeholder files for every module.
2. **File-level ownership** — almost no file is touched by both people after foundation.
3. A small set of **integration sync points** at hour 3 and hour 4.5 for short merges.

---

## 2. Branch strategy

```
main
 ├── (foundation commits — both pairing)
 │
 ├──── feat/detection      ← Person A   (Track A: Vision pipeline)
 │
 └──── feat/voice-ui       ← Person B   (Track B: Interaction layer)
```

- Foundation work goes to `feat/foundation`, gets PR'd to `main`, both eyeball-review and merge. Even the foundation phase does not push directly to `main`.
- Each track is a long-lived feature branch.
- **First merge sync** at ~hour 3: each track opens a small PR back to `main`, the other reviews in 5 min, both merge. Catches contract drift early.
- **Second merge sync** at ~hour 4.5: same pattern.
- **Hour 5–6:** both work directly on `main` together for integration polish and demo prep.

---

## 3. Track assignment

Split is by **input pipeline vs. output pipeline**, not by skill. Each track gets one chunk of AR exposure so neither of you is the only one who learned the framework.

### Track A — Vision Pipeline (Person A)

> "Camera frames in → labelled positions in the dict. Always running."

- ARKit session configuration (world tracking + scene mesh)
- ARView container (`UIViewRepresentable`) + lifecycle
- **Detection starts at app launch and never stops** — no UI toggle, no on/off button. The loop kicks off as soon as `ARViewContainer` is created.
- Detection service: pull frames at 2 Hz, run YOLO on background queue
- Raycasting: bbox center → 3D world position (with camera-ray fallback)
- Drop YOLOv8n.mlpackage into project
- ARView observes `store.activeTarget` and renders the anchor + arrow entity (lives inside the ARView, so it's Track A)

### Track B — Interaction Layer (Person B)

> "User intent in → spoken guidance out."

- SwiftUI shell beyond what foundation set up (mic button, status overlay showing "Seen: bottle, cup, book")
- SpeechService: `SFSpeechRecognizer` wrapper (start/stop, deliver text)
- TTSService: `AVSpeechSynthesizer` wrapper
- QueryHandler: text → noun extraction → store lookup → set `activeTarget` + speak direction
- DirectionUtil: pure math (`describeDirection`)
- "Object not seen yet" branch with helpful TTS prompt

---

## 4. File ownership table (the conflict-prevention sheet)

| File | Owner | Notes |
|---|---|---|
| `MiraApp.swift` | **Foundation** | App entrypoint. Frozen after foundation. |
| `ContentView.swift` | **Foundation** | ZStack of `ARViewContainer` + `MicButton` overlay. Frozen after foundation. |
| `Info.plist` | **Foundation** | Permissions. Frozen after foundation. |
| `SceneStore.swift` | **Foundation** | The contract. Frozen after foundation. |
| `ObjectRecord.swift` | **Foundation** | The struct. Frozen after foundation. |
| `ARViewContainer.swift` | **Track A** | Owns ARView, session config, Combine subscription to `activeTarget`. |
| `DetectionService.swift` | **Track A** | YOLO loop on background queue. |
| `Raycaster.swift` | **Track A** | Bbox→3D helpers, fallback logic. |
| `ArrowEntity.swift` | **Track A** | Builds the glowing arrow `Entity` (RealityKit). |
| `Models/YOLOv8n.mlpackage` | **Track A** | Model asset. |
| `MicButton.swift` | **Track B** | SwiftUI mic UI + tap handler. |
| `StatusOverlay.swift` | **Track B** | "Seen: ..." list view. |
| `SpeechService.swift` | **Track B** | `SFSpeechRecognizer` wrapper. |
| `TTSService.swift` | **Track B** | `AVSpeechSynthesizer` wrapper. |
| `QueryHandler.swift` | **Track B** | Voice text → store lookup → `activeTarget` + TTS. |
| `DirectionUtil.swift` | **Track B** | `describeDirection` pure fn. |

**Only `ContentView.swift` is structurally shared, and it's frozen after foundation.** Everything else has exactly one owner. Merge conflicts should be functionally impossible.

---

## 5. Foundation phase (both pairing, ~45 min)

Do this together at one screen. End state: `main` has a buildable skeleton both of you can pull, a frozen `SceneStore`, and stub files for everyone.

1. **Create Xcode project** — App template, SwiftUI lifecycle, Swift, iOS 17+. Bundle ID like `com.<you>.mira`.
2. **Add permissions to `Info.plist`** — all three keys (PRD §9).
3. **Initialize git** — `git init`, push to a fresh GitHub repo, both clone.
4. **Create file scaffolding** — empty `.swift` files matching the table in §4. Each file just contains its `import` lines and an empty `struct`/`class`/`func` stub. This way Track A creating `ArrowEntity.swift` is not a "new file" — the file already exists, they're just filling it in.
5. **Write `ObjectRecord.swift` and `SceneStore.swift`** — exactly as in PRD §7. Frozen after this point. If either of you needs to change this, both pause and decide together.
6. **Write `MiraApp.swift`** — instantiates `SceneStore` as `@StateObject`, passes it down via `.environmentObject(store)` on `ContentView`.
7. **Write `ContentView.swift`** — the ZStack template:
   ```swift
   struct ContentView: View {
       @EnvironmentObject var store: SceneStore
       var body: some View {
           ZStack {
               ARViewContainer().ignoresSafeArea()
               VStack {
                   StatusOverlay().padding(.top, 50)
                   Spacer()
                   MicButton().padding(.bottom, 50)
               }
           }
       }
   }
   ```
   Frozen after this.
8. **Run on both phones** — confirm camera permission dialog fires, blank ARView appears (Track A's stub returns an empty `ARView`).
9. **Commit + push to `main`.**
10. **Each person creates their feature branch:** `git checkout -b feat/detection` (A) / `git checkout -b feat/voice-ui` (B).

After step 10, both diverge.

---

## 6. Hour-by-hour timeline

| Hour | Person A (Vision) | Person B (Interaction) |
|---|---|---|
| 0 | **PAIR** — foundation phase (§5) | **PAIR** — foundation phase (§5) |
| 1 | ARKit config in `ARViewContainer.swift`: world tracking + LiDAR mesh; verify on device | `SpeechService.swift` + `TTSService.swift` skeletons; verify mic permission, do a hello-world transcribe + speak |
| 2 | Drop in YOLOv8n.mlpackage; `DetectionService.swift` runs on bg queue; print labels to console | `MicButton.swift` UI + tap → SpeechService → log transcription; `DirectionUtil.swift` w/ unit-style sanity check |
| 3 | Raycasting in `Raycaster.swift`; pipe detections → `store.upsert`; verify list of seen labels | `StatusOverlay.swift` reads `store.objects.keys`; `QueryHandler.swift` skeleton (text→noun→lookup→set activeTarget) |
| — | **SYNC #1** — both PR to `main`, 5-min review each, merge | **SYNC #1** — both PR to `main`, 5-min review each, merge |
| 4 | ARView observes `activeTarget`; on change, add `ARAnchor` + `ArrowEntity` | QueryHandler wires TTS: speak direction on hit, "haven't seen it" on miss |
| — | **SYNC #2** — short PRs, merge | **SYNC #2** — short PRs, merge |
| 5 | **PAIR on `main`** — full demo flow: scan room → ask → arrow appears → walk to it. Polish arrow visual (color, glow, scale). | **PAIR on `main`** — tune speech recognition timeouts, tighten direction string, handle "what about X" follow-ups if time |
| 6 | **PAIR** — record a backup demo video on one phone while the other does a live run. Buffer for breakage. | **PAIR** — same |

---

## 7. Sync point protocol (designed to take 5 minutes)

When you hit a sync point:

1. Each pushes their feature branch.
2. Each opens a PR to `main` with a 1-line description ("detection loop wired up", "mic button + query handler").
3. Other person opens it, eyeballs the diff, comments only on contract drift (did anyone touch a Foundation file?).
4. Whoever was the original Foundation-file gatekeeper merges first (just convention; pick at hour 0). Other person rebases their branch onto new `main` and merges next.
5. Both pull `main` and continue.

If a sync point exposes a contract problem (e.g. you need a new field on `ObjectRecord`), **both pause** and amend the contract together on `main`, then both rebase. This should be rare if the PRD is right.

---

## 8. Things to NOT do (will create merge pain)

- Do not edit a file outside your column in §4. If you need something there, ask the owner.
- Do not modify `SceneStore.swift` mid-stream alone. Contract changes are joint.
- Do not let either feature branch live longer than ~2 hours unmerged.
- Do not wait until hour 5 to integrate. The sync points exist to fail fast.
- Do not develop in the simulator past hour 1 — you both have devices, use them.

---

## 9. Pre-flight checklist (do this tonight, not tomorrow morning)

- [ ] Both have Xcode 15+ installed and updated
- [ ] Both have signed into Apple Developer account on Xcode
- [ ] Both phones (LiDAR-equipped iPhone Pro/Pro Max) are on a recent iOS, in developer mode, trusted by your Mac
- [ ] Both can build & run the default Xcode "Augmented Reality App" template on your phone
- [ ] Download YOLOv8n.mlpackage in advance (Ultralytics or HuggingFace) — don't fight Wi-Fi at the venue
- [ ] Decide on the GitHub repo name + create the empty repo
- [ ] Decide who is Person A (Vision) and who is Person B (Interaction)
- [ ] Pick the Foundation-file gatekeeper (the one who merges first at sync points)
