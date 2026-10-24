import AVFoundation
import CoreImage
import SwiftUI
import UIKit

/// Live camera preview, aspect-fill and portrait.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        private var observer: NSObjectProtocol?

        /// The preview connection only exists once the session has inputs, so apply this repeatedly.
        func applyPortrait() {
            guard let connection = previewLayer.connection,
                  connection.isVideoRotationAngleSupported(90),
                  connection.videoRotationAngle != 90 else { return }
            connection.videoRotationAngle = 90
        }

        func observe(_ session: AVCaptureSession) {
            observer = NotificationCenter.default.addObserver(
                forName: AVCaptureSession.didStartRunningNotification, object: session, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.applyPortrait() }
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            applyPortrait()
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.observe(session)
        view.applyPortrait()
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.applyPortrait()
    }
}

/// Shows a frozen frame exactly as the aspect-fill preview showed it.
struct FrozenFrameView: View {
    private let rendered: CGImage?

    private static let context = CIContext()

    /// Renders once at init; SwiftUI recreates the view when the frozen image changes.
    init(image: CIImage) {
        rendered = Self.context.createCGImage(image, from: image.extent)
    }

    var body: some View {
        Group {
            if let rendered {
                Image(decorative: rendered, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.black
            }
        }
        .clipped()
    }
}
