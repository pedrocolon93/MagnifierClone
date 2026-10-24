# Magnifier Clone v1 (Zoom + Freeze + Ask) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An iPhone magnifier with working zoom, freeze/release, and an Ask feature that answers one voice-or-typed question about the visible part of the frozen frame using Foundation Models (on-device → consented Private Cloud Compute → Vision fallback).

**Architecture:** A single `@Observable` `AppModel` owns a pure state machine (`Phase`) and talks to four services through protocols (`FrameSource`, `AskServicing`, `SpeechServicing`, `WaitingFeedbackPlaying`) so all flow logic is unit-tested with fakes. Pure helpers (`ZoomMapping`, `FrameCropper.visibleRect`, `AppSettings`, availability mapping) are unit-tested; hardware-bound services (camera, speech, model, haptics) are verified on device in the final task.

**Tech Stack:** Swift 6.4 / Xcode 27.1, SwiftUI, AVFoundation, Core Image, FoundationModels, Vision, Speech (`SpeechAnalyzer`/`SpeechTranscriber`), Core Haptics, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-23-magnifier-ask-design.md` (read it; reference screenshots in `docs/superpowers/specs/assets/`).

## Global Constraints

- iOS 27.0 deployment target; iPhone only (`TARGETED_DEVICE_FAMILY = 1`), portrait only.
- Project defaults: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, approachable concurrency. Mark non-UI work `nonisolated`/`@concurrent` explicitly.
- `MyApp/` and `MagnifierCloneTests/` are file-system-synchronized groups: new files placed in those folders are picked up automatically — never add per-file entries to `project.pbxproj`.
- Before every `xcodebuild`: `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (active dir is CommandLineTools).
- Test command (referred to below as **TEST**): `xcodebuild test -project MagnifierClone.xcodeproj -scheme MagnifierClone -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -quiet` (append `-only-testing:MagnifierCloneTests/<Suite>` to narrow).
- One question per freeze; a new `LanguageModelSession` per question.
- `OCRTool` is always in the session's tools.
- Never escalate to Private Cloud Compute without the user tapping **Send** on the consent prompt, every time.
- The model only sees the visible region: hardware zoom already applied, preview aspect-fill crop removed, area under the control panel excluded.
- Waiting feedback: sound `MyApp/Resources/waiting.m4a` + haptic tap, repeated at Settings interval (0.5–3.0 s, default 1.0 s); stops on first answer text, on error, on consent prompt, and on release.
- Settings input mode: `voice` / `text` / `askEachTime`; default `askEachTime`.
- Copy fixed by spec: status **"Asking…"**; consent prompt **"This question needs Apple's Private Cloud Compute. Send this image?"** with buttons **Send** / **Don't send**; not-ready notice **"Apple Intelligence is still getting ready"**.

## Review Focus

1. **Releasing (X) mid-flight** — tapping X while listening or asking must cancel speech/model work, stop the dings immediately, and land in live; late model output must not resurrect an answer. → Task 5 `releaseWhileAskingCancelsAndStopsFeedback`, `lateUpdatesAfterReleaseAreIgnored`.
2. **Empty question** — dictation that ends with silence-only, or sending a blank/whitespace text, must not call the model; return to frozen. → Task 5 `emptyQuestionReturnsToFrozen`.
3. **Tapping Capture/Ask before the camera delivers a frame** (just launched, permission pending) — stay live, no crash. → Task 5 `captureWithoutFrameStaysLive`.
4. **Model error mid-stream** — dings stop, an error message shows in the answer overlay, X still returns to frozen. → Task 5 `askErrorShowsFailureAndStopsFeedback`.
5. **Degenerate layout** — panel taller than the view or zero-size view during first layout must not produce an empty/negative crop. → Task 4 `visibleRectNilWhenFullyObscured`, `visibleRectNilForZeroView`.

---

### Task 1: Project setup (git, test target, plist, resources)

**Files:**
- Modify: `MagnifierClone.xcodeproj/project.pbxproj`
- Modify: `MyApp/ContentView.swift` (remove `import Playgrounds`)
- Create: `MyApp/Resources/waiting.m4a`
- Create: `MagnifierCloneTests/SmokeTests.swift`
- Create: `.gitignore`

