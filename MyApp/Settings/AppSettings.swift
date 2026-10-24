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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        inputMode = defaults.string(forKey: "inputMode").flatMap(InputMode.init(rawValue:)) ?? .askEachTime
        let stored = defaults.object(forKey: "waitInterval") as? Double ?? 1.0
        waitInterval = min(max(stored, Self.waitIntervalRange.lowerBound), Self.waitIntervalRange.upperBound)
    }
}
