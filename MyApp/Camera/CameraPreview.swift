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
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        if let connection = view.previewLayer.connection, connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

/// Shows a frozen frame exactly as the aspect-fill preview showed it.
struct FrozenFrameView: View {
    let image: CIImage
    @State private var rendered: CGImage?

    private static let context = CIContext()

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
        .task(id: ObjectIdentifier(image)) {
            rendered = Self.context.createCGImage(image, from: image.extent)
        }
    }
}