**Interfaces:**
- Produces: test target `MagnifierCloneTests` (host app `MagnifierClone`, `@testable import MagnifierClone`), the TEST command working.

- [ ] **Step 1:** `git init`; `.gitignore` with `xcuserdata/`, `*.xcuserstate`, `.DS_Store`, `DerivedData/`, `build/`. Commit the untouched template + docs: `git add -A && git commit -m "chore: initial template and design docs"`.
- [ ] **Step 2:** Edit `project.pbxproj` (hand-written IDs, objectVersion 90) to add a unit-test bundle target `MagnifierCloneTests`: a `PBXFileSystemSynchronizedRootGroup` (path `MagnifierCloneTests`) added to the main group, a product reference `MagnifierCloneTests.xctest`, Sources/Frameworks/Resources phases, a `PBXTargetDependency` + `PBXContainerItemProxy` on the app, Debug/Release configs with `TEST_HOST = "$(BUILT_PRODUCTS_DIR)/MagnifierClone.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/MagnifierClone"`, `BUNDLE_LOADER = "$(TEST_HOST)"`, `PRODUCT_BUNDLE_IDENTIFIER = com.pedrocolonpersonalteam.MagnifierCloneTests`, `GENERATE_INFOPLIST_FILE = YES`, `IPHONEOS_DEPLOYMENT_TARGET = 27.0`, `SDKROOT = iphoneos`, `DEVELOPMENT_TEAM = 7LH226MQY4`. Add it to the project's `targets`. Use new IDs in the same zero-padded style.
- [ ] **Step 3:** In both app configs add: `INFOPLIST_KEY_NSMicrophoneUsageDescription = "To ask questions about what the camera sees using your voice";`, `INFOPLIST_KEY_NSSpeechRecognitionUsageDescription = "To turn your spoken question into text";`, `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = UIInterfaceOrientationPortrait;`, `TARGETED_DEVICE_FAMILY = 1;`.
- [ ] **Step 4:** Download the sound: `mkdir -p MyApp/Resources && curl -fL -o MyApp/Resources/waiting.m4a https://github.com/extratone/iOSSystemSounds/raw/main/m4a/3rdParty_DirectionUp_Haptic.m4a && afinfo MyApp/Resources/waiting.m4a` → expect an AAC/ALAC description, non-zero duration.
- [ ] **Step 5:** Write `SmokeTests.swift`:

```swift
import Testing
@testable import MagnifierClone

@Test func waitingSoundIsBundled() {
    #expect(Bundle.main.url(forResource: "waiting", withExtension: "m4a") != nil)
}
```

- [ ] **Step 6:** Run TEST → expect `** TEST SUCCEEDED **` with 1 test passing. If the scheme lacks the test target, create a shared scheme `MagnifierClone.xcodeproj/xcshareddata/xcschemes/MagnifierClone.xcscheme` with the test target in its TestAction.
- [ ] **Step 7:** Commit: `git add -A && git commit -m "chore: add test target, permissions, waiting sound"`.

---

### Task 2: Settings model

**Files:**
- Create: `MyApp/Settings/AppSettings.swift`
- Test: `MagnifierCloneTests/AppSettingsTests.swift`

**Interfaces:**
- Produces:
  - `enum InputMode: String, CaseIterable { case voice, text, askEachTime }`
  - `enum InputKind { case voice, text }`
  - `@Observable final class AppSettings { init(defaults: UserDefaults = .standard); var inputMode: InputMode; var waitInterval: Double /* seconds */; static let waitIntervalRange: ClosedRange<Double> = 0.5...3.0 }` — persisted under keys `"inputMode"`, `"waitInterval"`; setter clamps `waitInterval` into range.

- [ ] **Step 1: Write failing tests** (use `UserDefaults(suiteName: UUID().uuidString)!`):
  - `defaultsAreAskEachTimeAndOneSecond`: `inputMode == .askEachTime`, `waitInterval == 1.0`.
  - `valuesPersistAcrossInstances`: set `.voice` and `2.0` → new instance on same defaults reads `.voice`, `2.0`.
  - `waitIntervalIsClamped`: set `0.1` → `0.5`; set `9` → `3.0`.
