import CoreGraphics
import CoreImage
import Foundation
@testable import MagnifierClone

final class FakeFrames: FrameSource {
    var frame: CIImage?

    init(frame: CIImage? = nil) { self.frame = frame }

    func latestFrame() -> CIImage? { frame }
}

final class FakeAsk: AskServicing {
    var availability: ModelAvailability = .available
    private(set) var calls: [(question: String, route: AskRoute)] = []
    private(set) var frames: [FrozenFrame] = []
    /// One continuation per `answer` call, in call order.
    private(set) var continuations: [AsyncThrowingStream<AskUpdate, Error>.Continuation] = []

    var continuation: AsyncThrowingStream<AskUpdate, Error>.Continuation? { continuations.last }

    func answer(_ question: String, frame: FrozenFrame, route: AskRoute) -> AsyncThrowingStream<AskUpdate, Error> {
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: AskUpdate.self, throwing: Error.self)
        calls.append((question, route))
        frames.append(frame)
        continuations.append(continuation)
        return stream
    }
}

final class FakeSpeech: SpeechServicing {
    private(set) var stopCount = 0
    private(set) var transcribeCount = 0
    private(set) var continuation: AsyncThrowingStream<String, Error>.Continuation?

    func transcribe() -> AsyncThrowingStream<String, Error> {
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: String.self, throwing: Error.self)
        transcribeCount += 1
        self.continuation = continuation
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
    private(set) var lastInterval: Double?
    private(set) var isRunning = false

    func start(interval: Double) {
        startCount += 1
        lastInterval = interval
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
