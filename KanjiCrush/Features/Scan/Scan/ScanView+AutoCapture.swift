import AVFoundation
import CoreImage
import SwiftUI
import Vision

// MARK: - Stability detector

/// Tracks the centre-of-mass of recently-detected text regions and reports
/// when the camera is "stable enough" to fire an auto-capture. Pure value
/// type — owns no Vision/AVF resources; lives inside `FrameScanCoordinator`.
private struct StabilityDetector {
    /// Sample of one frame's worth of text geometry.
    struct Sample {
        let timestamp: CFTimeInterval
        let centre: CGPoint   // normalised 0...1 (Vision coords)
        let count: Int        // number of detected text regions
    }

    /// Rolling window in seconds. We auto-fire when the window is full *and*
    /// the centre-of-mass jitter is below `maxJitterNormalised`.
    var windowSeconds: CFTimeInterval = 1.0

    /// ~10 px on a typical 400-pt viewport ≈ 0.025 of the normalised axis.
    /// Vision uses normalised coordinates so this stays resolution-agnostic.
    var maxJitterNormalised: CGFloat = 0.025

    /// After a successful auto-fire we ignore stability for this long so the
    /// user can recompose without an immediate re-fire.
    var cooldownSeconds: CFTimeInterval = 2.5

    private var samples: [Sample] = []
    private var cooldownUntil: CFTimeInterval = 0

    mutating func reset() {
        samples.removeAll(keepingCapacity: true)
    }

    mutating func startCooldown(now: CFTimeInterval) {
        cooldownUntil = now + cooldownSeconds
        samples.removeAll(keepingCapacity: true)
    }

    /// Records a frame's geometry and returns the current accumulation
    /// progress (0...1) and whether the frame is stable enough to fire.
    mutating func ingest(_ sample: Sample) -> (progress: Double, shouldFire: Bool) {
        guard sample.timestamp >= cooldownUntil else {
            samples.removeAll(keepingCapacity: true)
            return (0, false)
        }
        // Dropping the sample when there's no text keeps an empty viewfinder
        // from accidentally counting as "stable".
        guard sample.count > 0 else {
            samples.removeAll(keepingCapacity: true)
            return (0, false)
        }

        samples.append(sample)
        // Trim anything older than the window.
        let cutoff = sample.timestamp - windowSeconds
        while let first = samples.first, first.timestamp < cutoff {
            samples.removeFirst()
        }

        guard let oldest = samples.first, samples.count >= 3 else {
            return (0, false)
        }
        let spanned = sample.timestamp - oldest.timestamp
        let progress = min(1.0, spanned / windowSeconds)

        let jitter = currentJitter()
        let stable = progress >= 1.0 && jitter <= maxJitterNormalised
        return (progress, stable)
    }

    /// Mean Euclidean distance from each sample's centre to the average
    /// centre, in Vision normalised units.
    private func currentJitter() -> CGFloat {
        guard !samples.isEmpty else { return .infinity }
        let avgX = samples.reduce(0) { $0 + $1.centre.x } / CGFloat(samples.count)
        let avgY = samples.reduce(0) { $0 + $1.centre.y } / CGFloat(samples.count)
        let total = samples.reduce(CGFloat(0)) { acc, s in
            let dx = s.centre.x - avgX
            let dy = s.centre.y - avgY
            return acc + (dx * dx + dy * dy).squareRoot()
        }
        return total / CGFloat(samples.count)
    }
}

// MARK: - Frame coordinator

/// Hooks an `AVCaptureVideoDataOutput` onto the live camera session,
/// runs a low-fidelity `VNRecognizeTextRequest` on each frame, and feeds
/// the resulting bbox centres into a `StabilityDetector`. Publishes a
/// progress value the UI can render and invokes `onAutoFire` when the
/// framed text holds still long enough.
@MainActor
final class FrameScanCoordinator: NSObject, ObservableObject {
    /// 0...1 — accumulation toward auto-fire. Drops to 0 between sessions.
    @Published private(set) var stabilityProgress: Double = 0
    /// `true` briefly while we kick off an auto-capture; the UI flashes this.
    @Published private(set) var didJustAutoFire: Bool = false

    /// Caller-supplied closure that fires the same code path as the shutter.
    var onAutoFire: (() -> Void)?

    private let videoOutput = AVCaptureVideoDataOutput()
    private let processingQueue = DispatchQueue(
        label: "kanjicrush.scan.frame", qos: .userInitiated
    )
    private var detector = StabilityDetector()
    private weak var attachedSession: AVCaptureSession?

    /// Mutated only on `processingQueue`; the delegate callback runs there
    /// exclusively, so unsynchronised access from that queue is safe.
    private nonisolated(unsafe) var requestInFlight = false
    private nonisolated(unsafe) var enabledOnQueue = false

