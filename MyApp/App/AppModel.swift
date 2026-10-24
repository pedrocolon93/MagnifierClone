import CoreGraphics
import CoreImage
import Foundation
import Observation

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

/// Owns live/frozen state and the Ask flow. Talks to services only through protocols.
@Observable
final class AppModel {
    static let notReadyNotice = "Apple Intelligence is still getting ready"
    static let noAnswerMessage = "No answer was produced. Try asking again."

    private(set) var phase: Phase = .live
    private(set) var frozenImage: CIImage?
    /// Set by the UI layout; used to crop the frozen frame to what's visible.
    var viewSize: CGSize = .zero
    var obscuredBottom: CGFloat = 0
    var isFrozen: Bool { phase != .live }

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let frames: FrameSource
    @ObservationIgnored private let ask: AskServicing
    @ObservationIgnored private let speech: SpeechServicing
    @ObservationIgnored private let feedback: WaitingFeedbackPlaying

    /// The task consuming the current speech or answer stream.
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Bumped whenever the current run is superseded; updates from older runs are dropped.
    @ObservationIgnored private var generation = 0

    init(settings: AppSettings, frames: FrameSource, ask: AskServicing, speech: SpeechServicing, feedback: WaitingFeedbackPlaying) {
        self.settings = settings
        self.frames = frames
        self.ask = ask
        self.speech = speech
        self.feedback = feedback
    }

    // MARK: - Freeze

    func capture() {
        guard phase == .live else { return }
        freeze()
    }

    func release() {
        cancelRun()
        speech.stop()
        feedback.stop()
        frozenImage = nil
        phase = .live
    }

    @discardableResult
    private func freeze() -> Bool {
        guard let image = frames.latestFrame() else { return false }
        frozenImage = image
        phase = .frozen
        return true
    }

    // MARK: - Input

    func askTapped() {
        switch phase {
        case .live:
            guard freeze() else { return }
        case .frozen, .choosingInput, .typing, .failed:
            break
        case .listening, .asking, .awaitingCloudConsent, .answering:
            return
        }
        switch settings.inputMode {
        case .askEachTime: phase = .choosingInput
        case .voice: choose(.voice)
        case .text: choose(.text)
        }
    }

    func choose(_ kind: InputKind) {
        guard frozenImage != nil else { return }
        cancelRun()
        switch kind {
        case .text:
            phase = .typing
        case .voice:
            phase = .listening(transcript: "")
            listen()
        }
    }

    func stopListening() {
        guard case .listening = phase else { return }
        speech.stop()
    }

    private func listen() {
        let run = generation
        let stream = speech.transcribe()
        task = Task { [weak self] in
            var transcript = ""
            do {
                for try await text in stream {
                    guard let self, self.generation == run else { return }
                    transcript = text
                    self.phase = .listening(transcript: text)
                }
                guard let self, self.generation == run else { return }
                self.submit(question: transcript)
            } catch {
                guard let self, self.generation == run else { return }
                self.phase = .failed(question: transcript, message: error.localizedDescription)
            }
        }
    }

    // MARK: - Asking

    func submit(question: String) {
        guard frozenImage != nil else { return }
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            cancelRun()
            phase = .frozen
            return
        }
        switch ask.availability {
        case .available: runAsk(trimmed, route: .onDevice, notice: nil)
        case .notReady: runAsk(trimmed, route: .vision, notice: Self.notReadyNotice)
        case .unavailable: runAsk(trimmed, route: .vision, notice: nil)
        }
    }

    func respondToCloudConsent(send: Bool) {
        guard case .awaitingCloudConsent(let question) = phase else { return }
        runAsk(question, route: send ? .cloud : .vision, notice: nil)
    }

    func dismissAnswer() {
        switch phase {
        case .answering, .failed:
            cancelRun()
            feedback.stop()
            phase = .frozen
        default:
            break
        }
    }

    private func runAsk(_ question: String, route: AskRoute, notice: String?) {
        guard let frame = currentFrozenFrame() else { return }
        cancelRun()
        let run = generation
        phase = .asking(question: question)
        feedback.start(interval: settings.waitInterval)
        let stream = ask.answer(question, frame: frame, route: route)

        task = Task { [weak self] in
            var answer: String?
            do {
                for try await update in stream {
                    guard let self, self.generation == run else { return }
                    switch update {
                    case .partial(let text):
                        guard !text.isEmpty else { continue }
                        if answer == nil { self.feedback.stop() }
                        answer = text
                        self.phase = .answering(question: question, answer: text, notice: notice, isComplete: false)
                    case .needsCloud:
                        self.feedback.stop()
                        self.phase = .awaitingCloudConsent(question: question)
                        return
                    }
                }
                guard let self, self.generation == run else { return }
                if let answer {
                    self.phase = .answering(question: question, answer: answer, notice: notice, isComplete: true)
                } else {
                    self.feedback.stop()
                    self.phase = .failed(question: question, message: Self.noAnswerMessage)
                }
            } catch {
                guard let self, self.generation == run else { return }
                self.feedback.stop()
                self.phase = .failed(question: question, message: error.localizedDescription)
            }
        }
    }

    private func currentFrozenFrame() -> FrozenFrame? {
        guard let image = frozenImage else { return nil }
        let extent = image.extent
        let visible = FrameCropper.visibleRect(imageSize: extent.size, viewSize: viewSize, obscuredBottom: obscuredBottom)
        return FrozenFrame(image: image, visibleRect: visible ?? extent)
    }

    /// Supersedes the current run: its task is cancelled and any late updates are dropped.
    private func cancelRun() {
        generation += 1
        task?.cancel()
        task = nil
    }
}
