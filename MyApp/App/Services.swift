import CoreImage
import Foundation

/// Supplies the most recent upright camera frame.
protocol FrameSource: AnyObject {
    func latestFrame() -> CIImage?
}

nonisolated enum ModelAvailability: Equatable, Sendable {
    case available, notReady, unavailable
}

nonisolated enum AskRoute: Equatable, Sendable {
    case onDevice, cloud, vision
}

nonisolated enum AskUpdate: Equatable, Sendable {
    /// Cumulative answer text so far.
    case partial(String)
    /// The on-device model can't answer; the user must consent before using Private Cloud Compute.
    case needsCloud
    /// A short note to show with the answer, e.g. why a fallback answered instead. Applies until the stream ends.
    case notice(String)
}

/// One finished question about a frozen frame, shown in the answer transcript.
nonisolated struct AskTurn: Equatable, Sendable {
    let question: String
    /// The answer, or the error message when `isError`.
    let answer: String
    let notice: String?
    let isError: Bool
}

protocol AskServicing: AnyObject {
    var availability: ModelAvailability { get }
    /// `history` holds earlier answered turns about the same frame, oldest first, for follow-up context.
    func answer(_ question: String, frame: FrozenFrame, route: AskRoute, history: [AskTurn]) -> AsyncThrowingStream<AskUpdate, Error>
}

protocol SpeechServicing: AnyObject {
    /// Cumulative transcript; finishes on silence or `stop()`.
    func transcribe() -> AsyncThrowingStream<String, Error>
    func stop()
}

protocol WaitingFeedbackPlaying: AnyObject {
    func start(interval: Double)
    func stop()
}
