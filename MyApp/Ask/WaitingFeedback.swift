import AVFoundation
import CoreHaptics
import Foundation

/// Repeating "ding" sound plus haptic while the app waits for an AI answer.
final class WaitingFeedback: WaitingFeedbackPlaying {
    private let ding: () -> Void
    private var task: Task<Void, Never>?

    init(ding: @escaping () -> Void = WaitingFeedback.systemDing) {
        self.ding = ding
    }

    func start(interval: Double) {
        stop()
        ding()
        let ding = self.ding
        task = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                if Task.isCancelled { break }
                ding()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    // MARK: - System sound and haptic

    nonisolated(unsafe) private static var player: AVAudioPlayer?
    nonisolated(unsafe) private static var engine: CHHapticEngine?

    nonisolated static func systemDing() {
        playSound()
        playHaptic()
    }

    nonisolated private static func playSound() {
        if player == nil {
            guard let url = Bundle.main.url(forResource: "waiting", withExtension: "m4a") else { return }
            // .ambient + .mixWithOthers respects the silent switch.
            try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            try? AVAudioSession.sharedInstance().setActive(true)
            player = try? AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
        }
        player?.currentTime = 0
        player?.play()
    }

    nonisolated private static func playHaptic() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            if engine == nil {
                let newEngine = try CHHapticEngine()
                newEngine.isAutoShutdownEnabled = true
                newEngine.resetHandler = { [weak newEngine] in try? newEngine?.start() }
                newEngine.stoppedHandler = { _ in }
                engine = newEngine
            }
            guard let engine else { return }
            try engine.start()
            let event = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8),
                ],
                relativeTime: 0
            )
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            try engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
        } catch {
            engine = nil // recreate lazily next time
        }
    }
}
