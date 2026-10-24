import CoreGraphics
import CoreImage
import Foundation
import Testing
@testable import MagnifierClone

@MainActor
struct AppModelTests {
    let settings: AppSettings
    let frames = FakeFrames(frame: CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 1080, height: 1920)))
    let ask = FakeAsk()
    let speech = FakeSpeech()
    let feedback = FakeFeedback()
    let model: AppModel

    init() {
        settings = AppSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        model = AppModel(settings: settings, frames: frames, ask: ask, speech: speech, feedback: feedback)
    }

    // MARK: - Helpers

    /// Polls `condition` (yielding to let model tasks run) for up to 1 s.
    @discardableResult
    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(1)
        while !condition() {
            if ContinuousClock.now >= deadline { return false }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(1))
        }
        return true
    }

    /// Gives model tasks a chance to process anything already delivered (for "nothing happens" checks).
    private func settle() async {
        for _ in 0..<20 {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    /// Freezes and submits a typed question, leaving the model in `.asking`.
    private func startTypedAsk(_ question: String = "what is this") {
        settings.inputMode = .text
        model.askTapped()
        model.submit(question: question)
    }

    // MARK: - Freeze

    @Test func captureFreezesAndReleaseReturnsLive() {
        #expect(model.phase == .live)
        #expect(!model.isFrozen)
        model.capture()
        #expect(model.phase == .frozen)
        #expect(model.isFrozen)
        #expect(model.frozenImage != nil)
        model.release()
        #expect(model.phase == .live)
        #expect(model.frozenImage == nil)
    }

    @Test func captureWithoutFrameStaysLive() {
        frames.frame = nil
        model.capture()
        #expect(model.phase == .live)
        #expect(model.frozenImage == nil)
        model.askTapped()
        #expect(model.phase == .live)
    }

    // MARK: - Input choice

    @Test func askTappedAskEachTimeShowsChooser() {
        settings.inputMode = .askEachTime
        model.askTapped()
        #expect(model.phase == .choosingInput)
        #expect(model.frozenImage != nil)
    }

    @Test func askTappedVoiceModeStartsListening() {
        settings.inputMode = .voice
        model.askTapped()
        #expect(model.phase == .listening(transcript: ""))
        #expect(speech.transcribeCount == 1)
    }

    @Test func askTappedTextModeStartsTyping() {
        settings.inputMode = .text
        model.askTapped()
        #expect(model.phase == .typing)
    }

    @Test func voiceTranscriptStreamsThenSubmitsOnFinish() async throws {
        settings.inputMode = .voice
        model.askTapped()
        let speechStream = try #require(speech.continuation)
        speechStream.yield("what")
        speechStream.yield("what is this")
        #expect(await waitUntil { model.phase == .listening(transcript: "what is this") })
        speechStream.finish()
        #expect(await waitUntil { model.phase == .asking(question: "what is this") })
        #expect(ask.calls.count == 1)
        #expect(ask.calls.first?.question == "what is this")
        #expect(ask.calls.first?.route == .onDevice)
    }

    @Test func stopListeningSubmitsTranscript() async throws {
        settings.inputMode = .voice
        model.askTapped()
        try #require(speech.continuation).yield("read this")
        #expect(await waitUntil { model.phase == .listening(transcript: "read this") })
        model.stopListening()
        #expect(speech.stopCount == 1)
        #expect(await waitUntil { model.phase == .asking(question: "read this") })
    }

    @Test func emptyQuestionReturnsToFrozen() async throws {
        startTypedAsk("   ")
        #expect(model.phase == .frozen)
        #expect(ask.calls.isEmpty)
        #expect(feedback.startCount == 0)

        settings.inputMode = .voice
        model.askTapped()
        let speechStream = try #require(speech.continuation)
        speechStream.yield("")
        speechStream.finish()
        #expect(await waitUntil { model.phase == .frozen })
        #expect(ask.calls.isEmpty)
        #expect(feedback.startCount == 0)
    }

    // MARK: - Asking

    @Test func askingStartsFeedbackWithSettingsInterval() {
        settings.waitInterval = 2.0
        startTypedAsk()
        #expect(model.phase == .asking(question: "what is this"))
        #expect(feedback.startCount == 1)
        #expect(feedback.lastInterval == 2.0)
        #expect(feedback.isRunning)
    }

    @Test func askReceivesVisibleRegionOfFrozenFrame() throws {
        model.viewSize = CGSize(width: 390, height: 844)
        model.obscuredBottom = 300
        startTypedAsk()
        let frame = try #require(ask.frames.first)
        let expected = try #require(FrameCropper.visibleRect(
            imageSize: CGSize(width: 1080, height: 1920), viewSize: model.viewSize, obscuredBottom: 300))
        #expect(frame.visibleRect == expected)
        #expect(frame.image.extent == model.frozenImage?.extent)
    }

    @Test func askFallsBackToFullExtentWithoutLayout() throws {
        startTypedAsk()
        let frame = try #require(ask.frames.first)
        #expect(frame.visibleRect == CGRect(x: 0, y: 0, width: 1080, height: 1920))
    }

    @Test func firstPartialStopsFeedbackAndShowsAnswer() async throws {
        startTypedAsk()
        let stream = try #require(ask.continuation)
        stream.yield(.partial("It is"))
        #expect(await waitUntil {
            model.phase == .answering(question: "what is this", answer: "It is", notice: nil, isComplete: false)
        })
        #expect(!feedback.isRunning)
        #expect(feedback.stopCount == 1)
        stream.yield(.partial("It is a mug"))
        #expect(await waitUntil {
            model.phase == .answering(question: "what is this", answer: "It is a mug", notice: nil, isComplete: false)
        })
        #expect(feedback.stopCount == 1)
    }

    @Test func streamEndMarksComplete() async throws {
        startTypedAsk()
        let stream = try #require(ask.continuation)
        stream.yield(.partial("A mug"))
        stream.finish()
        #expect(await waitUntil {
            model.phase == .answering(question: "what is this", answer: "A mug", notice: nil, isComplete: true)
        })
    }

    @Test func needsCloudPromptsAndSendUsesCloudRoute() async throws {
        startTypedAsk()
        try #require(ask.continuation).yield(.needsCloud)
        #expect(await waitUntil { model.phase == .awaitingCloudConsent(question: "what is this") })
        #expect(!feedback.isRunning)
        model.respondToCloudConsent(send: true)
        #expect(model.phase == .asking(question: "what is this"))
        #expect(feedback.isRunning)
        #expect(feedback.startCount == 2)
        #expect(ask.calls.map(\.route) == [.onDevice, .cloud])

        let cloud = try #require(ask.continuation)
        cloud.yield(.partial("From the cloud"))
        cloud.finish()
        #expect(await waitUntil {
            model.phase == .answering(question: "what is this", answer: "From the cloud", notice: nil, isComplete: true)
        })
    }

    @Test func declineCloudUsesVisionRoute() async throws {
        startTypedAsk()
        try #require(ask.continuation).yield(.needsCloud)
        #expect(await waitUntil { model.phase == .awaitingCloudConsent(question: "what is this") })
        model.respondToCloudConsent(send: false)
        #expect(model.phase == .asking(question: "what is this"))
        #expect(feedback.isRunning)
        #expect(ask.calls.map(\.route) == [.onDevice, .vision])
    }

    @Test func notReadyUsesVisionWithNotice() async throws {
        ask.availability = .notReady
        startTypedAsk()
        #expect(ask.calls.first?.route == .vision)
        let stream = try #require(ask.continuation)
        stream.yield(.partial("Text: Hello"))
        stream.finish()
        #expect(await waitUntil {
            model.phase == .answering(question: "what is this", answer: "Text: Hello",
                                      notice: "Apple Intelligence is still getting ready", isComplete: true)
        })
    }

    @Test func unavailableUsesVisionWithoutNotice() async throws {
        ask.availability = .unavailable
        startTypedAsk()
        #expect(ask.calls.first?.route == .vision)
        try #require(ask.continuation).yield(.partial("Text: Hello"))
        #expect(await waitUntil {
            model.phase == .answering(question: "what is this", answer: "Text: Hello", notice: nil, isComplete: false)
        })
    }

    @Test func askErrorShowsFailureAndStopsFeedback() async throws {
        startTypedAsk()
        try #require(ask.continuation).finish(throwing: FakeError())
        #expect(await waitUntil { model.phase == .failed(question: "what is this", message: "The model failed") })
        #expect(!feedback.isRunning)
    }

    @Test func askErrorAfterPartialShowsFailure() async throws {
        startTypedAsk()
        let stream = try #require(ask.continuation)
        stream.yield(.partial("It is"))
        #expect(await waitUntil {
            model.phase == .answering(question: "what is this", answer: "It is", notice: nil, isComplete: false)
        })
        stream.finish(throwing: FakeError())
        #expect(await waitUntil { model.phase == .failed(question: "what is this", message: "The model failed") })
        #expect(!feedback.isRunning)
        #expect(feedback.startCount == 1)
        model.dismissAnswer()
        #expect(model.phase == .frozen)
    }

    @Test func speechErrorWithTranscriptShowsFailure() async throws {
        settings.inputMode = .voice
        model.askTapped()
        let speechStream = try #require(speech.continuation)
        speechStream.yield("what is")
        #expect(await waitUntil { model.phase == .listening(transcript: "what is") })
        speechStream.finish(throwing: FakeError())
        #expect(await waitUntil { model.phase == .failed(question: "what is", message: "The model failed") })
        #expect(ask.calls.isEmpty)
    }

    @Test func speechErrorWithEmptyTranscriptReturnsToFrozen() async throws {
        settings.inputMode = .voice
        model.askTapped()
        try #require(speech.continuation).finish(throwing: FakeError())
        #expect(await waitUntil { model.phase == .frozen })
        #expect(model.frozenImage != nil)
        #expect(ask.calls.isEmpty)
        #expect(feedback.startCount == 0)
    }

    // MARK: - Guards

    @Test func submitWhileAskingIsIgnored() async throws {
        startTypedAsk()
        model.submit(question: "again")
        #expect(model.phase == .asking(question: "what is this"))
        #expect(ask.calls.count == 1)
        #expect(feedback.startCount == 1)

        try #require(ask.continuation).yield(.partial("A mug"))
        #expect(await waitUntil {
            if case .answering = model.phase { return true } else { return false }
        })
        model.submit(question: "again")
        #expect(model.phase == .answering(question: "what is this", answer: "A mug", notice: nil, isComplete: false))
        #expect(ask.calls.count == 1)
        #expect(feedback.startCount == 1)
    }

    @Test func submitWhileFrozenIsIgnored() {
        model.capture()
        model.submit(question: "what is this")
        #expect(model.phase == .frozen)
        #expect(ask.calls.isEmpty)
    }

    @Test func chooseWhileAskingIsIgnored() async throws {
        startTypedAsk()
        model.choose(.voice)
        model.choose(.text)
        #expect(model.phase == .asking(question: "what is this"))
        #expect(feedback.isRunning)
        #expect(speech.transcribeCount == 0)
        await settle()
        #expect(ask.terminations.first?.outcome == nil)
    }

    @Test func chooseWhileListeningIsIgnored() {
        settings.inputMode = .voice
        model.askTapped()
        model.choose(.voice)
        model.choose(.text)
        #expect(model.phase == .listening(transcript: ""))
        #expect(speech.transcribeCount == 1)
    }

    @Test func choosingTextFromChooserDoesNotTouchSpeech() {
        model.askTapped()
        #expect(model.phase == .choosingInput)
        model.choose(.text)
        #expect(model.phase == .typing)
        #expect(speech.stopCount == 0)
    }

    // MARK: - Dismiss / release

    @Test func dismissAnswerReturnsToFrozen() async throws {
        startTypedAsk()
        let first = try #require(ask.continuation)
        first.yield(.partial("A mug"))
        first.finish()
        #expect(await waitUntil {
            if case .answering = model.phase { return true } else { return false }
        })
        model.dismissAnswer()
        #expect(model.phase == .frozen)
        #expect(model.frozenImage != nil)

        model.askTapped()
        model.submit(question: "again")
        try #require(ask.continuation).finish(throwing: FakeError())
        #expect(await waitUntil { model.phase == .failed(question: "again", message: "The model failed") })
        model.dismissAnswer()
        #expect(model.phase == .frozen)
    }

    @Test func releaseWhileAskingCancelsAndStopsFeedback() async throws {
        startTypedAsk()
        #expect(feedback.isRunning)
        model.release()
        #expect(model.phase == .live)
        #expect(model.frozenImage == nil)
        #expect(!feedback.isRunning)

        settings.inputMode = .voice
        model.askTapped()
        #expect(model.phase == .listening(transcript: ""))
        let before = speech.stopCount
        model.release()
        #expect(model.phase == .live)
        #expect(speech.stopCount >= before + 1)
        await settle()
        #expect(model.phase == .live)
        #expect(ask.calls.count == 1)
    }

    @Test func releaseCancelsAskStream() async throws {
        startTypedAsk()
        let probe = try #require(ask.terminations.first)
        #expect(probe.outcome == nil)
        model.release()
        #expect(await waitUntil { probe.outcome == .cancelled })
    }

    @Test func releaseCancelsSpeechStream() async throws {
        settings.inputMode = .voice
        model.askTapped()
        let probe = try #require(speech.termination)
        try #require(speech.continuation).yield("what")
        #expect(await waitUntil { model.phase == .listening(transcript: "what") })
        #expect(probe.outcome == nil)
        model.release()
        #expect(await waitUntil { probe.outcome == .cancelled })
    }

    @Test func lateUpdatesAfterReleaseAreIgnored() async throws {
        startTypedAsk()
        let old = try #require(ask.continuation)
        model.release()
        old.yield(.partial("x"))
        old.finish()
        await settle()
        #expect(model.phase == .live)
    }

    @Test func lateUpdatesFromSupersededAskAreIgnored() async throws {
        startTypedAsk()
        let old = try #require(ask.continuation)
        model.release()
        startTypedAsk("second")
        old.yield(.partial("stale"))
        await settle()
        #expect(model.phase == .asking(question: "second"))
        try #require(ask.continuation).yield(.partial("fresh"))
        #expect(await waitUntil {
            model.phase == .answering(question: "second", answer: "fresh", notice: nil, isComplete: false)
        })
    }

    @Test func askTappedWhileAskingIsIgnored() async throws {
        startTypedAsk()
        model.askTapped()
        #expect(model.phase == .asking(question: "what is this"))
        #expect(ask.calls.count == 1)

        try #require(ask.continuation).yield(.partial("A mug"))
        #expect(await waitUntil {
            if case .answering = model.phase { return true } else { return false }
        })
        model.askTapped()
        #expect(model.phase == .answering(question: "what is this", answer: "A mug", notice: nil, isComplete: false))
    }
}
