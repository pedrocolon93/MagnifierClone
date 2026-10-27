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

/// Which instructions the model answers with, from Settings.
nonisolated enum AnswerStyle: String, CaseIterable, Sendable {
    /// The model as is, like round 1 of the prototype's user testing.
    case standard
    /// Answers that also cover the details that matter, where things are, and what to do next (round 2).
    case accessibility
}

protocol AskServicing: AnyObject {
    var availability: ModelAvailability { get }
    /// `history` holds earlier answered turns about the same frame, oldest first, for follow-up context.
    func answer(_ question: String, frame: FrozenFrame, route: AskRoute, history: [AskTurn], style: AnswerStyle) -> AsyncThrowingStream<AskUpdate, Error>
}

protocol SpeechServicing: AnyObject {
    /// Cumulative transcript; finishes on silence or `stop()`.
    func transcribe() -> AsyncThrowingStream<String, Error>
    func stop()
}

/// How the waiting feedback behaves, from Settings.
nonisolated struct WaitingCue: Equatable, Sendable {
    /// Seconds between dings.
    var interval: Double
    /// Seconds after waiting begins before the first ding.
    var delay: Double = 0
    /// Sound to play; nil plays none.
    var soundURL: URL? = WaitingCue.defaultSoundURL
    var vibrates = true

    /// The "Ding": the DirectionUp sound that ships with iOS, found in the system sounds folder.
    /// Nil if it isn't there, in which case only the haptic plays.
    static let defaultSoundURL: URL? = SystemSounds.all()
        .first { $0.url.deletingPathExtension().lastPathComponent.localizedStandardContains("DirectionUp") }?.url
}

protocol WaitingFeedbackPlaying: AnyObject {
    func start(_ cue: WaitingCue)
    func stop()
}
