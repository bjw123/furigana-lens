import SwiftUI
import SwiftData
import Speech
import UIKit

/// Reusable speech-check sheet: shows a Japanese prompt (sentence or word),
/// and walks the learner through it chunk-by-chunk so the speech recogniser
/// doesn't have to swallow a whole sentence in one breath. Chunks are
/// auto-derived from the morphological tokenisation (one chunk per
/// content-bearing token; particles and punctuation glue to the preceding
/// chunk) and can be merged, split or removed by the learner before they
/// start reading.
///
/// Mirrors the per-token diff + struggling-kanji congratulation + save-missed-
/// word flow from `SessionRunner` in `KanjiTypedReviewView`, but operates
/// over an arbitrary sentence/reading pair rather than the kanji-quiz queue.
/// The two implementations are intentionally kept separate so the kanji-quiz
/// path stays untouched.
struct SentenceSpeechCheckView: View {
    let sentence: String
    let expectedReading: String
    let meaning: String
    var showFurigana: Bool

    @Environment(\.dismiss) var dismiss

    @Query var allCards: [Flashcard]
    @Query var allLogs: [ReviewLog]
    @Query(sort: \Deck.createdAt, order: .reverse) var decks: [Deck]

    @StateObject var speech = SpeechRecognitionService()

    @State var input: String = ""
    @State var authChecked = false
    @State var pendingSaveToken: SaveTokenRequest?
    @State var showFuriganaState: Bool
    @State var chunks: [Chunk] = []
    @State var results: [ChunkResult] = []
    @State var currentIndex: Int = 0
    @State var sessionComplete = false
    @State var isEditing = false
    @State var chunkFeedback: ChunkFeedback?
    /// Portion of the normalised live transcript already accounted for by a
    /// previous chunk's auto-advance. Subsequent matches are looked for in
    /// the suffix after this prefix so we never re-match the same span twice.
    @State var consumedPrefix: String = ""
    /// Snapshot of `consumedPrefix.count` at the moment the *current* chunk
    /// became active. Used to enforce a minimum suffix growth before short
    /// candidate readings (1-2 mora) are allowed to match — prevents the
    /// previous chunk's trailing kana from bleeding into a one-syllable
    /// match for the new chunk.
    @State var chunkConsumedBaseline: Int = 0
    /// Tap-to-set endpoint. When non-nil, the user has chosen to read only up
    /// to (and including) `chunks[targetIndex]` — chunks past it are rendered
    /// as out-of-scope and the session auto-finishes when this chunk is
    /// matched. Default nil = read the whole sentence.
    @State var targetIndex: Int? = nil
    @State var isDictionaryDegraded = false
    /// `nil` once we've confirmed the recogniser is usable, otherwise the
    /// specific reason it's blocked — drives the speech-unavailable banner in
    /// place of the chunk runner. Populated in `.task` on first appearance so
    /// we don't query Speech.framework on the main render path.
    @State var speechUnavailableReason: SpeechUnavailableReason? = nil
    @FocusState var inputFocused: Bool

    init(sentence: String, expectedReading: String, meaning: String, showFurigana: Bool) {
        self.sentence = sentence
        self.expectedReading = expectedReading
        self.meaning = meaning
        self.showFurigana = showFurigana
        _showFuriganaState = State(initialValue: showFurigana)
    }

    var strugglingKanjiChars: Set<Character> {
        Set(StatsService.strugglingKanjiReadings(logs: allLogs, cards: allCards, days: 30, limit: 32).map(\.kanji))
    }

    // MARK: - Chunk model

    /// A user-readable slice of the original sentence. Concatenating every
    /// chunk's `surface` does NOT have to equal the original sentence — the
    /// learner can remove filler pieces (e.g. trailing punctuation) before
    /// starting. Each chunk carries the canonical reading it should produce.
    struct Chunk: Identifiable, Equatable {
        let id: UUID
        var surface: String
        var reading: String   // normalized hiragana, what the user should say
        /// Indices into the parent `segments` array. Kept so we can re-merge
        /// adjacent chunks back into a longer span, and so per-chunk diffs
        /// map back to the original sentence layout.
        var segmentIndices: [Int]

        var hasKanji: Bool {
            surface.unicodeScalars.contains { scalar in
                (0x4E00...0x9FFF).contains(scalar.value) ||
                (0x3400...0x4DBF).contains(scalar.value) ||
                (0xF900...0xFAFF).contains(scalar.value) ||
                (0x20000...0x2A6DF).contains(scalar.value)
            }
        }
    }

