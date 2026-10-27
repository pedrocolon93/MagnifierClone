import AVFoundation
import CoreHaptics
import Foundation

/// Repeating "ding" sound plus haptic while the app waits for an AI answer.
final class WaitingFeedback: WaitingFeedbackPlaying {
    private let ding: (WaitingCue) -> Void
    private var task: Task<Void, Never>?

    init(ding: @escaping (WaitingCue) -> Void = WaitingFeedback.systemDing) {
        self.ding = ding
    }

    func start(_ cue: WaitingCue) {
        stop()
        let ding = self.ding
        if cue.delay <= 0 { ding(cue) }
        task = Task { @MainActor in
            if cue.delay > 0 {
                try? await Task.sleep(for: .seconds(cue.delay))
                if Task.isCancelled { return }
                ding(cue)
            }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(cue.interval))
                if Task.isCancelled { break }
                ding(cue)
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

    nonisolated static func systemDing(_ cue: WaitingCue) {
        if let url = cue.soundURL { playSound(at: url) }
        if cue.vibrates { playHaptic() }
    }

    /// Plays `url` once; also used by Settings to preview a sound. Reuses the player while the sound is unchanged.
    nonisolated static func playSound(at url: URL) {
        Task.detached {
            if player?.url != url {
                // .ambient + .mixWithOthers respects the silent switch.
                try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
                try? AVAudioSession.sharedInstance().setActive(true)
                player = try? AVAudioPlayer(contentsOf: url)
                player?.prepareToPlay()
            }
            player?.currentTime = 0
            player?.play()
        }
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
