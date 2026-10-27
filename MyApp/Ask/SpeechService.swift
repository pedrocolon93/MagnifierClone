import AVFoundation
import Foundation
import OSLog
import Speech

nonisolated enum SpeechServiceError: LocalizedError, Equatable {
    case permissionDenied
    case unsupportedLanguage
    case audioUnavailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Voice questions need microphone and speech recognition access. Enable the microphone for this app in Settings."
        case .unsupportedLanguage:
            "On-device dictation isn't available for your language."
        case .audioUnavailable:
            "The microphone stopped working. Try asking again."
        }
    }
}

/// On-device dictation with `SpeechAnalyzer` + `SpeechTranscriber`, fed from the microphone.
final class SpeechService: SpeechServicing {
    private let silenceTimeout: Duration
    private var session: DictationSession?

    init(silenceTimeout: Duration = .seconds(1.5)) {
        self.silenceTimeout = silenceTimeout
    }

    func transcribe() -> AsyncThrowingStream<String, Error> {
        session?.finish()
        let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream()
        let session = DictationSession(continuation: continuation, silenceTimeout: silenceTimeout)
        self.session = session
        // Consumer cancellation (or any termination) stops the engine and analyzer.
        continuation.onTermination = { _ in
            Task { @MainActor in session.tearDown() }
        }
        session.start()
        return stream
    }

    /// Finishes the current transcription normally so its transcript gets submitted. Harmless when idle.
    func stop() {
        session?.finish()
        session = nil
    }
}

/// One recording: permissions, assets, audio engine, analyzer, and the finish timers.
private final class DictationSession {
    /// Finish with nothing if no speech arrives within this time after recording starts.
    private static let noSpeechTimeout: Duration = .seconds(10)
    nonisolated private static let logger = Logger(subsystem: "MagnifierClone", category: "SpeechService")

    private let continuation: AsyncThrowingStream<String, Error>.Continuation
    private let silenceTimeout: Duration
    private let engine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var bufferContinuation: AsyncStream<AVReadOnlyAudioPCMBuffer>.Continuation?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var tasks: [Task<Void, Never>] = []
    private var timer: Task<Void, Never>?
    private var finalizedText = ""
    private var transcript = ""
    private var isTapInstalled = false
    private var isRecordingSessionSet = false
    private(set) var isTornDown = false

    init(continuation: AsyncThrowingStream<String, Error>.Continuation, silenceTimeout: Duration) {
        self.continuation = continuation
        self.silenceTimeout = silenceTimeout
    }

    func start() {
        tasks.append(Task { await self.run() })
    }

    /// Ends the stream normally (the transcript so far is the question).
    func finish() {
        guard !isTornDown else { return }
        tearDown()
        continuation.finish()
    }

    func finish(throwing error: Error) {
        guard !isTornDown else { return }
        tearDown()
        continuation.finish(throwing: error)
    }

    /// Stops audio and analysis and restores the audio session. Idempotent.
    func tearDown() {
        guard !isTornDown else { return }
        isTornDown = true
        timer?.cancel()
        timer = nil
        tasks.forEach { $0.cancel() }
        tasks = []
        if isTapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
        engine.stop()
        bufferContinuation?.finish()
        inputContinuation?.finish()
        if let analyzer {
            Task { await analyzer.cancelAndFinishNow() }
            self.analyzer = nil
        }
        if isRecordingSessionSet {
            // Back to what the waiting sound uses: respects the silent switch, mixes with others.
            Task.detached{
                do {
                    try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
                } catch {
                    Self.logger.error("Couldn't restore the ambient audio session: \(error.localizedDescription, privacy: .public)")
                }
                DispatchQueue.main.async{
                    self.isRecordingSessionSet = false
                }
            }
        }
    }

    // MARK: - Setup

    private func run() async {
        do {
            guard await Self.requestPermissions() else { throw SpeechServiceError.permissionDenied }
            guard !isTornDown else { return }

            guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) else {
                throw SpeechServiceError.unsupportedLanguage
            }
            let transcriber = SpeechTranscriber(
                locale: locale,
                transcriptionOptions: [],
                // Volatile + fast results: words show up while the person is still speaking.
                reportingOptions: [.volatileResults, .fastResults],
                attributeOptions: []
            )
            let modules: [any SpeechModule] = [transcriber]
            if let request = try await AssetInventory.assetInstallationRequest(supporting: modules) {
                try await request.downloadAndInstall()
            }
            guard !isTornDown else { return }

            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            isRecordingSessionSet = true
            try audioSession.setActive(true)

            let naturalFormat = engine.inputNode.outputFormat(forBus: 0)
            guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
                compatibleWith: modules,
                considering: naturalFormat
            ) else {
                throw SpeechServiceError.audioUnavailable
            }
            guard !isTornDown else { return }

