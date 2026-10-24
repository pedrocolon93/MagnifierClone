# MagnifierClone — v1 Design (Zoom + Freeze + Ask)

## Intent

A clone of Apple's Magnifier app for iPhone. The headline feature is **Ask**: freeze what the camera sees and ask a question about it, answered by Apple's on-device Foundation Models (with image input). The target user is someone with low vision, so legibility, feedback while waiting, and "the model sees exactly what I see" matter more than feature breadth.

## Goals (v1)

- Live camera preview with a working **zoom** slider (− / + and drag).
- **Capture** freezes the current frame; while frozen, the Capture button becomes an **X** that releases the frame back to live.
- **Ask** freezes the frame (if not already frozen), takes one question (voice or typed), and shows the answer.
- **Settings** page with: input mode, and waiting-sound periodicity.
- Control panel visually matching the screenshots (dark rounded sheet, 4-column circular buttons, zoom capsule, labels under the bottom row).

### Control panel layout (reference: `assets/magnifier-ref-1.jpeg`, `assets/magnifier-ref-2.jpeg`)

Dark, near-black rounded sheet pinned to the bottom with a grab handle on top. Grid of 4 columns:

| Row | Col 1 | Col 2 | Col 3 | Col 4 |
|---|---|---|---|---|
| 1 | Zoom capsule spanning cols 1–3: magnifier-plus icon, −, slider (yellow knob), + | | | Torch (placeholder) |
| 2 | Filters / dots (placeholder) | Camera flip (placeholder) | Brightness, yellow sun (placeholder) | Color/contrast circles (placeholder) |
| 3 | **Detect** (placeholder, labeled) | **Ask** (speech bubble, labeled) | **Capture** (large white ring, labeled; becomes X when frozen) | **Settings** (gear, labeled) |

Buttons are dark-gray circles; only row 3 has text labels below. VoiceOver order follows reading order (row by row, left→right).

## Non-goals (v1)

- Torch, filters (dots), camera flip, brightness, color/contrast, Detect: present as **placeholder buttons** (visible, no-op).
- Follow-up questions / multi-turn chat. **One question per freeze.**
- Saving/sharing captured images.
- iPad / landscape-specific layouts.

## Anti-goals

- The model must never see a different image than the user saw (wrong frame, uncropped full sensor frame, stale frame).
- No silent waiting: the user must always get audible/haptic feedback while an answer is pending.

## Constraints

- iOS 27 deployment target (already set in project). Existing project: `MagnifierClone.xcodeproj`, sources in `MyApp/`. Camera usage string already present.
- Needs `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription` added.
- Foundation Models requires an Apple Intelligence–capable device with it enabled; must handle unavailability.

## Decided behavior

### Capture / freeze

- `CameraService` (AVFoundation) streams frames to the preview and always retains the **latest `CVPixelBuffer`** plus its orientation.
- Freeze = snapshot the latest buffer; the preview shows that still. Both **Capture** and **Ask** enter the frozen state.
- While frozen, the Capture button renders as an **X**; tapping it unfreezes and discards any Ask state.

### Image preparation ("only what's on screen")

- Crop the frozen buffer to **exactly the visible region**: account for zoom factor (if digital zoom is applied in-app rather than via `videoZoomFactor`), preview aspect-fill cropping, and orientation. The region **covered by the control panel is excluded**, since the panel is opaque and the user can't see it. *(Claude's call.)*
- Crop/rotate on GPU via Core Image.
- **On-device request:** attach the full-resolution crop.
- **Private Cloud Compute fallback:** downscale crop (long edge ≈1536 px) and/or pass as JPEG (~0.8) via file URL to reduce upload. *Whether this measurably reduces upload is unverified — measure.*

### Ask flow

