import AVFoundation
import CoreImage
import SwiftUI
import Testing
import UIKit
@testable import MagnifierClone

/// Hosts the camera layer (the part of `RootView` that sizes the screen and sets `viewSize`) with a
/// frozen frame whose aspect differs from the screen's, and checks that nothing grows past the screen.
@MainActor
struct FrozenLayoutTests {
    static let screen = CGSize(width: 393, height: 852)

    /// A 1080×1920 checkerboard: taller-than-wide like a portrait camera frame, but narrower than the screen's aspect.
    static func testPattern() -> CIImage {
        let filter = CIFilter(name: "CICheckerboardGenerator", parameters: [
            "inputColor0": CIColor.white, "inputColor1": CIColor.black, "inputWidth": 60,
        ])!
        return filter.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: 1080, height: 1920))
    }

    @Test func frozenFrameFillsScreenWithoutOverflow() async throws {
        let settings = AppSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let model = AppModel(settings: settings, frames: FakeFrames(frame: Self.testPattern()), ask: FakeAsk(),
                             speech: FakeSpeech(), feedback: FakeFeedback())
        model.capture()
        try #require(model.isFrozen)

        let host = UIHostingController(rootView: CameraLayer(model: model, session: AVCaptureSession()))
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: Self.screen)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        for _ in 0..<10 {
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(host.sizeThatFits(in: Self.screen) == Self.screen)
        #expect(model.viewSize == Self.screen)
    }
}
