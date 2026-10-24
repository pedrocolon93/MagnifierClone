import CoreGraphics
import Foundation
import Testing
@testable import MagnifierClone

struct ZoomMappingTests {
    @Test func sliderZeroIsOneX() {
        #expect(ZoomMapping(maxDeviceFactor: 15).factor(forSlider: 0) == 1)
    }

    @Test func maxFactorIsCappedAtTen() {
        let mapping = ZoomMapping(maxDeviceFactor: 15)
        #expect(mapping.maxFactor == 10)
        #expect(mapping.factor(forSlider: 1) == 10)
    }

    @Test func midpointIsExponential() {
        let mapping = ZoomMapping(maxDeviceFactor: 15)
        #expect(abs(mapping.factor(forSlider: 0.5) - CGFloat(10.0.squareRoot())) < 0.001)
    }

    @Test func sliderRoundTrips() {
        let mapping = ZoomMapping(maxDeviceFactor: 15)
        let value = mapping.sliderValue(forFactor: mapping.factor(forSlider: 0.3))
        #expect(abs(value - 0.3) < 0.0001)
    }

    @Test func steppingClampsToUnitRange() {
        let mapping = ZoomMapping(maxDeviceFactor: 15)
        #expect(mapping.stepped(from: 0.95, by: 1) == 1)
        #expect(mapping.stepped(from: 0.05, by: -1) == 0)
    }

    @Test func frontCameraWithNoZoomStaysAtOneX() {
        let mapping = ZoomMapping(maxDeviceFactor: 1)
        #expect(mapping.factor(forSlider: 1) == 1)
        #expect(mapping.sliderValue(forFactor: 1) == 0)
    }
}