    /// Attach the video data output to `session`. Safe to call multiple times.
    func attach(to session: AVCaptureSession) {
        guard attachedSession !== session else { return }
        detach()
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.setSampleBufferDelegate(self, queue: processingQueue)
        session.beginConfiguration()
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }
        session.commitConfiguration()
        attachedSession = session
    }

    func detach() {
        if let session = attachedSession,
           session.outputs.contains(videoOutput) {
            session.beginConfiguration()
            session.removeOutput(videoOutput)
            session.commitConfiguration()
        }
        attachedSession = nil
    }

    func setEnabled(_ on: Bool) {
        processingQueue.async { [self] in
            enabledOnQueue = on
        }
        if !on {
            detector.reset()
            stabilityProgress = 0
        }
    }

    /// Drop any accumulated samples — e.g. when the user manually captures
    /// or returns from the frozen view.
    func resetAccumulation() {
        detector.reset()
        stabilityProgress = 0
    }

    /// Called after an auto-capture path completes; starts the cooldown so
    /// we don't immediately re-fire on the same scene.
    func noteAutoFireConsumed() {
        detector.startCooldown(now: CACurrentMediaTime())
        stabilityProgress = 0
        didJustAutoFire = false
    }
}

// MARK: - Sample-buffer delegate

extension FrameScanCoordinator: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // This delegate is invoked exclusively on `processingQueue` (set in
        // `attach(to:)`), so the unsafe flags can be touched directly here.
        guard enabledOnQueue, !requestInFlight else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        requestInFlight = true

        let request = VNRecognizeTextRequest { [weak self] req, _ in
            guard let self else { return }
            let observations = (req.results as? [VNRecognizedTextObservation]) ?? []
            let centre = Self.centreOfMass(of: observations)
            let count = observations.count
            let now = CACurrentMediaTime()
            self.requestInFlight = false

            Task { @MainActor in
                let result = self.detector.ingest(
                    .init(timestamp: now, centre: centre, count: count)
                )
                self.stabilityProgress = result.progress
                if result.shouldFire {
                    self.didJustAutoFire = true
                    self.onAutoFire?()
                }
            }
        }
        // .fast is more than enough for stability — we only need bounding
        // boxes, not perfect text. The eventual capture goes through the
        // accurate path in OCRService.
        request.recognitionLevel = .fast
        request.recognitionLanguages = ["ja-JP"]
        request.usesLanguageCorrection = false

        let orientation = Self.exifOrientation(for: connection)
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: orientation,
            options: [:]
        )
        do {
            try handler.perform([request])
        } catch {
            // Don't bother reporting — next frame will try again.
            requestInFlight = false
        }
    }

    nonisolated private static func centreOfMass(
        of observations: [VNRecognizedTextObservation]
    ) -> CGPoint {
        guard !observations.isEmpty else { return .zero }
        var sumX: CGFloat = 0
        var sumY: CGFloat = 0
        for obs in observations {
            sumX += obs.boundingBox.midX
            sumY += obs.boundingBox.midY
        }
        let n = CGFloat(observations.count)
        return CGPoint(x: sumX / n, y: sumY / n)
    }

    nonisolated private static func exifOrientation(
        for connection: AVCaptureConnection
    ) -> CGImagePropertyOrientation {
        // The preview is portrait back-camera; map AVF rotation to EXIF.
        let angle = connection.videoRotationAngle
        switch angle {
        case 0: return .right
        case 90: return .up
        case 180: return .left
        case 270: return .down
        default: return .right
        }
    }
}

// MARK: - View overlay

extension ScanView {
    /// Subtle radial progress ring placed near the shutter button. Renders
    /// nothing when no accumulation is in progress.
    @ViewBuilder
    func autoCaptureOverlay(progress: Double, justFired: Bool) -> some View {
        ZStack {
            // Brief flash when the auto-capture fires.
            if justFired {
                Circle()
                    .fill(Color.white.opacity(0.55))
                    .blur(radius: 18)
                    .frame(width: 140, height: 140)
                    .transition(.opacity)
            }

            if progress > 0.05 && !justFired {
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .stroke(Palette.sakura.opacity(0.25), lineWidth: 3)
                            .frame(width: 36, height: 36)
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(
                                Palette.sakura,
                                style: StrokeStyle(lineWidth: 3, lineCap: .round)
                            )
                            .frame(width: 36, height: 36)
                            .rotationEffect(.degrees(-90))
                            .animation(.easeOut(duration: 0.15), value: progress)
                    }
                    Text("Hold steady…")
                        .font(.system(.caption2, design: .rounded).weight(.medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(.black.opacity(0.45)))
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: progress > 0.05)
        .animation(.easeInOut(duration: 0.2), value: justFired)
        .allowsHitTesting(false)
    }
}
