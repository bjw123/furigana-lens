import AVFoundation
import SwiftUI

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}
}

final class PreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}

@MainActor
final class CameraController: ObservableObject {
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var isConfigured = false
    private var device: AVCaptureDevice?

    @Published var isRunning = false
    @Published var permissionDenied = false
    @Published private(set) var zoomFactor: CGFloat = 1.0

    var minZoomFactor: CGFloat { 1.0 }
    var maxZoomFactor: CGFloat {
        guard let device else { return 1.0 }
        return min(device.activeFormat.videoMaxZoomFactor, 10.0)
    }

    func setZoom(_ factor: CGFloat) {
        guard let device else { return }
        let clamped = max(minZoomFactor, min(factor, maxZoomFactor))
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = clamped
            device.unlockForConfiguration()
            zoomFactor = clamped
        } catch {
            // Silently ignore — zoom is a non-critical control.
        }
    }

    func configure() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            await setupSession()
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted {
                await setupSession()
            } else {
                permissionDenied = true
            }
        default:
            permissionDenied = true
        }
    }

    func start() {
        guard !session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
            DispatchQueue.main.async { self?.isRunning = true }
        }
    }

    func stop() {
        guard session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.stopRunning()
            DispatchQueue.main.async { self?.isRunning = false }
        }
    }

    func capturePhoto() async -> UIImage? {
        guard isConfigured else { return nil }
        return await withCheckedContinuation { continuation in
            let settings = AVCapturePhotoSettings()
            let delegate = PhotoCaptureDelegate { image in
                continuation.resume(returning: image)
            }
            PhotoCaptureDelegate.retained[self.photoOutput] = delegate
            photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }

    private func setupSession() async {
        session.beginConfiguration()
        session.sessionPreset = .photo

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            session.commitConfiguration()
            return
        }

        session.inputs.forEach { session.removeInput($0) }
        session.addInput(input)

        session.outputs.forEach { session.removeOutput($0) }
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }

        session.commitConfiguration()
        self.device = device
        zoomFactor = device.videoZoomFactor
        isConfigured = true
    }
}

private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    static var retained: [AVCapturePhotoOutput: PhotoCaptureDelegate] = [:]
    private let completion: (UIImage?) -> Void

    init(completion: @escaping (UIImage?) -> Void) {
        self.completion = completion
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        defer { Self.retained[output] = nil }
        guard error == nil, let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            completion(nil)
            return
        }
        completion(image)
    }
}
