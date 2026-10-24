import CoreGraphics
import Foundation

/// Maps a 0...1 slider to an exponential zoom factor so each step feels like equal magnification.
nonisolated struct ZoomMapping {
    static let factorCap: CGFloat = 10

    let maxFactor: CGFloat

    init(maxDeviceFactor: CGFloat) {
        maxFactor = max(1, min(maxDeviceFactor, Self.factorCap))
    }

    func factor(forSlider value: Double) -> CGFloat {
        let clamped = min(max(value, 0), 1)
        return pow(maxFactor, CGFloat(clamped))
    }

    func sliderValue(forFactor f: CGFloat) -> Double {
        guard maxFactor > 1 else { return 0 }
        let clamped = min(max(f, 1), maxFactor)
        return Double(log(clamped) / log(maxFactor))
    }

    func stepped(from value: Double, by step: Int) -> Double {
        min(max(value + 0.1 * Double(step), 0), 1)
    }
}
