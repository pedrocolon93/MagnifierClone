# MagnifierClone

> **Sample project.** This is a small personal sample I built to show the idea of asking questions about what the
> camera sees. It is not Apple's code, it is not affiliated with or endorsed by Apple, and it isn't meant for
> production use.

A recreation of the Magnifier app for iPhone, built around one feature: **Ask**. Point the camera at something,
ask a question out loud (or type it), and get an answer about exactly what's on screen, using Apple's on-device
Foundation Models with image input.

It's designed with low-vision users in mind, so it focuses on clear feedback while you wait and on making sure
the model sees the same image you do.

## What it does

- Live camera preview with zoom, freeze (Capture), flip camera, and a working flashlight.
- **Ask:** freezes the frame, listens to your question with live dictation, and answers it.
- Only what's visible on screen is sent to the model: the frame is cropped to the preview, the zoom, and the
  area above the control panel.
- A waiting sound and haptics repeat while the answer is on its way (the sound, its timing, and vibration can be
  changed in Settings).
- Follow-up questions about the same frame.
- Two answer styles: **Standard** (short) and **Accessibility** (adds the details that matter, where things are,
  and what you could do next).
- Falls back to on-device text recognition (Vision) when it helps.

## Requirements

- Xcode 26.3 or later, iOS 27.
- An Apple Intelligence–capable iPhone with Apple Intelligence turned on (Foundation Models runs on device).
- Camera, microphone, and speech recognition permissions.

## Running it

1. Open `MagnifierClone.xcodeproj`.
2. Pick your own team under **Signing & Capabilities** (and change the bundle ID if needed).
3. Run on a real device. The camera doesn't work in the Simulator.

Tests live in `MagnifierCloneTests` and run with **Product → Test**.

## Layout

| Folder | What's in it |
|---|---|
| `MyApp/Camera` | Camera session, preview, zoom mapping, and cropping the frame to what's on screen |
| `MyApp/Ask` | The Ask flow: speech, the model call, the text recognition fallback, and waiting feedback |
| `MyApp/UI` | Control panel, Ask overlay, and Settings |
| `MyApp/Settings` | Saved settings and the list of system sounds |
| `docs/` | The design spec and implementation plan |

## Related

This sample goes with the [Magnifier VQA case study](https://pedroacolon.com/projects/magnifier-vqa/) on my portfolio.

The default waiting sound comes from the [iOSSystemSounds](https://github.com/extratone/iOSSystemSounds) collection.
