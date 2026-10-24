import CoreImage
import CoreML
import Vision

/// Describes an image with Vision alone, for when no language model can answer.
nonisolated enum VisionFallback {
    static let emptyMessage = "I couldn't find any text or recognizable objects."
    static let minimumConfidence: Float = 0.3
    static let maximumLabels = 3

    /// `"Text: …"` and/or `"Looks like: …"` lines, or `emptyMessage` when Vision finds neither.
    static func describe(_ image: CIImage) async throws -> String {
        var textRequest = RecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        useCPUInSimulator(&textRequest)
        let textObservations = try await textRequest.perform(on: image)
        let text = textObservations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var classifyRequest = ClassifyImageRequest()
        useCPUInSimulator(&classifyRequest)
        let classifications = try await classifyRequest.perform(on: image)
        let labels = classifications
            .filter { $0.confidence >= minimumConfidence }
            .sorted { $0.confidence > $1.confidence }
            .prefix(maximumLabels)
            .map(\.identifier)

        var lines: [String] = []
        if !text.isEmpty { lines.append("Text: \(text)") }
        if !labels.isEmpty { lines.append("Looks like: \(labels.joined(separator: ", "))") }
        return lines.isEmpty ? emptyMessage : lines.joined(separator: "\n")
    }

    /// The simulator can't create Vision's neural-engine/GPU contexts ("Failed to create espresso
    /// context"), so requests run on the CPU there. Devices keep Vision's default compute devices.
    private static func useCPUInSimulator(_ request: inout some ImageProcessingRequest) {
        #if targetEnvironment(simulator)
        for (stage, devices) in request.supportedComputeStageDevices {
            let cpu = devices.first { if case .cpu = $0 { true } else { false } }
            request.setComputeDevice(cpu, for: stage)
        }
        #endif
    }
}
