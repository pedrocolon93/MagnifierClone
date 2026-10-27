@preconcurrency import AVFoundation
import CoreImage
import Observation
import os

/// Wraps a pixel buffer, which is immutable once delivered by the capture pipeline.
nonisolated private struct PixelBufferBox: @unchecked Sendable {
    let buffer: CVPixelBuffer
}

/// Receives sample buffers on the capture queue and stores the newest pixel buffer.
nonisolated final class FrameBufferStore: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let latest = OSAllocatedUnfairLock<PixelBufferBox?>(initialState: nil)

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let box = PixelBufferBox(buffer: buffer)
        latest.withLock { $0 = box }
    }

    func current() -> CVPixelBuffer? {
        latest.withLock { $0 }?.buffer
    }
}

nonisolated enum CameraAccess: Equatable, Sendable {
    /// Not yet asked, or the answer hasn't arrived.
    case unknown
    case authorized
    /// Denied or restricted; only Settings can change it.
    case denied
}

/// Wide camera (back or front) with hardware zoom; exposes the newest upright, unmirrored frame.
@Observable
final class CameraService: FrameSource {
    let session = AVCaptureSession()
    private(set) var access: CameraAccess = .unknown
    private(set) var sliderValue: Double = 0
    private(set) var zoom = ZoomMapping(maxDeviceFactor: 1)
    private(set) var position: AVCaptureDevice.Position = .back
    private(set) var isSwitching = false
    private(set) var isTorchOn = false
    /// The front camera has no torch.
    private(set) var hasTorch = false

    @ObservationIgnored private let frames = FrameBufferStore()
    @ObservationIgnored private let sessionQueue = DispatchQueue(label: "camera.session")
    @ObservationIgnored private let videoQueue = DispatchQueue(label: "camera.video")
    @ObservationIgnored private var device: AVCaptureDevice?
    @ObservationIgnored private var isConfigured = false

    func start() async {
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            access = .denied
            return
        }
        access = .authorized
        let session = session, frames = frames, videoQueue = videoQueue, alreadyConfigured = isConfigured
        let result: (device: AVCaptureDevice, maxZoom: CGFloat)? = await withCheckedContinuation { continuation in
            sessionQueue.async {
                var result: (device: AVCaptureDevice, maxZoom: CGFloat)?
                if alreadyConfigured {
                    result = nil
                } else {
                    result = Self.configure(session: session, frames: frames, videoQueue: videoQueue)
                }
                if (alreadyConfigured || result != nil), !session.isRunning { session.startRunning() }
                continuation.resume(returning: result)
            }
        }
        if let result {
            device = result.device
            hasTorch = result.device.hasTorch
            zoom = ZoomMapping(maxDeviceFactor: result.maxZoom)
            isConfigured = true
            setZoom(slider: sliderValue)
        }
    }

    func stop() {
        let session = session
        sessionQueue.async {
            if session.isRunning { session.stopRunning() }
        }
    }

    /// Switches between the back and front cameras and resets zoom to 1×.
    func flip() async {
        guard isConfigured, !isSwitching else { return }
        isSwitching = true
        defer { isSwitching = false }
        let target: AVCaptureDevice.Position = position == .back ? .front : .back
        let session = session
        let result: (device: AVCaptureDevice, maxZoom: CGFloat)? = await withCheckedContinuation { continuation in
            sessionQueue.async {
                continuation.resume(returning: Self.switchInput(on: session, to: target))
            }
        }
        guard let result else { return }
        device = result.device
        position = target
        // The torch belongs to the back camera and goes out when it's swapped away.
        hasTorch = result.device.hasTorch
        isTorchOn = false
        zoom = ZoomMapping(maxDeviceFactor: result.maxZoom)
        setZoom(slider: 0)
    }

    func setTorch(_ on: Bool) {
        guard let device, device.hasTorch, device.isTorchAvailable else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
            isTorchOn = on
        } catch {}
    }

    func setZoom(slider: Double) {
        let clamped = min(max(slider, 0), 1)
        sliderValue = clamped
        guard let device else { return }
        let factor = zoom.factor(forSlider: clamped)
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = factor
            device.unlockForConfiguration()
        } catch {}
    }

    func latestFrame() -> CIImage? {
        frames.current().map { CIImage(cvPixelBuffer: $0) }
    }

    /// Runs on the session queue.
    nonisolated private static func configure(
        session: AVCaptureSession, frames: FrameBufferStore, videoQueue: DispatchQueue
    ) -> (device: AVCaptureDevice, maxZoom: CGFloat)? {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera) else { return nil }
        session.beginConfiguration()
        defer {
            session.commitConfiguration()
            orientConnections(of: session)
        }
        session.sessionPreset = .high
        guard session.canAddInput(input) else { return nil }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(frames, queue: videoQueue)
        guard session.canAddOutput(output) else { return nil }
        session.addOutput(output)
        return (camera, camera.activeFormat.videoMaxZoomFactor)
    }

    /// Runs on the session queue. Swaps the camera input; on failure the old input stays.
    nonisolated private static func switchInput(
        on session: AVCaptureSession, to position: AVCaptureDevice.Position
    ) -> (device: AVCaptureDevice, maxZoom: CGFloat)? {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: camera) else { return nil }
        session.beginConfiguration()
        defer {
            session.commitConfiguration()
            // The new input brings new connections, including the preview layer's, which start sideways.
            orientConnections(of: session)
        }
        let old = session.inputs
        old.forEach(session.removeInput)
        guard session.canAddInput(input) else {
            old.forEach(session.addInput)
            return nil
        }
        session.addInput(input)
        return (camera, camera.activeFormat.videoMaxZoomFactor)
    }

    /// Every video connection (frame output and preview layer alike) is portrait and never mirrored,
    /// so text reads correctly and the frozen frame matches the preview. Runs after the configuration commits.
    nonisolated private static func orientConnections(of session: AVCaptureSession) {
        for connection in session.connections where connection.inputPorts.contains(where: { $0.mediaType == .video }) {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
        }
    }
}
