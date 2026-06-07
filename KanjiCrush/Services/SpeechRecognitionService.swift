import AVFoundation
import Foundation
import Speech
import SwiftUI
import os

/// Live Japanese speech-to-text wrapper used by the typed-quiz "Speak" mode.
///
/// Drives `SFSpeechRecognizer` (locale `ja-JP`) off the device microphone via
/// an `AVAudioEngine` tap. On-device recognition is preferred when the
/// recognizer reports support for it, otherwise it falls back to Apple's
/// server-based recognition transparently. Transient state only — never
/// persisted.
///
/// In `continuousMode` (the default) the service re-installs a fresh
/// `SFSpeechRecognitionTask` whenever the current task finalises due to a
/// silence pause or a recoverable server-timeout, while the underlying
/// `AVAudioEngine` keeps running. This lets a caller drive an "open mic"
/// session that survives natural pauses in speech.
@MainActor
final class SpeechRecognitionService: ObservableObject {
    @Published private(set) var transcript: String = ""
    @Published private(set) var isListening: Bool = false
    @Published private(set) var error: String?

    /// When `true`, finalised recognition tasks are restarted on the same
    /// audio session so the caller sees an uninterrupted stream of transcript
    /// updates across silence pauses. Defaults to `true` because the in-app
    /// callers (sentence reader) want auto-advance behaviour; the typed-quiz
    /// "Speak" mode flips this to `false`.
    var continuousMode: Bool = true

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    /// Accumulated final-result text from previous recognition cycles in the
    /// current `isListening` session. The published `transcript` is this
    /// prefix concatenated with the live partial from the active task, so
    /// callers see a stable, ever-growing string across silence cuts.
    private var transcriptPrefix: String = ""

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

        if !speechGranted || !micGranted {
            AppLog.speech.notice("permission denied speech=\(speechGranted, privacy: .public) mic=\(micGranted, privacy: .public)")
        }
        return speechGranted && micGranted
    }

    /// Begins live capture and streams partial recognition results into
    /// `transcript`. Throws if the Japanese recognizer is missing or the
    /// audio session cannot be configured.
    func start() throws {
        guard !isListening else { return }
        guard let recognizer, recognizer.isAvailable else {
            AppLog.speech.error("start failed: recognizer unavailable")
            throw SpeechRecognitionError.unavailable
        }
        AppLog.speech.info("session start continuous=\(self.continuousMode, privacy: .public) onDevice=\(recognizer.supportsOnDeviceRecognition, privacy: .public)")

        // Tear down any lingering state from a previous session.
        task?.cancel()
        task = nil

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            // Forward the buffer onto whichever request is currently active.
            // The request gets swapped out under us when a continuous-mode
            // restart happens, so we read it through `self` rather than
            // capturing it.
            Task { @MainActor [weak self] in
                self?.request?.append(buffer)
            }
        }
        engine.prepare()
        try engine.start()
        self.audioEngine = engine

        transcript = ""
        transcriptPrefix = ""
        error = nil
        isListening = true

        installRecognitionTask(on: recognizer)
    }

    /// Spins up a fresh `SFSpeechRecognitionTask` against the existing audio
    /// engine. Called from `start()` for the first cycle and again from the
    /// completion handler when `continuousMode` is on and the previous task
    /// finalised.
    private func installRecognitionTask(on recognizer: SFSpeechRecognizer) {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        task = recognizer.recognitionTask(with: request) { [weak self] result, err in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    let live = result.bestTranscription.formattedString
                    if result.isFinal {
                        // Fold the finalised cycle into the prefix so the
                        // next cycle starts from a stable accumulated string.
                        let glue = self.transcriptPrefix.isEmpty || live.isEmpty ? "" : " "
                        self.transcriptPrefix = self.transcriptPrefix + glue + live
                        self.transcript = self.transcriptPrefix
                    } else {
                        let glue = self.transcriptPrefix.isEmpty || live.isEmpty ? "" : " "
                        self.transcript = self.transcriptPrefix + glue + live
                    }
                }

                let finished = (result?.isFinal ?? false)
                if err != nil || finished {
                    if let err {
                        let nsErr = err as NSError
                        // 203 = no speech, 216 = cancelled, 1110 = silence
                        // cutoff, 1101/301 = server timeout (treated as a
                        // recoverable cycle restart in continuous mode).
                        let recoverable = nsErr.domain == "kAFAssistantErrorDomain"
                            && (nsErr.code == 203 || nsErr.code == 216
                                || nsErr.code == 1110 || nsErr.code == 1101
                                || nsErr.code == 301)
                        if !recoverable {
                            AppLog.speech.error("recognition error domain=\(nsErr.domain, privacy: .public) code=\(nsErr.code, privacy: .public) desc=\(nsErr.localizedDescription, privacy: .public)")
                            self.error = nsErr.localizedDescription
                        }
                    }

                    // Tear down the finished task + request without killing
                    // the audio engine, then either restart (continuous) or
                    // fully stop.
                    self.task = nil
                    self.request = nil

                    if self.isListening,
                       self.continuousMode,
                       let recognizer = self.recognizer,
                       recognizer.isAvailable {
                        AppLog.speech.debug("auto-recovery: restarting recognition task")
                        self.installRecognitionTask(on: recognizer)
                    } else {
                        self.teardown()
                    }
                }
            }
        }
    }

    /// Stops capture and finalises any in-flight recognition. The last
    /// observed `transcript` value remains so the user can edit it.
    func stop() {
        guard isListening else { return }
        AppLog.speech.info("session stop transcriptChars=\(self.transcript.count, privacy: .public)")
        // Flip the flag first so the recognition-task completion handler
        // doesn't try to spin up a replacement task under continuous mode.
        isListening = false
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
