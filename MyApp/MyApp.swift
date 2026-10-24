import SwiftUI

@main struct MyApp: App {
    @State private var settings: AppSettings
    @State private var camera: CameraService
    @State private var model: AppModel

    init() {
        let settings = AppSettings()
        let camera = CameraService()
        // Private Cloud Compute needs an Apple-managed entitlement this project lacks, so the cloud route is off.
        let model = AppModel(
            settings: settings, frames: camera, ask: AskService(cloudEnabled: false),
            speech: SpeechService(), feedback: WaitingFeedback()
        )
        _settings = State(initialValue: settings)
        _camera = State(initialValue: camera)
        _model = State(initialValue: model)
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model, camera: camera, settings: settings)
        }
    }
}
