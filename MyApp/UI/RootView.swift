import SwiftUI

struct RootView: View {
    let model: AppModel
    let camera: CameraService
    let settings: AppSettings
    @State private var showSettings = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black
            if let image = model.frozenImage, model.isFrozen {
                FrozenFrameView(image: image)
            } else {
                CameraPreview(session: camera.session)
            }
        }
        .ignoresSafeArea()
        .onGeometryChange(for: CGSize.self) { $0.size } action: { model.viewSize = $0 }
        .overlay(alignment: .bottom) {
            ControlPanel(model: model, camera: camera) { showSettings = true }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { model.obscuredBottom = $0 }
                .ignoresSafeArea(edges: .bottom)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(settings: settings)
                .presentationDetents([.medium])
        }
        .task { await camera.start() }
        .preferredColorScheme(.dark)
    }
}
