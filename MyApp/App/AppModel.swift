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
    /// Whether this model currently has a transcription or the waiting feedback running.
    @ObservationIgnored private var isListening = false
    @ObservationIgnored private var isFeedbackRunning = false

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
        isListening = false
        isFeedbackRunning = false
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
        switch phase {
        case .frozen, .choosingInput, .typing, .failed:
            break
        case .live, .listening, .asking, .awaitingCloudConsent, .answering:
            return
        }
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
        isListening = true
        task = Task { [weak self] in
            var transcript = ""
            do {
                for try await text in stream {
                    guard let self, self.generation == run else { return }
                    transcript = text
                    self.phase = .listening(transcript: text)
                }
                guard let self, self.generation == run else { return }
                self.isListening = false
                self.submit(question: transcript)
            } catch {
                guard let self, self.generation == run else { return }
                self.isListening = false
                let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    // Nothing was heard (e.g. permission denied): show why, don't ask.
                    self.cancelRun()
                }
                self.phase = .failed(question: trimmed, message: error.localizedDescription)
            }
        }
    }

    // MARK: - Asking

    func submit(question: String) {
        switch phase {
        case .typing, .listening:
            break
        default:
            return
        }
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
        startFeedback()
        let stream = ask.answer(question, frame: frame, route: route)

        task = Task { [weak self] in
            var answer: String?
            var notice = notice
            do {
                for try await update in stream {
                    guard let self, self.generation == run else { return }
                    switch update {
                    case .partial(let text):
                        guard !text.isEmpty else { continue }
                        self.stopFeedback()
                        answer = text
                        self.phase = .answering(question: question, answer: text, notice: notice, isComplete: false)
                    case .needsCloud:
                        self.stopFeedback()
                        self.phase = .awaitingCloudConsent(question: question)
                        return
                    case .notice(let text):
                        notice = text
                        if case .answering(_, let current, _, let isComplete) = self.phase {
                            self.phase = .answering(question: question, answer: current, notice: text, isComplete: isComplete)
                        }
                    }
                }
                guard let self, self.generation == run else { return }
                if let answer {
                    self.phase = .answering(question: question, answer: answer, notice: notice, isComplete: true)
                } else {
                    self.stopFeedback()
                    self.phase = .failed(question: question, message: Self.noAnswerMessage)
                }
            } catch {
                guard let self, self.generation == run else { return }
                self.stopFeedback()
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

    /// Supersedes the current run: its task is cancelled, any late updates are dropped,
    /// and transcription and waiting feedback it started are stopped.
    private func cancelRun() {
        generation += 1
        task?.cancel()
        task = nil
        if isListening {
            isListening = false
            speech.stop()
        }
        stopFeedback()
    }

    private func startFeedback() {
        isFeedbackRunning = true
        feedback.start(interval: settings.waitInterval)
    }

    private func stopFeedback() {
        guard isFeedbackRunning else { return }
        isFeedbackRunning = false
        feedback.stop()
    }
}
