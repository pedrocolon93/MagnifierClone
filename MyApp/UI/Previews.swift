#if DEBUG
import AVFoundation
import CoreImage
import SwiftUI

// Preview-only stand-ins for the services, so the Ask states can be seen in the canvas.
// Compiled only in Debug and referenced only from #Preview, never from the app's runtime paths.

private final class PreviewFrames: FrameSource {
    /// A portrait checkerboard, so the aspect-fill crop is visible.
    private let image = CIFilter(name: "CICheckerboardGenerator", parameters: [
        "inputColor0": CIColor(red: 0.85, green: 0.85, blue: 0.8), "inputColor1": CIColor(red: 0.2, green: 0.3, blue: 0.4),
        "inputWidth": 90,
    ])!.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: 1080, height: 1920))

    func latestFrame() -> CIImage? { image }
}

private struct PreviewError: LocalizedError {
    var errorDescription: String? { "The model couldn't answer right now." }
}

private final class PreviewAsk: AskServicing {
    enum Outcome { case pending, answer(notice: String?), failure }
    let outcome: Outcome
    init(_ outcome: Outcome) { self.outcome = outcome }

    var availability: ModelAvailability { .available }

    func answer(_ question: String, frame: FrozenFrame, route: AskRoute) -> AsyncThrowingStream<AskUpdate, Error> {
        AsyncThrowingStream { continuation in
            switch outcome {
            case .pending:
                break
            case .answer(let notice):
                if let notice { continuation.yield(.notice(notice)) }
                continuation.yield(.partial("Text: BEST BEFORE\n12 NOV 2026\nLooks like: carton, food"))
                continuation.finish()
            case .failure:
                continuation.finish(throwing: PreviewError())
            }
        }
    }
}

private final class PreviewSpeech: SpeechServicing {
    func transcribe() -> AsyncThrowingStream<String, Error> { AsyncThrowingStream { _ in } }
    func stop() {}
}

private final class PreviewFeedback: WaitingFeedbackPlaying {
    func start(interval: Double) {}
    func stop() {}
}

/// The main screen without the live camera: frozen frame, control panel and Ask overlays.
private struct AskPreview: View {
    let model: AppModel
    let camera = CameraService()

    init(_ outcome: PreviewAsk.Outcome?) {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "preview")!)
        settings.inputMode = .text
        model = AppModel(settings: settings, frames: PreviewFrames(), ask: PreviewAsk(outcome ?? .pending),
                         speech: PreviewSpeech(), feedback: PreviewFeedback())
        model.capture()
        if outcome != nil {
            model.askTapped()
            model.submit(question: "When does this expire?")
        }
    }

    var body: some View {
        CameraLayer(model: model, session: camera.session)
            .overlay(alignment: .bottom) {
                ControlPanel(model: model, camera: camera) {}
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { model.obscuredBottom = $0 }
                    .ignoresSafeArea(edges: .bottom)
            }
            .overlay { AskOverlay(model: model) }
            .preferredColorScheme(.dark)
    }
}

#Preview("Frozen") { AskPreview(nil) }
#Preview("Asking") { AskPreview(.pending) }
#Preview("Answering") { AskPreview(.answer(notice: nil)) }
#Preview("Answering with notice") { AskPreview(.answer(notice: AskService.fallbackNotice)) }
#Preview("Failed") { AskPreview(.failure) }
#endif