    /// Outcome of speaking a single chunk.
    struct ChunkResult: Identifiable, Equatable {
        let id: UUID  // mirrors Chunk.id
        let surface: String
        let expectedReading: String
        let matched: Bool
        /// User chose to skip rather than read this chunk. Distinct from
        /// matched=false (which means they tried and missed) — skips get
        /// a softer visual treatment in the summary.
        let skipped: Bool
        let transcript: String
    }

    /// Inline feedback rendered under the transcript field while the user is
    /// still working through the active chunk. Cleared when the user moves on
    /// to the next chunk (or retries the same one).
    enum ChunkFeedback: Equatable {
        case correct
        case wrong(expected: String, heard: String)
    }

    struct SaveTokenRequest: Identifiable {
        let id = UUID()
        let surface: String
        let reading: String
        let context: String
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WashiBackground()
                ScrollView {
                    VStack(spacing: 18) {
                        if isDictionaryDegraded {
                            ErrorBanner.dictionaryDegraded()
                        }
                        promptView
                        controlsRow
                        if let reason = speechUnavailableReason {
                            // Recogniser is dead in the water — surface a
                            // banner instead of a non-functional chunk runner.
                            // Edit mode is still allowed so the user can
                            // inspect / tweak chunks while waiting on
                            // authorisation.
                            ErrorBanner.speechUnavailable(reason: reason, openSettings: openSystemSettings)
                            if isEditing { editChunksPanel }
                        } else if isEditing {
                            editChunksPanel
                        } else if sessionComplete {
                            summaryView
                        } else {
                            chunkRunner
                        }
                    }
                    .padding(.vertical, 18)
                    .padding(.horizontal, 16)
                }
            }
            .observingDictionaryDegraded($isDictionaryDegraded)
            .task { await refreshSpeechAvailability() }
            .navigationTitle("Read aloud")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(isEditing ? "Done" : "Edit") {
                        if speech.isListening { speech.stop() }
                        isEditing.toggle()
                    }
                    .disabled(sessionComplete && !isEditing)
                }
            }
            .onAppear {
                if chunks.isEmpty {
                    chunks = Self.buildChunks(for: sentence)
                }
            }
            .onChange(of: speech.transcript) { _, new in
                input = new
                processTranscript(new)
            }
            .sheet(item: $pendingSaveToken) { req in
                let meaningLookup = DictionaryService.shared.lookup(req.surface, limit: 1).first
                    .map { $0.glosses().joined(separator: "; ") } ?? ""
                SaveFlashcardSheet(
                    expression: req.surface,
                    reading: req.reading,
                    meaning: meaningLookup.isEmpty ? nil : meaningLookup,
                    meaningSource: meaningLookup.isEmpty ? nil : "JMdict",
                    contextSentence: req.context,
                    decks: decks
                )
            }
        }
    }

    // MARK: - Helpers (state)

    var activeChunk: Chunk? {
        guard currentIndex >= 0, currentIndex < chunks.count else { return nil }
        return chunks[currentIndex]
    }

    var isLastChunk: Bool {
        currentIndex >= chunks.count - 1
    }

    func chunkResult(at index: Int) -> ChunkResult? {
        guard index < chunks.count else { return nil }
        let id = chunks[index].id
        return results.first { $0.id == id }
    }

    func containsKanji(_ s: String) -> Bool {
        s.contains(where: { isKanji($0) })
    }

    func isKanji(_ ch: Character) -> Bool {
        ch.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value) ||
            (0x3400...0x4DBF).contains(scalar.value) ||
            (0xF900...0xFAFF).contains(scalar.value) ||
            (0x20000...0x2A6DF).contains(scalar.value)
        }
    }

    // MARK: - Speech availability

    /// Resolves the current speech-recognition gating: denied/restricted Speech
    /// auth, or a Japanese recogniser that the OS reports as unavailable
    /// (e.g. unsupported device, locale model not downloaded). Returns nil
    /// when everything looks healthy — including `.notDetermined`, since the
    /// mic button will trigger the actual prompt flow on first tap.
    func refreshSpeechAvailability() async {
        let status = SFSpeechRecognizer.authorizationStatus()
        switch status {
        case .denied:
            speechUnavailableReason = .notAuthorized
            return
        case .restricted:
            speechUnavailableReason = .restricted
            return
        case .authorized, .notDetermined:
            break
        @unknown default:
            break
        }
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
        if recognizer == nil || recognizer?.isAvailable == false {
            speechUnavailableReason = .recognizerUnavailable
            return
        }
        speechUnavailableReason = nil
    }

    /// Opens the app's entry in Settings so the user can flip Speech
    /// Recognition / Microphone permissions back on. No-op if the URL isn't
    /// resolvable (basically never, but keeps the call safe).
    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
