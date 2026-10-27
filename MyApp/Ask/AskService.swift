import CoreImage
import Foundation
import FoundationModels
import Vision

/// Answers questions about a frozen frame: on-device Foundation Models first, Private Cloud Compute
/// only when asked for the `.cloud` route (after the user consents), and Vision as the fallback.
final class AskService: AskServicing {
    static let instructions = "You help a person with low vision understand what their camera shows. Answer concisely."
    static let fallbackNotice = "Apple Intelligence couldn't answer this one, so here's what the camera can read."

    /// Whether the Private Cloud Compute route may be used. PCC requires Apple's managed
    /// entitlement; without it, construct with `false` so the on-device route never asks for the cloud.
    private let cloudEnabled: Bool

    init(cloudEnabled: Bool = true) {
        self.cloudEnabled = cloudEnabled
    }

    var availability: ModelAvailability {
        Self.mapAvailability(SystemLanguageModel.default.availability)
    }

    func answer(_ question: String, frame: FrozenFrame, route: AskRoute, history: [AskTurn]) -> AsyncThrowingStream<AskUpdate, Error> {
        let cloudEnabled = cloudEnabled
        let question = Self.prompt(question, history: history)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    switch route {
                    case .onDevice:
                        try await Self.answerOnDevice(question, frame: frame, cloudEnabled: cloudEnabled, into: continuation)
                    case .cloud where cloudEnabled:
                        try await Self.answerInCloud(question, frame: frame, into: continuation)
                    case .cloud, .vision:
                        let description = try await VisionFallback.describe(FrameCropper.croppedImage(frame))
                        continuation.yield(.partial(description))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            // The consumer cancels its task on release/dismiss; stop the model or Vision work with it.
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Each question gets a fresh session, so earlier turns about the same frame ride along in the prompt.
    static func prompt(_ question: String, history: [AskTurn]) -> String {
        guard !history.isEmpty else { return question }
        let earlier = history
            .map { "Question: \($0.question)\nAnswer: \($0.answer)" }
            .joined(separator: "\n\n")
        return "Earlier questions about this same image:\n\n\(earlier)\n\nNew question: \(question)"
    }

    // MARK: - Routes

    private static func answerOnDevice(
        _ question: String, frame: FrozenFrame, cloudEnabled: Bool,
        into continuation: AsyncThrowingStream<AskUpdate, Error>.Continuation
    ) async throws {
        let session = LanguageModelSession(tools: tools(), instructions: instructions)
        let image = FrameCropper.croppedImage(frame)
        do {
            let stream = session.streamResponse {
                question
                Attachment(image).label("frame")
            }
            for try await snapshot in stream {
                continuation.yield(.partial(snapshot.content))
            }
        } catch {
            switch onDeviceFailureAction(for: error, cloudEnabled: cloudEnabled) {
            case .askForCloud:
                continuation.yield(.needsCloud)
            case .useVision:
                continuation.yield(.notice(fallbackNotice))
                continuation.yield(.partial(try await VisionFallback.describe(image)))
            case .fail:
                throw error
            }
        }
    }

    private static func answerInCloud(
        _ question: String, frame: FrozenFrame,
        into continuation: AsyncThrowingStream<AskUpdate, Error>.Continuation
    ) async throws {
        let url = try FrameCropper.cloudJPEG(frame)
        defer { try? FileManager.default.removeItem(at: url) }
        let session = LanguageModelSession(model: PrivateCloudComputeLanguageModel(), tools: tools(), instructions: instructions)
        let stream = session.streamResponse {
            question
            Attachment(imageURL: url).label("frame")
        }
        for try await snapshot in stream {
            continuation.yield(.partial(snapshot.content))
        }
    }

    /// Vision's `OCRTool` comes from the Vision + FoundationModels cross-import overlay, which the
    /// iOS Simulator SDK doesn't ship; the simulator build runs without it.
    private static func tools() -> [any Tool] {
        #if canImport(_Vision_FoundationModels)
        return [OCRTool()]
        #else
        return []
        #endif
    }

    // MARK: - Policy

    nonisolated enum OnDeviceFailureAction: Equatable, Sendable {
        /// Ask the user to consent to Private Cloud Compute.
        case askForCloud
        /// Answer with Vision instead, with `fallbackNotice`.
        case useVision
        /// Surface the error.
        case fail
    }

    /// What to do when the on-device model fails: a larger model could help with escalation errors
    /// (only offered when the cloud route is enabled); a guardrail refusal won't change with a larger
    /// model, so it and escalation errors without the cloud get the Vision result rather than raw error text.
    static func onDeviceFailureAction(for error: Error, cloudEnabled: Bool) -> OnDeviceFailureAction {
        if isGuardrailViolation(error) { return .useVision }
        if shouldEscalate(error) { return cloudEnabled ? .askForCloud : .useVision }
        return .fail
    }

    static func isGuardrailViolation(_ error: Error) -> Bool {
        guard let error = error as? LanguageModelError, case .guardrailViolation = error else { return false }
        return true
    }

    static func mapAvailability(_ availability: SystemLanguageModel.Availability) -> ModelAvailability {
        switch availability {
        case .available: .available
        case .unavailable(.modelNotReady): .notReady
        case .unavailable: .unavailable
        }
    }

    /// Whether the error means the on-device model can't handle this request but a larger model could.
    /// Apps built with Xcode 27 receive `LanguageModelError` (it replaces the deprecated
    /// `LanguageModelSession.GenerationError`, whose `exceededContextWindowSize` is now `contextSizeExceeded`).
    static func shouldEscalate(_ error: Error) -> Bool {
        guard let error = error as? LanguageModelError else { return false }
        switch error {
        case .contextSizeExceeded, .unsupportedCapability, .unsupportedLanguageOrLocale: return true
        default: return false
        }
    }
}
