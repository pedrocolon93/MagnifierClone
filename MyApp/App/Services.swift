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

protocol AskServicing: AnyObject {
    var availability: ModelAvailability { get }
    func answer(_ question: String, frame: FrozenFrame, route: AskRoute) -> AsyncThrowingStream<AskUpdate, Error>
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
