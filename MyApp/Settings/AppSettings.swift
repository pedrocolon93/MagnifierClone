import Foundation
import Observation

enum InputMode: String, CaseIterable {
    case voice, text, askEachTime
}

enum InputKind {
    case voice, text
}

@Observable
final class AppSettings {
    static let waitIntervalRange: ClosedRange<Double> = 0.5...3.0
    static let waitDelayRange: ClosedRange<Double> = 0...5
    /// `waitingSound` values that aren't file paths.
    static let builtInSound = ""
    static let noSound = "none"

    @ObservationIgnored private let defaults: UserDefaults

    var inputMode: InputMode {
        didSet { defaults.set(inputMode.rawValue, forKey: "inputMode") }
    }

    /// Seconds to wait before the waiting sound plays; always within `waitIntervalRange`.
    var waitInterval: Double {
        didSet {
            let clamped = min(max(waitInterval, Self.waitIntervalRange.lowerBound), Self.waitIntervalRange.upperBound)
            if clamped != waitInterval { waitInterval = clamped }
            defaults.set(clamped, forKey: "waitInterval")
        }
    }

    /// Seconds after waiting begins before the first ding; always within `waitDelayRange`.
    var waitDelay: Double {
        didSet {
            let clamped = min(max(waitDelay, Self.waitDelayRange.lowerBound), Self.waitDelayRange.upperBound)
            if clamped != waitDelay { waitDelay = clamped }
            defaults.set(clamped, forKey: "waitDelay")
        }
    }

    /// `builtInSound`, `noSound`, or the path of a system sound file.
    var waitingSound: String {
        didSet { defaults.set(waitingSound, forKey: "waitingSound") }
    }

    var answerStyle: AnswerStyle {
        didSet { defaults.set(answerStyle.rawValue, forKey: "answerStyle") }
    }

    var vibrates: Bool {
        didSet { defaults.set(vibrates, forKey: "vibrates") }
    }

    var waitingSoundURL: URL? {
        switch waitingSound {
        case Self.builtInSound: WaitingCue.defaultSoundURL
        case Self.noSound: nil
        default: URL(filePath: waitingSound)
        }
    }

    var waitingCue: WaitingCue {
        WaitingCue(interval: waitInterval, delay: waitDelay, soundURL: waitingSoundURL, vibrates: vibrates)
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        inputMode = defaults.string(forKey: "inputMode").flatMap(InputMode.init(rawValue:)) ?? .askEachTime
        let stored = defaults.object(forKey: "waitInterval") as? Double ?? 1.0
        waitInterval = min(max(stored, Self.waitIntervalRange.lowerBound), Self.waitIntervalRange.upperBound)
        let storedDelay = defaults.object(forKey: "waitDelay") as? Double ?? 0
        waitDelay = min(max(storedDelay, Self.waitDelayRange.lowerBound), Self.waitDelayRange.upperBound)
        let storedSound = defaults.string(forKey: "waitingSound") ?? Self.builtInSound
        // A system sound that's gone (e.g. after an iOS update) falls back to the built-in one.
        if storedSound == Self.builtInSound || storedSound == Self.noSound
            || FileManager.default.fileExists(atPath: storedSound) {
            waitingSound = storedSound
        } else {
            waitingSound = Self.builtInSound
        }
        vibrates = defaults.object(forKey: "vibrates") as? Bool ?? true
        answerStyle = defaults.string(forKey: "answerStyle").flatMap(AnswerStyle.init(rawValue:)) ?? .standard
    }
}
