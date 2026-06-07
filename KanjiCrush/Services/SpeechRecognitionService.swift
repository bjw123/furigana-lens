import AVFoundation
import Foundation
import Speech
import SwiftUI

/// Live Japanese speech-to-text wrapper used by the typed-quiz "Speak" mode.
///
/// Drives `SFSpeechRecognizer` (locale `ja-JP`) off the device microphone via
/// an `AVAudioEngine` tap. On-device recognition is preferred when the
/// recognizer reports support for it, otherwise it falls back to Apple's
/// server-based recognition transparently. Transient state only — never
/// persisted.
@MainActor
final class SpeechRecognitionService: ObservableObject {
    @Published private(set) var transcript: String = ""
    @Published private(set) var isListening: Bool = false
    @Published private(set) var error: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    /// `true` when a Japanese recognizer exists, is available, and both
    /// Speech + Microphone authorisation are granted. Used by the UI to
    /// gate the mic button before listening begins.
    var isAvailable: Bool {
        guard let recognizer, recognizer.isAvailable else { return false }
        let speechAuth = SFSpeechRecognizer.authorizationStatus()
        guard speechAuth == .authorized || speechAuth == .notDetermined else { return false }
        let micAuth: Bool
        if #available(iOS 17.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted, .undetermined: micAuth = true
            default: micAuth = false
            }
        } else {
            switch AVAudioSession.sharedInstance().recordPermission {
            case .granted, .undetermined: micAuth = true
            default: micAuth = false
            }
        }
        return micAuth
    }

    /// Requests both Speech Recognition and Microphone permissions.
    /// Returns `true` only if both prompts resolved as granted.
    func requestAuthorization() async -> Bool {
        let speechGranted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }

        let micGranted: Bool
        if #available(iOS 17.0, *) {
            micGranted = await AVAudioApplication.requestRecordPermission()
        } else {
            micGranted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        }

        return speechGranted && micGranted
    }

    /// Begins live capture and streams partial recognition results into
    /// `transcript`. Throws if the Japanese recognizer is missing or the
    /// audio session cannot be configured.
    func start() throws {
        guard !isListening else { return }
        guard let recognizer, recognizer.isAvailable else {
            throw SpeechRecognitionError.unavailable
        }

        // Tear down any lingering state from a previous session.
        task?.cancel()
        task = nil

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }
        engine.prepare()
        try engine.start()
        self.audioEngine = engine

        transcript = ""
        error = nil
        isListening = true

        task = recognizer.recognitionTask(with: request) { [weak self] result, err in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if err != nil || (result?.isFinal ?? false) {
                    if let err {
                        // Ignore the expected "no speech" / cancelled errors so
                        // the UI only surfaces genuine recogniser failures.
                        let nsErr = err as NSError
                        let cancelled = nsErr.domain == "kAFAssistantErrorDomain"
                            && (nsErr.code == 203 || nsErr.code == 216 || nsErr.code == 1110)
                        if !cancelled {
                            self.error = nsErr.localizedDescription
                        }
                    }
                    self.teardown()
                }
            }
        }
    }

    /// Stops capture and finalises any in-flight recognition. The last
    /// observed `transcript` value remains so the user can edit it.
    func stop() {
        guard isListening else { return }
        request?.endAudio()
        task?.finish()
        teardown()
    }

    private func teardown() {
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            if engine.isRunning { engine.stop() }
        }
        audioEngine = nil
        request = nil
        task = nil
        isListening = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

enum SpeechRecognitionError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Japanese speech recognition is unavailable on this device."
        }
    }
}
