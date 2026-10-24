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
    /// Single-entry cache. The strong CIImage reference prevents identity reuse after dealloc.
    private static var cached: (source: CIImage, rendered: CGImage?)?

    /// SwiftUI recreates this struct on every parent update, so render only when the image instance changes.
    init(image: CIImage) {
        if let cached = Self.cached, cached.source === image {
            rendered = cached.rendered
        } else {
            let cg = Self.context.createCGImage(image, from: image.extent)
            Self.cached = (image, cg)
            rendered = cg
        }
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
