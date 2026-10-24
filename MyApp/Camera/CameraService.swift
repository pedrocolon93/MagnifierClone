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

/// Back wide camera with hardware zoom; exposes the newest upright frame.
@Observable
final class CameraService: FrameSource {
    let session = AVCaptureSession()
    private(set) var access: CameraAccess = .unknown
    private(set) var sliderValue: Double = 0
    private(set) var zoom = ZoomMapping(maxDeviceFactor: 1)

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
        defer { session.commitConfiguration() }
        session.sessionPreset = .high
        guard session.canAddInput(input) else { return nil }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(frames, queue: videoQueue)
        guard session.canAddOutput(output) else { return nil }
        session.addOutput(output)
        if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        return (camera, camera.activeFormat.videoMaxZoomFactor)
    }
}