1. Tap **Ask** → frame freezes → choose input per Settings mode (see Settings).
2. **Voice:** mic starts; on-device transcription (`SpeechAnalyzer`/`SpeechTranscriber`) streams into a **pill at the top of the screen**. Ends on short silence or tap on the pill.
3. **Text:** a pill text field sits **above the keyboard**; on send it animates to the **top pill position** and the keyboard dismisses.
4. Below the top pill: **"Asking…"** status.
5. While waiting: play `3rdParty_DirectionUp_Haptic.m4a` (bundled; source: https://github.com/extratone/iOSSystemSounds/raw/main/m4a/3rdParty_DirectionUp_Haptic.m4a) **plus a matching haptic tap**, repeating at the Settings periodicity ("ding ding ding"). Stops when the first answer token arrives. Sound respects the silent switch; haptic always fires. Audio session mixes with others.
6. **Answer screen:** semi-transparent black overlay over the frozen frame, white text: the question at top, the answer below. Answer streams in. Large text, Dynamic Type. VoiceOver announces the answer on arrival.
7. Answer screen has an **X**: closes the answer and returns to the **frozen frame** (user can Ask again — fresh session — or use the Capture X to go live).

### Model usage (`AskService`)

- New `LanguageModelSession(tools: [OCRTool()])` per question. OCR tool is always included.
- Prompt: system-style instruction ("You help a person with low vision understand what their camera shows. Answer concisely.") + user question + `Attachment(croppedImage, orientation:).label("frame")`.
- Use `streamResponse` for streaming.
- Escalation: on-device first; fall back to `PrivateCloudComputeLanguageModel` if the on-device call fails due to context/capability errors.
- **Never escalate silently** *(Pedro's decision)*. Before sending, stop the waiting sound and show a prompt over the frozen frame: "This question needs Apple's Private Cloud Compute. Send this image?" **Send** → resume "Asking…" + waiting sound, upload compressed crop. **Don't send** → Vision fallback result. Asked every time escalation is needed *(Claude's call: one question per freeze makes this rare, and the image differs each time)*.
- PCC access from a third-party app may need an entitlement; build the PCC path behind a single flag so it can be stubbed if unavailable, and measure upload size only if it works.
- Availability is treated as distinct cases *(Claude's call)*: **model not ready (downloading)** → show "Apple Intelligence is still getting ready" + Vision fallback result; **device not eligible / Apple Intelligence off** → Vision fallback silently.
- If `SystemLanguageModel.default.availability` is unavailable: **Vision fallback** — run text recognition + image classification on the crop and present the result as the answer (formatted plainly, e.g., "Text: … / Looks like: …").

### Settings

- Opened from the Settings button (sheet).
- **Input mode:** Voice / Text / Ask each time *(Pedro's decision)*. Ask each time shows the Voice/Text chooser on every Ask tap; Voice or Text skips the chooser. Default = Ask each time.
- **Waiting sound interval:** slider, ~0.5–3 s, default 1.0 s.
- Persisted with `@AppStorage`.

### Zoom

- Slider maps to `AVCaptureDevice.videoZoomFactor` (1× … device max, capped e.g. 10×), −/+ step buttons. Using hardware zoom means the preview already shows the cropped region; the crop computation must use the same factor.

## Structure (proposed)

```
MyApp/
  MyApp.swift
  App/AppModel.swift            // @Observable: live/frozen state, ask phase, settings
  Camera/CameraService.swift    // AVCaptureSession, zoom, latest frame
  Camera/CameraPreview.swift    // UIViewRepresentable / frozen still view
  Camera/FrameCropper.swift     // visible-region math + Core Image crop/resize/JPEG
  Ask/AskService.swift          // FoundationModels session, OCRTool, PCC + Vision fallback
  Ask/SpeechService.swift       // SpeechAnalyzer dictation
  Ask/WaitingFeedback.swift     // repeating sound + Core Haptics
  UI/ControlPanel.swift         // bottom sheet matching screenshots
  UI/QuestionPill.swift
  UI/AnswerOverlay.swift
  UI/SettingsView.swift
  Resources/waiting.m4a
```

State machine: `live → frozen → choosingInput → listening|typing → asking → answered → (X) frozen → (Capture X) live`. Unfreezing from any state cancels in-flight speech/model tasks and stops waiting feedback.

## Left to the builder

- Exact visual metrics of the control panel (match screenshots).
- Pill styling and animation curves.
- Error copy (model error, mic denied, camera denied).
- Silence-detection threshold for voice.

## Notes

- The waiting sound is an Apple system sound redistributed via GitHub; fine for personal use, should be replaced before any App Store release. Keep it a single swappable resource.
- `MyApp/ContentView.swift` currently imports `Playgrounds`; remove when replacing.