- [ ] **Step 2:** Run TEST `-only-testing:MagnifierCloneTests/AppSettingsTests` → FAIL (types not defined).
- [ ] **Step 3:** Implement `AppSettings` (didSet writes to the injected defaults; `@AppStorage` is not used here because it can't take injected defaults inside `@Observable`).
- [ ] **Step 4:** Run → PASS.
- [ ] **Step 5:** Commit `feat: settings model with input mode and wait interval`.

---

### Task 3: Zoom mapping

**Files:**
- Create: `MyApp/Camera/ZoomMapping.swift`
- Test: `MagnifierCloneTests/ZoomMappingTests.swift`

**Interfaces:**
- Produces: `struct ZoomMapping { init(maxDeviceFactor: CGFloat); let maxFactor: CGFloat /* min(maxDeviceFactor, 10) */; func factor(forSlider value: Double) -> CGFloat; func sliderValue(forFactor f: CGFloat) -> Double; func stepped(from value: Double, by step: Int) -> Double }`. Slider is 0…1, mapping is exponential (`1 * pow(maxFactor, value)`) so each slider step feels like equal magnification; `stepped` moves by 0.1 per step, clamped to 0…1.

- [ ] **Step 1: Write failing tests:** `factor(forSlider: 0) == 1`; with max device 15 → `maxFactor == 10`, `factor(forSlider: 1) == 10`; `factor(forSlider: 0.5) ≈ sqrt(10)` (±0.001); `sliderValue(forFactor: factor(forSlider: 0.3)) ≈ 0.3`; `stepped(from: 0.95, by: 1) == 1`; `stepped(from: 0.05, by: -1) == 0`; with max device 1 (front camera edge) → `factor(forSlider: 1) == 1`.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run → PASS.
- [ ] **Step 5:** Commit `feat: zoom slider mapping`.

---

### Task 4: FrameCropper

**Files:**
- Create: `MyApp/Camera/FrameCropper.swift`
- Test: `MagnifierCloneTests/FrameCropperTests.swift`

**Interfaces:**
- Produces:
  - `struct FrozenFrame { let image: CIImage /* upright, full buffer, origin .zero */; let visibleRect: CGRect /* in image pixels, top-left origin */ }`
  - `enum FrameCropper { static func visibleRect(imageSize: CGSize, viewSize: CGSize, obscuredBottom: CGFloat) -> CGRect?; static func croppedImage(_ frame: FrozenFrame) -> CIImage; static func cloudJPEG(_ frame: FrozenFrame, maxLongEdge: CGFloat = 1536, quality: CGFloat = 0.8) throws -> URL }`
  - `visibleRect`: image is aspect-filled into `viewSize`; returns the image-pixel rect showing in the view's top `viewSize.height - obscuredBottom` points; `nil` if visible height ≤ 0 or view size is zero.
  - `croppedImage`: converts top-left rect to Core Image's bottom-left coords, crops, translates to origin.
  - `cloudJPEG`: crop → Lanczos downscale only if long edge > `maxLongEdge` → JPEG at `quality` written to a unique file in `FileManager.default.temporaryDirectory`.

- [ ] **Step 1: Write failing tests** (accuracy ±0.5):
  - `visibleRectPortraitPhone`: image 1080×1920, view 390×844, obscured 300 → `x 96.40, y 0, w 887.20, h 1237.54`.
  - `visibleRectNoObstruction`: same with obscured 0 → height `1920`.
  - `visibleRectNilWhenFullyObscured`: obscured 844 → `nil`; obscured 900 → `nil`.
  - `visibleRectNilForZeroView`: view `.zero` → `nil`.
  - `croppedImageTakesTopRegion`: build a 100×200 `CIImage` whose top half is red and bottom half blue (two `CIImage(color:)` cropped and composited); `visibleRect = (0,0,100,100)` → result extent `(0,0,100,100)`, center pixel rendered via `CIContext` is red.
  - `cloudJPEGDownscalesLongEdge`: 3000×4000 solid image, full visible rect → file exists, `CGImageSourceCreateWithURL` pixel height `1536`, width `1152`.
  - `cloudJPEGKeepsSmallImages`: 800×600 → stays 800×600.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement (all functions `nonisolated`; use a shared `nonisolated(unsafe) static let context = CIContext()`).
- [ ] **Step 4:** Run → PASS.
- [ ] **Step 5:** Commit `feat: crop frozen frame to visible region`.

---

### Task 5: AppModel state machine

**Files:**
- Create: `MyApp/App/AppModel.swift`, `MyApp/App/Services.swift`
- Test: `MagnifierCloneTests/AppModelTests.swift`, `MagnifierCloneTests/Fakes.swift`

**Interfaces:**
- Consumes: `AppSettings`, `InputMode`, `InputKind` (Task 2); `FrozenFrame`, `FrameCropper.visibleRect` (Task 4).
- Produces (in `Services.swift`):

```swift
protocol FrameSource: AnyObject { func latestFrame() -> CIImage? }
enum ModelAvailability: Equatable { case available, notReady, unavailable }
enum AskRoute: Equatable { case onDevice, cloud, vision }
enum AskUpdate: Equatable { case partial(String) /* cumulative */, needsCloud }
protocol AskServicing: AnyObject {
    var availability: ModelAvailability { get }
    func answer(_ question: String, frame: FrozenFrame, route: AskRoute) -> AsyncThrowingStream<AskUpdate, Error>
}
protocol SpeechServicing: AnyObject {
    func transcribe() -> AsyncThrowingStream<String, Error> // cumulative text; finishes on silence or stop()
    func stop()
}
protocol WaitingFeedbackPlaying: AnyObject { func start(interval: Double); func stop() }
```

- Produces (in `AppModel.swift`):

```swift
enum Phase: Equatable {
    case live
    case frozen
    case choosingInput
    case listening(transcript: String)
    case typing
    case asking(question: String)
    case awaitingCloudConsent(question: String)
    case answering(question: String, answer: String, notice: String?, isComplete: Bool)
    case failed(question: String, message: String)
}
@Observable final class AppModel {
    init(settings: AppSettings, frames: FrameSource, ask: AskServicing, speech: SpeechServicing, feedback: WaitingFeedbackPlaying)
    private(set) var phase: Phase
    private(set) var frozenImage: CIImage?
    var viewSize: CGSize; var obscuredBottom: CGFloat   // set by UI layout
    var isFrozen: Bool { phase != .live }
    func capture()
    func release()
    func askTapped()
    func choose(_ kind: InputKind)
    func stopListening()
    func submit(question: String)
    func respondToCloudConsent(send: Bool)
    func dismissAnswer()
}
```

Transitions (the implementer writes these; tests pin them):
- `capture()`: live → frozen iff `frames.latestFrame()` non-nil (stores `frozenImage`). Otherwise no-op.
- `askTapped()`: freeze if live (abort if no frame); then `.askEachTime` → `choosingInput`, `.voice` → `choose(.voice)`, `.text` → `choose(.text)`. Ignored in asking/answering/consent/listening phases.
- `choose(.voice)` → `listening("")`, consume `speech.transcribe()`; each element updates transcript; on finish → `submit(question: transcript)`. `choose(.text)` → `typing`.
- `submit`: trimmed empty → `frozen`. Else `asking(q)`, `feedback.start(interval: settings.waitInterval)`, route from availability (`available` → `.onDevice`; `notReady` → `.vision` with notice "Apple Intelligence is still getting ready"; `unavailable` → `.vision`, no notice).
- First non-empty `.partial` → `feedback.stop()`, `answering(..., isComplete: false)`; stream end → `isComplete: true`.
- `.needsCloud` → `feedback.stop()`, `awaitingCloudConsent(q)`. `respondToCloudConsent(send: true)` → `asking`, feedback restarts, route `.cloud`; `send: false` → `asking`, route `.vision` (feedback restarts).
- Thrown error → `feedback.stop()`, `failed(q, message: error.localizedDescription)`.
- `dismissAnswer()`: from answering/failed → `frozen`.
- `release()`: from any phase → cancel the current task, `speech.stop()`, `feedback.stop()`, `frozenImage = nil`, `live`. Each ask run carries a generation token; updates from a stale generation are dropped.
- `FrozenFrame` passed to `ask.answer` = `frozenImage` + `FrameCropper.visibleRect(imageSize:viewSize:obscuredBottom:)`, falling back to the full image extent if `nil`.

- [ ] **Step 1: Write fakes** in `Fakes.swift`: `FakeFrames` (settable `frame: CIImage?`), `FakeAsk` (settable `availability`, records `(question, route)` calls, returns a stream driven by a stored `AsyncThrowingStream.Continuation` the test controls), `FakeSpeech` (test-controlled continuation; `stopCount`), `FakeFeedback` (`startCount`, `stopCount`, `lastInterval`, `isRunning`).
- [ ] **Step 2: Write failing tests** (`@MainActor` suite; use `await Task.yield()`/a small `waitUntil` helper polling up to 1 s for async transitions):
  - `captureFreezesAndReleaseReturnsLive`
  - `captureWithoutFrameStaysLive` (frame nil → `.live`; `askTapped()` also stays `.live`)
  - `askTappedAskEachTimeShowsChooser`; `askTappedVoiceModeStartsListening`; `askTappedTextModeStartsTyping`
  - `voiceTranscriptStreamsThenSubmitsOnFinish` (yield "what", "what is this" → `.listening("what is this")`; finish → `.asking("what is this")`, FakeAsk called with route `.onDevice`)
  - `emptyQuestionReturnsToFrozen` (submit `"   "` → `.frozen`, FakeAsk not called, feedback never started; voice finishing with `""` → same)
  - `askingStartsFeedbackWithSettingsInterval` (interval 2.0 → `lastInterval == 2.0`)
  - `firstPartialStopsFeedbackAndShowsAnswer`; `streamEndMarksComplete`
  - `needsCloudPromptsAndSendUsesCloudRoute`; `declineCloudUsesVisionRoute`
  - `notReadyUsesVisionWithNotice` (notice == "Apple Intelligence is still getting ready"); `unavailableUsesVisionWithoutNotice`
  - `askErrorShowsFailureAndStopsFeedback`
  - `dismissAnswerReturnsToFrozen` (from answering and from failed)
  - `releaseWhileAskingCancelsAndStopsFeedback` (also `speech.stopCount >= 1` when released while listening)
  - `lateUpdatesAfterReleaseAreIgnored` (release, then yield `.partial("x")` on the old continuation → stays `.live`)
  - `askTappedWhileAskingIsIgnored`
- [ ] **Step 3:** Run TEST `-only-testing:MagnifierCloneTests/AppModelTests` → FAIL.
- [ ] **Step 4:** Implement `Services.swift` and `AppModel.swift`.
- [ ] **Step 5:** Run → all PASS. Run full TEST → all PASS.
- [ ] **Step 6:** Commit `feat: app state machine for freeze and ask flow`.

---

### Task 6: Waiting feedback (sound + haptic)

**Files:**
- Create: `MyApp/Ask/WaitingFeedback.swift`
- Test: `MagnifierCloneTests/WaitingFeedbackTests.swift`

**Interfaces:**
- Consumes: `WaitingFeedbackPlaying` (Task 5).
- Produces: `final class WaitingFeedback: WaitingFeedbackPlaying { init(ding: @escaping () -> Void = WaitingFeedback.systemDing) }` plus `static func systemDing()`, which plays `waiting.m4a` through a cached `AVAudioPlayer` (audio session `.ambient`, `.mixWithOthers`, so the silent switch mutes it) and a Core Haptics transient event (intensity 1.0, sharpness 0.8); haptics are skipped if `CHHapticEngine.capabilitiesForHardware().supportsHaptics` is false.
- `start(interval:)` dings immediately, then every `interval` seconds via a `Task` loop; calling `start` again restarts; `stop()` cancels.

- [ ] **Step 1: Write failing tests** with a counting `ding` closure:
  - `startDingsImmediately` (count == 1 right after start)
  - `repeatsAtInterval` (interval 0.1, wait 0.35 s → count in 3...5)
  - `stopHaltsDings` (stop, wait 0.3 s → count unchanged)
  - `restartDoesNotDoubleSchedule` (start twice at 0.1, wait 0.35 s → count ≤ 6)
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run → PASS.
- [ ] **Step 5:** Commit `feat: repeating waiting sound and haptic`.

---

### Task 7: Camera service and preview

**Files:**
- Create: `MyApp/Camera/CameraService.swift`, `MyApp/Camera/CameraPreview.swift`

**Interfaces:**
- Consumes: `FrameSource` (Task 5), `ZoomMapping` (Task 3).
- Produces:
  - `@Observable final class CameraService: FrameSource { func start() async; func stop(); var zoom: ZoomMapping { get }; func setZoom(slider: Double); private(set) var sliderValue: Double; func latestFrame() -> CIImage? }`
  - `struct CameraPreview: UIViewRepresentable { let session: AVCaptureSession }` (`AVCaptureVideoPreviewLayer`, `.resizeAspectFill`)
  - `struct FrozenFrameView: View { let image: CIImage }` (renders a `CGImage` with `.scaledToFill()`, clipped — must match the preview's aspect fill exactly)

- [ ] **Step 1:** Implement `CameraService`: back wide camera (`.builtInWideAngleCamera`), session preset `.high`, `AVCaptureVideoDataOutput` (BGRA, `alwaysDiscardsLateVideoFrames`) on a serial queue. Set the output connection's `videoRotationAngle = 90` so buffers are delivered upright portrait. Keep the latest `CVPixelBuffer` behind an `OSAllocatedUnfairLock`; `latestFrame()` wraps it as `CIImage(cvPixelBuffer:)`. Request camera permission in `start()`. Zoom: `lockForConfiguration`, `videoZoomFactor = zoom.factor(forSlider:)`, where `ZoomMapping(maxDeviceFactor: device.activeFormat.videoMaxZoomFactor)`.
- [ ] **Step 2:** Build: `xcodebuild build -project MagnifierClone.xcodeproj -scheme MagnifierClone -destination 'generic/platform=iOS' -quiet` → `** BUILD SUCCEEDED **`. Run full TEST → PASS.
- [ ] **Step 3:** Commit `feat: camera capture with zoom and latest-frame access`.

(On-device behavior is verified in Task 12.)

---

### Task 8: AskService (Foundation Models, PCC, Vision fallback)

**Files:**
- Create: `MyApp/Ask/AskService.swift`, `MyApp/Ask/VisionFallback.swift`
- Test: `MagnifierCloneTests/AskServiceTests.swift`

**Interfaces:**
- Consumes: `AskServicing`, `AskRoute`, `AskUpdate`, `ModelAvailability` (Task 5); `FrameCropper` (Task 4).
- Produces:
  - `final class AskService: AskServicing { init(cloudEnabled: Bool = true) }`
  - `static func mapAvailability(_ a: SystemLanguageModel.Availability) -> ModelAvailability` (`.available` → `.available`; `.unavailable(.modelNotReady)` → `.notReady`; other unavailable reasons → `.unavailable`)
  - `static func shouldEscalate(_ error: Error) -> Bool` (true for `LanguageModelSession.GenerationError.exceededContextWindowSize` and other capability errors the SDK exposes; false for cancellation, guardrail, and anything else)
  - `enum VisionFallback { static func describe(_ image: CIImage) async throws -> String }` → `"Text: <recognized lines joined by space>"` and/or `"Looks like: <top 3 classification identifiers with confidence ≥ 0.3, comma-separated>"`, lines joined by `\n`; `"I couldn't find any text or recognizable objects."` if both are empty.
- Prompt instructions (verbatim): `"You help a person with low vision understand what their camera shows. Answer concisely."`
- `.onDevice`: `LanguageModelSession(tools: [OCRTool()], instructions:)`; `streamResponse { question; Attachment(FrameCropper.croppedImage(frame)).label("frame") }`; yield `.partial(snapshot.content)` per snapshot. On an error where `shouldEscalate` is true, yield `.needsCloud` and finish (only if `cloudEnabled`; otherwise rethrow).
- `.cloud`: same prompt, with the session built on `PrivateCloudComputeLanguageModel` and `Attachment(url)` from `FrameCropper.cloudJPEG(frame)`; delete the temp file afterwards. If PCC isn't usable from this app (missing entitlement / unavailable symbol), keep this branch behind `cloudEnabled` and set it to `false` in `MagnifierApp`; report it in the task summary.
- `.vision`: yield one `.partial(VisionFallback.describe(croppedImage))`.
- Verify the exact `Attachment`, `OCRTool`, `PrivateCloudComputeLanguageModel` and `streamResponse` signatures against the iOS 27.1 SDK headers (`swift-symbolgraph-extract` or Xcode's Quick Help). The spec's example code is the reference; the SDK wins on any conflict.

- [ ] **Step 1: Write failing tests:**
  - `mapAvailabilityCases` (all four cases)
  - `escalatesOnContextWindowError` (true); `doesNotEscalateOnCancellation` (`CancellationError()` → false)
  - `visionFallbackReadsText`: render "HELLO 42" in black 120-pt bold on white (`UIGraphicsImageRenderer` → `CIImage`) → the result contains `"HELLO"`.
  - `visionFallbackEmptyImageMessage`: a blank white image → the result has no `"Text:"` line.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run → PASS (the model paths are verified on device in Task 12).
- [ ] **Step 5:** Commit `feat: ask service with on-device, cloud, and vision routes`.

---

### Task 9: SpeechService

**Files:**
- Create: `MyApp/Ask/SpeechService.swift`

**Interfaces:**
- Consumes: `SpeechServicing` (Task 5).
- Produces: `final class SpeechService: SpeechServicing { init(silenceTimeout: Duration = .seconds(1.5)) }`

- [ ] **Step 1:** Implement with `SpeechAnalyzer` + `SpeechTranscriber` (current locale, volatile results enabled, on-device asset install via `AssetInventory` if needed), fed from an `AVAudioEngine` input tap converted to the analyzer's best format. Yield cumulative text (finalized + current volatile). Finish when no new text arrives for `silenceTimeout` *after the first non-empty text*, when `stop()` is called, or after a 10 s hard cap with no speech (yield nothing and finish). Request microphone and speech authorization. On denial, throw an error whose `localizedDescription` says to enable the microphone in Settings. Set the audio session to `.playAndRecord` while recording and restore it on finish.
- [ ] **Step 2:** Build for generic iOS → succeeds; full TEST → PASS.
- [ ] **Step 3:** Commit `feat: on-device dictation service`.

---

### Task 10: Main screen + control panel (zoom, capture/X, settings)

**Files:**
- Create: `MyApp/UI/RootView.swift`, `MyApp/UI/ControlPanel.swift`, `MyApp/UI/SettingsView.swift`
- Modify: `MyApp/MyApp.swift` (build services and `AppModel`, show `RootView`); delete `MyApp/ContentView.swift`

**Interfaces:**
- Consumes: `AppModel` (Task 5), `CameraService`/`CameraPreview`/`FrozenFrameView` (Task 7), `AppSettings` (Task 2), `WaitingFeedback` (6), `AskService` (8), `SpeechService` (9).
- Produces: `RootView(model: AppModel, camera: CameraService, settings: AppSettings)`; `ControlPanel` reports its height so `RootView` sets `model.obscuredBottom` (via `onGeometryChange`), and sets `model.viewSize` to the full screen size.

- [ ] **Step 1:** `ControlPanel` per the spec's layout table and the reference screenshots: near-black (`Color(white: 0.09)`) sheet, top corner radius ~44, grab handle; 4-column grid of 72-pt dark-gray (`Color(white: 0.22)`) circles; row 1 has the zoom capsule spanning 3 columns (`magnifyingglass` plus `minus`, a custom slider with a yellow knob, and `plus`) and the torch (`flashlight.off.fill`); row 2 holds placeholders (`circle.grid.cross.fill`, `arrow.triangle.2.circlepath.camera`, yellow `sun.max.fill`, `circle.circle`); row 3 has Detect (`viewfinder`), Ask (`text.bubble`), Capture (white ring with an inner ring, or `xmark` when `model.isFrozen`), and Settings (`gear`), with labels. Placeholders are no-ops with `.accessibilityHint("Not available yet")`. Zoom −/+ use `ZoomMapping.stepped`, and the slider calls `camera.setZoom(slider:)`.
- [ ] **Step 2:** `RootView`: a full-screen `CameraPreview` when live, `FrozenFrameView(model.frozenImage)` when frozen, the panel at the bottom, and `SettingsView` in a sheet: a segmented picker for input mode (Voice / Text / Ask each time) and a slider for the waiting sound interval, 0.5–3.0 s step 0.5 with the value shown in seconds. Start the camera in `.task`.
- [ ] **Step 3:** Build → succeeds; full TEST → PASS. Run on the iPhone 18 Pro simulator and take a screenshot (`xcrun simctl io booted screenshot`): the panel layout matches the reference (the camera is black on the simulator).
- [ ] **Step 4:** Commit `feat: main screen with control panel, zoom, freeze, settings`.

---

### Task 11: Ask flow UI

**Files:**
- Create: `MyApp/UI/AskOverlay.swift` (input chooser, question pill, text pill, "Asking…", consent prompt, answer overlay)
- Modify: `MyApp/UI/RootView.swift` (place `AskOverlay` above the frame and below the panel)

**Interfaces:**
- Consumes: `AppModel.phase` and its methods (Task 5).

- [ ] **Step 1:** Render by phase:
  - `choosingInput`: two large buttons, **Voice** (`mic.fill`) and **Text** (`keyboard`), calling `choose`.
  - `listening(t)`: a top pill (capsule, `.ultraThinMaterial`, white text, mic icon) shows `t`, or "Listening…" when empty; tapping it calls `stopListening()`.
  - `typing`: a capsule `TextField` pinned above the keyboard (`.safeAreaInset(edge: .bottom)` with auto focus) and a send button. On submit, the pill moves to the top using `matchedGeometryEffect` and the keyboard dismisses, then `submit(question:)` is called.
  - `asking(q)`: top pill `q` plus **"Asking…"** with a `ProgressView` below it.
  - `awaitingCloudConsent`: the spec's consent copy with **Send** / **Don't send**, calling `respondToCloudConsent`.
  - `answering`/`failed`: a full-screen `Color.black.opacity(0.75)` with white text, the question (`.title2.bold()`) on top, the optional notice (`.callout`, secondary), and the answer/message (`.title3`) below in a `ScrollView`. All text uses Dynamic Type, and an X button (top-trailing, 44-pt) calls `dismissAnswer()`. When `isComplete` becomes true, post `AccessibilityNotification.Announcement(answer)`.
- [ ] **Step 2:** Build → succeeds; full TEST → PASS. On the simulator, Capture → Ask → Text → type "test" → send: the pill moves to the top and "Asking…" shows (an answer appears if the Mac's simulator supports Apple Intelligence; otherwise you get the Vision fallback text).
- [ ] **Step 3:** Commit `feat: ask flow overlays`.

---

### Task 12: On-device verification

**Files:** none (fixes found here go into the owning task's files, with a commit per fix)

- [ ] **Step 1:** Run on a physical Apple Intelligence iPhone (team `7LH226MQY4`) and check each item, noting pass/fail in the task summary:
  1. Zoom slider and −/+ change the magnification smoothly, up to 10×.
  2. Capture freezes the frame and the button becomes an X; tapping X returns to live.
  3. At 4× zoom, Ask → Text "what does this say?" on a printed page: the answer refers only to text visible above the panel. To check the crop, temporarily log `visibleRect` and save the cropped JPEG to Photos.
  4. Waiting sound plus haptic every ~1 s, and every 2.5 s after changing Settings. The sound is muted by the silent switch while the haptic still fires, and both stop when the answer starts streaming.
  5. Voice: the pill fills as you speak and the question is sent after about 1.5 s of silence. Tapping the pill sends it immediately.
  6. Answer screen: the X returns to the frozen frame, and with VoiceOver on the answer is announced.
  7. Turn off Apple Intelligence in Settings → Ask returns the "Text: / Looks like:" fallback.
  8. Force escalation (e.g. ask for a very long, detailed description) → the consent prompt appears, and **Don't send** returns the Vision result. **Send** returns a cloud answer, or the cloud path is reported as disabled.
  9. Release with X while "Asking…" → the sound stops immediately.
- [ ] **Step 2:** Commit any fixes; final full TEST → PASS.
