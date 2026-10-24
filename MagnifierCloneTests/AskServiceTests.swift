import CoreImage
import FoundationModels
import Testing
import UIKit
@testable import MagnifierClone

struct AskServiceTests {
    @Test func mapAvailabilityCases() {
        #expect(AskService.mapAvailability(.available) == .available)
        #expect(AskService.mapAvailability(.unavailable(.modelNotReady)) == .notReady)
        #expect(AskService.mapAvailability(.unavailable(.deviceNotEligible)) == .unavailable)
        #expect(AskService.mapAvailability(.unavailable(.appleIntelligenceNotEnabled)) == .unavailable)
    }

    @Test func escalatesOnContextWindowError() {
        let error = LanguageModelError.contextSizeExceeded(.init(contextSize: 4096, tokenCount: 5000, debugDescription: "too long"))
        #expect(AskService.shouldEscalate(error))
    }

    @Test func doesNotEscalateOnCancellation() {
        #expect(!AskService.shouldEscalate(CancellationError()))
    }

    @Test func doesNotEscalateOnGuardrail() {
        let error = LanguageModelError.guardrailViolation(.init(debugDescription: "blocked"))
        #expect(!AskService.shouldEscalate(error))
    }

    @Test func escalationAsksForCloudOnlyWhenCloudEnabled() {
        let error = LanguageModelError.contextSizeExceeded(.init(contextSize: 4096, tokenCount: 5000, debugDescription: "too long"))
        #expect(AskService.onDeviceFailureAction(for: error, cloudEnabled: true) == .askForCloud)
        #expect(AskService.onDeviceFailureAction(for: error, cloudEnabled: false) == .useVision)
    }

    @Test(arguments: [true, false])
    func guardrailFallsBackToVision(cloudEnabled: Bool) {
        let error = LanguageModelError.guardrailViolation(.init(debugDescription: "blocked"))
        #expect(AskService.onDeviceFailureAction(for: error, cloudEnabled: cloudEnabled) == .useVision)
    }

    @Test(arguments: [true, false])
    func otherErrorsFail(cloudEnabled: Bool) {
        #expect(AskService.onDeviceFailureAction(for: CancellationError(), cloudEnabled: cloudEnabled) == .fail)
        #expect(AskService.onDeviceFailureAction(for: FakeError(), cloudEnabled: cloudEnabled) == .fail)
    }

    @Test func visionFallbackReadsText() async throws {
        let image = Self.render(text: "HELLO 42")
        let result = try await VisionFallback.describe(image)
        #expect(result.contains("HELLO"))
    }

    @Test func visionFallbackKeepsLineBreaks() async throws {
        let image = Self.render(text: "HELLO\nWORLD", at: CGPoint(x: 40, y: 30))
        let result = try await VisionFallback.describe(image)
        #expect(result.contains("HELLO\nWORLD"))
    }

    @Test func visionFallbackEmptyImageMessage() async throws {
        let image = Self.render(text: nil)
        let result = try await VisionFallback.describe(image)
        #expect(!result.contains("Text:"))
    }

    private static func render(text: String?, at origin: CGPoint = CGPoint(x: 40, y: 120)) -> CIImage {
        let size = CGSize(width: 1000, height: 400)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let uiImage = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            if let text {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 120),
                    .foregroundColor: UIColor.black,
                ]
                (text as NSString).draw(at: origin, withAttributes: attributes)
            }
        }
        return CIImage(cgImage: uiImage.cgImage!)
    }
}
