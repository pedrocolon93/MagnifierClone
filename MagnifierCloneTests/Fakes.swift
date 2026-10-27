import CoreGraphics
import CoreImage
import Foundation
import Synchronization
@testable import MagnifierClone

final class FakeFrames: FrameSource {
    var frame: CIImage?

    init(frame: CIImage? = nil) { self.frame = frame }

    func latestFrame() -> CIImage? { frame }
}

/// Records how a fake's stream terminated; `onTermination` may fire off the main actor.
nonisolated final class TerminationProbe: Sendable {
    enum Outcome: Equatable, Sendable { case finished, cancelled }
    private let state = Mutex<Outcome?>(nil)

    var outcome: Outcome? { state.withLock { $0 } }

    func attach<T>(to continuation: AsyncThrowingStream<T, Error>.Continuation) {
        continuation.onTermination = { [self] termination in
            let outcome: Outcome
            if case .cancelled = termination { outcome = .cancelled } else { outcome = .finished }
            state.withLock { $0 = outcome }
        }
    }
}

final class FakeAsk: AskServicing {
    var availability: ModelAvailability = .available
    private(set) var calls: [(question: String, route: AskRoute)] = []
    private(set) var frames: [FrozenFrame] = []
    private(set) var histories: [[AskTurn]] = []
    /// One continuation per `answer` call, in call order.
    private(set) var continuations: [AsyncThrowingStream<AskUpdate, Error>.Continuation] = []

    /// One termination probe per `answer` call, in call order.
    private(set) var terminations: [TerminationProbe] = []

    var continuation: AsyncThrowingStream<AskUpdate, Error>.Continuation? { continuations.last }

    func answer(_ question: String, frame: FrozenFrame, route: AskRoute, history: [AskTurn]) -> AsyncThrowingStream<AskUpdate, Error> {
        histories.append(history)
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: AskUpdate.self, throwing: Error.self)
        calls.append((question, route))
        frames.append(frame)
        continuations.append(continuation)
        let probe = TerminationProbe()
        probe.attach(to: continuation)
        terminations.append(probe)
        return stream
    }
}

final class FakeSpeech: SpeechServicing {
    private(set) var stopCount = 0
    private(set) var transcribeCount = 0
    private(set) var continuation: AsyncThrowingStream<String, Error>.Continuation?
    private(set) var termination: TerminationProbe?

    func transcribe() -> AsyncThrowingStream<String, Error> {
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: String.self, throwing: Error.self)
        transcribeCount += 1
        self.continuation = continuation
        let probe = TerminationProbe()
        probe.attach(to: continuation)
        termination = probe
        return stream
    }

    /// Mirrors the real contract: stopping finishes the transcript stream.
    func stop() {
        stopCount += 1
        continuation?.finish()
    }
}

final class FakeFeedback: WaitingFeedbackPlaying {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var lastCue: WaitingCue?
    private(set) var isRunning = false

    var lastInterval: Double? { lastCue?.interval }

    func start(_ cue: WaitingCue) {
        startCount += 1
        lastCue = cue
        isRunning = true
    }

    func stop() {
        stopCount += 1
        isRunning = false
    }
}

struct FakeError: LocalizedError {
    var errorDescription: String? { "The model failed" }
}