            let analyzer = SpeechAnalyzer(modules: modules)
            self.analyzer = analyzer
            let (inputs, inputContinuation) = AsyncStream<AnalyzerInput>.makeStream()
            self.inputContinuation = inputContinuation
            tasks.append(Task { await self.consumeResults(of: transcriber) })
            try await analyzer.start(inputSequence: inputs)
            guard !isTornDown else { return }

            try startEngine(feeding: inputContinuation, in: analyzerFormat)
            armTimer(Self.noSpeechTimeout)
        } catch {
            guard !isTornDown, !(error is CancellationError) else { return }
            finish(throwing: error)
        }
    }

    private func startEngine(feeding inputs: AsyncStream<AnalyzerInput>.Continuation, in format: AVAudioFormat) throws {
        let (buffers, bufferContinuation) = AsyncStream<AVReadOnlyAudioPCMBuffer>.makeStream()
        self.bufferContinuation = bufferContinuation
        try Self.installTap(on: engine.inputNode, feeding: bufferContinuation)
        isTapInstalled = true
        tasks.append(Task.detached {
            let converted = await Self.convert(buffers, to: format, into: inputs)
            if !converted {
                await MainActor.run { self.finish(throwing: SpeechServiceError.audioUnavailable) }
            }
        })
        engine.prepare()
        try engine.start()
    }

    // MARK: - Results

    private func consumeResults(of transcriber: SpeechTranscriber) async {
        do {
            for try await result in transcriber.results {
                let text = String(result.text.characters)
                if result.isFinal {
                    finalizedText += text
                    update(finalizedText)
                } else {
                    update(finalizedText + text)
                }
            }
            // Results ended without us stopping: nothing more is coming, so submit what we have.
            finish()
        } catch {
            guard !isTornDown, !(error is CancellationError) else { return }
            finish(throwing: error)
        }
    }

    private func update(_ text: String) {
        guard !isTornDown, text != transcript else { return }
        transcript = text
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        continuation.yield(text)
        armTimer(silenceTimeout)
    }

    /// (Re)starts the timer that finishes the stream when no new text arrives in time.
    private func armTimer(_ duration: Duration) {
        timer?.cancel()
        timer = Task {
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self.finish()
        }
    }

    // MARK: - Nonisolated helpers

    nonisolated private static func requestPermissions() async -> Bool {
        let microphone: Bool
        switch AVAudioApplication.shared.recordPermission {
        case .granted: microphone = true
        case .denied: microphone = false
        default: microphone = await AVAudioApplication.requestRecordPermission()
        }
        guard microphone else { return false }

        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        default: return false
        }
    }

    /// The tap runs on the audio thread; it only hands buffers off.
    nonisolated private static func installTap(
        on node: AVAudioInputNode,
        feeding buffers: AsyncStream<AVReadOnlyAudioPCMBuffer>.Continuation
    ) throws {
        try node.installAudioTap(onBus: 0, bufferSize: 4096, format: nil) { buffer, _ in
            buffers.yield(buffer)
        }
    }

    /// Converts microphone buffers to the analyzer's format, off the main actor.
    /// Returns `false` if conversion failed. Then `inputs` is left open so the caller's
    /// `finish(throwing:)` (which tears down and closes it) wins over a normal results end.
    @concurrent nonisolated private static func convert(
        _ buffers: AsyncStream<AVReadOnlyAudioPCMBuffer>,
        to format: AVAudioFormat,
        into inputs: AsyncStream<AnalyzerInput>.Continuation
    ) async -> Bool {
        let converter = AnalyzerInputConverter(analyzerFormat: format)
        do {
            for await buffer in buffers {
                try converter.convert(AVAudioPCMBuffer(copying: buffer), at: nil).forEach { inputs.yield($0) }
            }
            try converter.flush().forEach { inputs.yield($0) }
            inputs.finish()
            return true
        } catch {
            logger.error("Audio conversion failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
