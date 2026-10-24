import CoreImage
import Foundation
import FoundationModels
import Vision

/// Answers questions about a frozen frame: on-device Foundation Models first, Private Cloud Compute
/// only when asked for the `.cloud` route (after the user consents), and Vision as the fallback.
final class AskService: AskServicing {
    static let instructions = "You help a person with low vision understand what their camera shows. Answer concisely."

    /// Whether the Private Cloud Compute route may be used. PCC requires Apple's managed
    /// entitlement; without it, construct with `false` so the on-device route never asks for the cloud.
    private let cloudEnabled: Bool

    init(cloudEnabled: Bool = true) {
        self.cloudEnabled = cloudEnabled
    }

    var availability: ModelAvailability {
        Self.mapAvailability(SystemLanguageModel.default.availability)
    }

    func answer(_ question: String, frame: FrozenFrame, route: AskRoute) -> AsyncThrowingStream<AskUpdate, Error> {
        let cloudEnabled = cloudEnabled
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
        } catch where cloudEnabled && shouldEscalate(error) {
            continuation.yield(.needsCloud)
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
