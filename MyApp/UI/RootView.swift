import AVFoundation
import SwiftUI

struct RootView: View {
    let model: AppModel
    let camera: CameraService
    let settings: AppSettings
    @State private var showSettings = false

    var body: some View {
        CameraLayer(model: model, session: camera.session)
            .overlay(alignment: .bottom) {
                ControlPanel(model: model, camera: camera) { showSettings = true }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { model.obscuredBottom = $0 }
                    .ignoresSafeArea(edges: .bottom)
            }
            .overlay { AskOverlay(model: model) }
            .sheet(isPresented: $showSettings) {
                SettingsView(settings: settings)
                    .presentationDetents([.medium])
            }
            .task { await camera.start() }
            .preferredColorScheme(.dark)
    }
}

/// The full-screen camera image, edge to edge: live preview, or the frozen frame. Reports its size as `model.viewSize`.
struct CameraLayer: View {
    let model: AppModel
    let session: AVCaptureSession

    var body: some View {
        ZStack(alignment: .bottom) {
            // Measured here, not on the stack: the base layer always takes exactly the offered size,
            // so whatever the content does, the crop matches the screen.
            Color.black
                .onGeometryChange(for: CGSize.self) { $0.size } action: { model.viewSize = $0 }
            if let image = model.frozenImage, model.isFrozen {
                FrozenFrameView(image: image)
            } else {
                CameraPreview(session: session)
            }
        }
        .ignoresSafeArea()
    }
}
