import SwiftUI
import SwiftData

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

    @Environment(\.dismiss) private var dismiss

    @Query private var allCards: [Flashcard]
    @Query private var allLogs: [ReviewLog]
    @Query(sort: \Deck.createdAt, order: .reverse) private var decks: [Deck]

    @StateObject private var speech = SpeechRecognitionService()

    @State private var input: String = ""
    @State private var authChecked = false
    @State private var pendingSaveToken: SaveTokenRequest?
    @State private var showFuriganaState: Bool
    @State private var chunks: [Chunk] = []
    @State private var results: [ChunkResult] = []
    @State private var currentIndex: Int = 0
    @State private var sessionComplete = false
    @State private var isEditing = false
    @State private var chunkFeedback: ChunkFeedback?
    /// Portion of the normalised live transcript already accounted for by a
    /// previous chunk's auto-advance. Subsequent matches are looked for in
    /// the suffix after this prefix so we never re-match the same span twice.
    @State private var consumedPrefix: String = ""
    /// Snapshot of `consumedPrefix.count` at the moment the *current* chunk
    /// became active. Used to enforce a minimum suffix growth before short
    /// candidate readings (1-2 mora) are allowed to match — prevents the
    /// previous chunk's trailing kana from bleeding into a one-syllable
    /// match for the new chunk.
    @State private var chunkConsumedBaseline: Int = 0
    /// Tap-to-set endpoint. When non-nil, the user has chosen to read only up
    /// to (and including) `chunks[targetIndex]` — chunks past it are rendered
    /// as out-of-scope and the session auto-finishes when this chunk is
    /// matched. Default nil = read the whole sentence.
    @State private var targetIndex: Int? = nil
    @FocusState private var inputFocused: Bool

    init(sentence: String, expectedReading: String, meaning: String, showFurigana: Bool) {
        self.sentence = sentence
        self.expectedReading = expectedReading
        self.meaning = meaning
        self.showFurigana = showFurigana
        _showFuriganaState = State(initialValue: showFurigana)
    }

    private var strugglingKanjiChars: Set<Character> {
        Set(StatsService.strugglingKanjiReadings(logs: allLogs, cards: allCards, days: 30, limit: 32).map(\.kanji))
    }

    // MARK: - Chunk model

    /// A user-readable slice of the original sentence. Concatenating every
    /// chunk's `surface` does NOT have to equal the original sentence — the
    /// learner can remove filler pieces (e.g. trailing punctuation) before
    /// starting. Each chunk carries the canonical reading it should produce.
    fileprivate struct Chunk: Identifiable, Equatable {
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
    fileprivate struct ChunkResult: Identifiable, Equatable {
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
    fileprivate enum ChunkFeedback: Equatable {
        case correct
        case wrong(expected: String, heard: String)
    }

    fileprivate struct SaveTokenRequest: Identifiable {
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
                        promptView
                        controlsRow
                        if isEditing {
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

    // MARK: - Prompt with active-chunk highlight

    @ViewBuilder
    private var promptView: some View {
        VStack(spacing: 8) {
            highlightedSentence
                .frame(maxWidth: .infinity)
                .padding(.horizontal)
            if !sessionComplete && !isEditing, let chunk = activeChunk {
                VStack(spacing: 2) {
                    Text("Read this part")
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(Palette.mist)
                        .textCase(.uppercase)
                        .tracking(0.6)
                    Text(chunk.surface)
                        .font(.system(.title2, design: .serif))
                        .foregroundStyle(Palette.sumi)
                    if !chunk.reading.isEmpty && chunk.reading != chunk.surface && showFuriganaState {
                        Text(chunk.reading)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Palette.indigo.opacity(0.85))
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity)
                .background(Palette.sakura.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Palette.sakura.opacity(0.45), lineWidth: 0.75)
                )
                .padding(.horizontal)
            }
        }
    }

    /// Sentence rendered as a wrapping flow of chunk-sized capsules. The
    /// active chunk is highlighted, completed chunks are dimmed with a
    /// pass/fail tint, and pending chunks are faded.
    private var highlightedSentence: some View {
        FlowLayout(spacing: 4) {
            ForEach(Array(chunks.enumerated()), id: \.element.id) { idx, chunk in
                chunkPill(chunk: chunk, index: idx)
            }
        }
    }

    @ViewBuilder
    private func chunkPill(chunk: Chunk, index: Int) -> some View {
        let state = chunkPillState(for: index)
        let outOfScope = isOutOfScope(index)
        VStack(spacing: 0) {
            if showFuriganaState && chunk.hasKanji && !chunk.reading.isEmpty && chunk.reading != chunk.surface {
                Text(chunk.reading)
                    .font(.system(size: 10, design: .rounded).weight(.medium))
                    .foregroundStyle(outOfScope ? Palette.mist.opacity(0.4) : state.readingColor)
            }
            Text(chunk.surface)
                .font(.system(.title3, design: .serif))
                .foregroundStyle(outOfScope ? Palette.sumi.opacity(0.25) : state.surfaceColor)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(outOfScope ? Color.clear : state.background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(outOfScope ? Color.clear : state.border, lineWidth: state.borderWidth)
        )
        .opacity(outOfScope ? 0.4 : state.opacity)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture {
            handleChunkTap(index: index)
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Read up to \(chunk.surface)")
    }

    /// Index past which chunks are styled as out-of-scope (greyed out, no
    /// pill). When `targetIndex` is nil the user is reading the whole
    /// sentence — nothing is out of scope.
    private func isOutOfScope(_ index: Int) -> Bool {
        guard let target = targetIndex else { return false }
        return index > target
    }

    /// Tap on a chunk → set it as the new endpoint. Tapping the SAME chunk
    /// twice clears the endpoint (back to "read the whole sentence"). Tapping
    /// a chunk EARLIER than the current index is a no-op (you can't un-read
    /// chunks you already finished).
    private func handleChunkTap(index: Int) {
        guard index >= currentIndex else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if targetIndex == index {
            targetIndex = nil
        } else {
            targetIndex = index
        }
    }

    private struct ChunkPillState {
        let background: Color
        let border: Color
        let borderWidth: CGFloat
        let surfaceColor: Color
        let readingColor: Color
        let opacity: Double
    }

    private func chunkPillState(for index: Int) -> ChunkPillState {
        // Look up any prior result for this chunk id.
        let result = chunkResult(at: index)
        if let result {
            if result.matched {
                return ChunkPillState(
                    background: Palette.bamboo.opacity(0.15),
                    border: Palette.bamboo.opacity(0.45),
                    borderWidth: 0.75,
                    surfaceColor: Palette.bamboo,
                    readingColor: Palette.bamboo.opacity(0.85),
                    opacity: 0.95
                )
            } else if result.skipped {
                // Softer treatment than vermillion — skipping isn't failing.
                return ChunkPillState(
                    background: Palette.mist.opacity(0.15),
                    border: Palette.mist.opacity(0.40),
                    borderWidth: 0.75,
                    surfaceColor: Palette.sumi.opacity(0.55),
                    readingColor: Palette.mist,
                    opacity: 0.85
                )
            } else {
                return ChunkPillState(
                    background: Palette.vermillion.opacity(0.18),
                    border: Palette.vermillion.opacity(0.55),
                    borderWidth: 0.75,
                    surfaceColor: Palette.vermillion,
                    readingColor: Palette.vermillion.opacity(0.85),
                    opacity: 0.95
                )
            }
        }
        if index == currentIndex && !sessionComplete && !isEditing {
            return ChunkPillState(
                background: Palette.sakura.opacity(0.22),
                border: Palette.sakura.opacity(0.65),
                borderWidth: 1.0,
                surfaceColor: Palette.sumi,
                readingColor: Palette.indigo.opacity(0.85),
                opacity: 1.0
            )
        }
        // Post-session pending chunks (never heard, never explicitly wrong)
        // get a softly tinted gold to call them out without the harsh
        // vermillion of a real failure.
        if sessionComplete {
            return ChunkPillState(
                background: Palette.gold.opacity(0.12),
                border: Palette.gold.opacity(0.45),
                borderWidth: 0.75,
                surfaceColor: Palette.sumi.opacity(0.7),
                readingColor: Palette.indigo.opacity(0.7),
                opacity: 0.9
            )
        }
        return ChunkPillState(
            background: .clear,
            border: .clear,
            borderWidth: 0,
            surfaceColor: Palette.sumi.opacity(0.55),
            readingColor: Palette.indigo.opacity(0.55),
            opacity: 0.85
        )
    }

    // MARK: - Controls row

    private var controlsRow: some View {
        HStack {
            Toggle("Show furigana", isOn: $showFuriganaState)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Palette.mist)
                .tint(Palette.indigo)
                .fixedSize()
            Spacer()
            if !sessionComplete && !isEditing {
                Text("\(min(currentIndex + 1, max(chunks.count, 1))) / \(max(chunks.count, 1))")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(Palette.mist)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Palette.washi))
                    .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 0.5))
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Active chunk runner

    @ViewBuilder
    private var chunkRunner: some View {
        if activeChunk != nil {
            VStack(spacing: 14) {
                micRow
                transcriptField
                Text(speech.isListening
                     ? "Read the sentence at your own pace — each part lights up green as it's heard."
                     : "Tap the mic and read the sentence aloud. The session ends when every part matches.")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Palette.mist)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                chunkFeedbackView
                manualOverrideRow
                    .padding(.horizontal)
                finishEarlyButton
                    .padding(.horizontal)
            }
        } else {
            // No chunks to read — e.g. user removed them all in edit mode.
            VStack(spacing: 10) {
                Text("Nothing to read")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Palette.sumi)
                Text("Tap Edit to add some words back.")
                    .font(.caption)
                    .foregroundStyle(Palette.mist)
            }
            .padding()
        }
    }

    private var micRow: some View {
        HStack(spacing: 10) {
            Button {
                Task { await toggleListening() }
            } label: {
                Image(systemName: speech.isListening ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(speech.isListening ? Palette.vermillion : Palette.indigo)
            }
            .disabled(!speech.isAvailable && !speech.isListening)
            if speech.isListening {
                Text("Listening…")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(Palette.vermillion)
            }
        }
    }

    @ViewBuilder
    private var transcriptField: some View {
        // While the recogniser is live the transcript is a read-only mirror so
        // a stray keystroke can't desync the live transcript-watching logic.
        // When the mic is off, the user can still hand-edit if they want to
        // visually inspect what was captured.
        if speech.isListening {
            Text(input.isEmpty ? "Listening…" : input)
                .font(.system(.title3, design: .rounded))
                .foregroundStyle(input.isEmpty ? Palette.mist : Palette.sumi)
                .frame(maxWidth: .infinity, minHeight: 28)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Palette.cream, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(strokeColor, lineWidth: 1)
                )
                .padding(.horizontal)
        } else {
            TextField("What you said", text: $input)
                .focused($inputFocused)
                .submitLabel(.done)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(.title3, design: .rounded))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Palette.cream, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(strokeColor, lineWidth: 1)
                )
                .padding(.horizontal)
        }
    }

    private var strokeColor: Color {
        switch chunkFeedback {
        case .correct: return Palette.bamboo.opacity(0.85)
        case .wrong: return Palette.vermillion.opacity(0.85)
        case nil: return Palette.hairline
        }
    }

    @ViewBuilder
    private var chunkFeedbackView: some View {
        switch chunkFeedback {
        case .correct:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                Text("Nice — moving on")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
            }
            .foregroundStyle(Palette.bamboo)
        case .wrong(let expected, let heard):
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("Not quite")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                }
                .foregroundStyle(Palette.vermillion)
                Text("Expected: \(expected)")
                    .font(.caption)
                    .foregroundStyle(Palette.sumi.opacity(0.85))
                if !heard.isEmpty {
                    Text("Heard: \(heard)")
                        .font(.caption2)
                        .foregroundStyle(Palette.mist)
                }
            }
            .padding(.horizontal)
        case nil:
            EmptyView()
        }
    }

    /// Two-button row offered when the mic is live: "I read this" (validates
    /// the transcript and only advances if the chunk actually appears) and
    /// "Skip" (advances without marking correct — for when the recogniser is
    /// fighting the user on a particular word and they just want to move on).
    @ViewBuilder
    private var manualOverrideRow: some View {
        if let chunk = activeChunk {
            HStack(spacing: 8) {
                if speech.isListening {
                    Button {
                        manuallyAdvance(chunk: chunk)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "hand.tap.fill")
                                .font(.caption2)
                            Text("I read \"\(chunk.surface)\"")
                                .font(.system(.caption, design: .rounded).weight(.semibold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Palette.indigo.opacity(0.12)))
                        .foregroundStyle(Palette.indigo)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("I read \(chunk.surface)")
                }

                Button {
                    skipCurrentChunk()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "forward.fill")
                            .font(.caption2)
                        Text("Skip")
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Palette.mist.opacity(0.18)))
                    .foregroundStyle(Palette.mist)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Skip this chunk")
            }
        }
    }

    /// While listening, give the user a way to end the session early without
    /// dropping back to the mic toggle. Pending (un-heard) chunks land in the
    /// summary's save-list alongside any explicit misses.
    @ViewBuilder
    private var finishEarlyButton: some View {
        if speech.isListening {
            Button { finishSessionEarly() } label: {
                Text("Finish session").frame(maxWidth: .infinity)
            }
            .buttonStyle(WashiButtonStyle())
        }
    }

    // MARK: - Edit mode

    private var editChunksPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Group, split or remove chunks")
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Palette.mist)
                .textCase(.uppercase)
                .tracking(0.6)
                .padding(.horizontal, 16)

            VStack(spacing: 8) {
                ForEach(Array(chunks.enumerated()), id: \.element.id) { idx, chunk in
                    editRow(chunk: chunk, index: idx)
                }
                if chunks.isEmpty {
                    Text("All chunks removed — tap Reset to restore.")
                        .font(.caption)
                        .foregroundStyle(Palette.mist)
                        .padding(.horizontal, 16)
                }
            }
            .padding(.horizontal, 8)

            HStack {
                Button {
                    chunks = Self.buildChunks(for: sentence)
                    resetSession()
                } label: {
                    Label("Reset chunks", systemImage: "arrow.counterclockwise")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Palette.indigo.opacity(0.12)))
                        .foregroundStyle(Palette.indigo)
                }
                .buttonStyle(.plain)
                Spacer()
                Button {
                    resetSession()
                    isEditing = false
                } label: {
                    Text("Start reading")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Palette.sumi))
                        .foregroundStyle(Palette.cream)
                }
                .buttonStyle(.plain)
                .disabled(chunks.isEmpty)
                .opacity(chunks.isEmpty ? 0.5 : 1.0)
            }
            .padding(.horizontal, 16)
        }
    }

    private func editRow(chunk: Chunk, index: Int) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(chunk.surface)
                    .font(.system(.title3, design: .serif))
                    .foregroundStyle(Palette.sumi)
                if !chunk.reading.isEmpty && chunk.reading != chunk.surface {
                    Text(chunk.reading)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Palette.indigo.opacity(0.85))
                }
            }
            Spacer()
            // Merge with next: glues this chunk into the next one so the user
            // reads them as a single unit. Disabled on the last row.
            Button {
                mergeChunk(at: index)
            } label: {
                Image(systemName: "arrow.down.to.line.compact")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Palette.indigo.opacity(0.12)))
                    .foregroundStyle(Palette.indigo)
            }
            .buttonStyle(.plain)
            .disabled(index >= chunks.count - 1)
            .opacity(index >= chunks.count - 1 ? 0.35 : 1.0)
            .accessibilityLabel("Merge with next chunk")

            // Split back: break this chunk into its underlying segments. Only
            // useful if it currently spans more than one segment.
            Button {
                splitChunk(at: index)
            } label: {
                Image(systemName: "scissors")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Palette.gold.opacity(0.15)))
                    .foregroundStyle(Palette.gold)
            }
            .buttonStyle(.plain)
            .disabled(chunk.segmentIndices.count <= 1)
            .opacity(chunk.segmentIndices.count <= 1 ? 0.35 : 1.0)
            .accessibilityLabel("Split chunk")

            Button(role: .destructive) {
                removeChunk(at: index)
            } label: {
                Image(systemName: "trash.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Palette.vermillion.opacity(0.15)))
                    .foregroundStyle(Palette.vermillion)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove chunk")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Palette.washi, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 0.5)
        )
    }

    // MARK: - Completion summary

    @ViewBuilder
    private var summaryView: some View {
        // All chunks got a `matched: true` result AND none are pending (i.e.
        // every chunk in the list has a corresponding result entry).
        let allMatched = !chunks.isEmpty
            && chunks.allSatisfy { chunk in
                results.contains { $0.id == chunk.id && $0.matched }
            }
        let solvedStruggling: [Character] = allMatched
            ? Array(Set(sentence.filter { isKanji($0) }).intersection(strugglingKanjiChars)).sorted()
            : []
        VStack(spacing: 14) {
            if allMatched {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                    Text("Read aloud correctly!")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                }
                .foregroundStyle(Palette.bamboo)
                if !solvedStruggling.isEmpty {
                    VStack(spacing: 8) {
                        Text("You read kanji you've been struggling with: \(solvedStruggling.map { String($0) }.joined(separator: " "))")
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(Palette.sumi)
                            .multilineTextAlignment(.center)
                        HStack(spacing: 6) {
                            ForEach(Array(solvedStruggling.enumerated()), id: \.offset) { _, ch in
                                KanjiGemBadge(kanji: String(ch), tint: Palette.gold, size: 36)
                            }
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(Palette.gold.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Palette.gold.opacity(0.5), lineWidth: 0.75)
                    )
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(pendingOrMissedHeadline)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                }
                .foregroundStyle(Palette.vermillion)
                missedChunksSection
            }
            if !meaning.isEmpty {
                Text(meaning)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Palette.sumi.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            VStack(spacing: 8) {
                Button {
                    resetSession()
                } label: {
                    Text("Try again").frame(maxWidth: .infinity)
                }
                .buttonStyle(SumiButtonStyle())
                Button { dismiss() } label: {
                    Text("Done").frame(maxWidth: .infinity)
                }
                .buttonStyle(WashiButtonStyle())
            }
            .padding(.horizontal)
        }
        .padding(.horizontal)
    }

    /// Chunks the user never matched — either explicit wrong results, or
    /// chunks that simply never got their candidate reading in the suffix
    /// before the session ended. Both end up in the save-list because the
    /// learner cares about the *word*, not how the session ended.
    private var unmatchedChunks: [Chunk] {
        chunks.filter { chunk in
            !results.contains { $0.id == chunk.id && $0.matched }
        }
    }

    private var pendingOrMissedHeadline: String {
        let unmatchedCount = unmatchedChunks.count
        if unmatchedCount == chunks.count {
            return "Session stopped — nothing matched"
        }
        return unmatchedCount == 1 ? "1 part wasn't heard" : "\(unmatchedCount) parts weren't heard"
    }

    @ViewBuilder
    private var missedChunksSection: some View {
        let unmatched = unmatchedChunks
        if !unmatched.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Save these as flashcards")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(Palette.sumi.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
                FlowLayout(spacing: 6) {
                    ForEach(unmatched.filter { containsKanji($0.surface) }) { chunk in
                        Button {
                            pendingSaveToken = SaveTokenRequest(
                                surface: chunk.surface,
                                reading: chunk.reading,
                                context: sentence
                            )
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "bookmark.fill")
                                    .font(.caption2)
                                Text(chunk.surface)
                                    .font(.system(.subheadline, design: .serif))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule().fill(Palette.indigo.opacity(0.12))
                            )
                            .foregroundStyle(Palette.indigo)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Helpers (state)

    private var activeChunk: Chunk? {
        guard currentIndex >= 0, currentIndex < chunks.count else { return nil }
        return chunks[currentIndex]
    }

    private var isLastChunk: Bool {
        currentIndex >= chunks.count - 1
    }

    private func chunkResult(at index: Int) -> ChunkResult? {
        guard index < chunks.count else { return nil }
        let id = chunks[index].id
        return results.first { $0.id == id }
    }

    private func containsKanji(_ s: String) -> Bool {
        s.contains(where: { isKanji($0) })
    }

    private func isKanji(_ ch: Character) -> Bool {
        ch.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value) ||
            (0x3400...0x4DBF).contains(scalar.value) ||
            (0xF900...0xFAFF).contains(scalar.value) ||
            (0x20000...0x2A6DF).contains(scalar.value)
        }
    }

    // MARK: - Continuous auto-advance

    /// Candidate normalised readings the live transcript suffix must contain
    /// for `chunk` to count as spoken. Mirrors the per-chunk Submit logic the
    /// view used to do on demand, but built up-front because the transcript
    /// stream may match the same chunk many times during a single utterance.
    ///
    /// Sources:
    ///   1. Tokenizer reading (fast, occasionally wrong on compounds).
    ///   2. Surface form (covers transcripts that came back as kanji).
    ///   3. Every JMdict kana form for the surface — the canonical compound
    ///      reading lives here.
    /// All candidates are folded through `AnswerNormalizer` so kana/katakana/
    /// romaji + long-vowel marks reduce to the same hiragana stem.
    private func candidates(for chunk: Chunk) -> [String] {
        var raw: [String] = [chunk.reading, chunk.surface]
        let dictEntries = DictionaryService.shared.lookup(chunk.surface, limit: 3)
        // Apple's Japanese recogniser picks a kanji form based on context and
        // can land on a DIFFERENT kanji that shares the same reading as the
        // chunk's surface (e.g. it might write 判る where the chunk wrote
        // 分かる). Both are valid spellings of わかる per JMdict — and JMdict's
        // `kanji` array on a single entry contains every accepted spelling.
        // Including them all as candidates makes the matching tolerant of the
        // recogniser's kanji-disambiguation choice. Adding `kana` covers the
        // case where the recogniser falls back to hiragana / katakana.
        raw.append(contentsOf: dictEntries.flatMap { $0.kana })
        raw.append(contentsOf: dictEntries.flatMap { $0.kanji })
        return raw
            .map(AnswerNormalizer.normalizeReading)
            .filter { !$0.isEmpty }
    }

    /// Drives the auto-advance loop. Folds the live transcript, slices off
    /// the prefix already consumed by past chunks, and if the suffix contains
    /// any candidate for the current chunk, marks it correct and advances.
    /// Loops because a single transcript update can resolve multiple chunks
    /// at once when the user reads quickly.
    private func processTranscript(_ raw: String) {
        guard speech.isListening || !raw.isEmpty else { return }
        guard !sessionComplete else { return }
        let normalised = AnswerNormalizer.normalizeReading(raw)

        // If the recogniser truncated the transcript (rare — happens when a
        // cycle restarts and the new partial is shorter than the prefix), pull
        // `consumedPrefix` back so we don't get stuck.
        if !consumedPrefix.isEmpty, !normalised.hasPrefix(consumedPrefix) {
            consumedPrefix = ""
            chunkConsumedBaseline = 0
        }

        var progressed = true
        while progressed, currentIndex < chunks.count {
            progressed = false
            let chunk = chunks[currentIndex]
            let suffix = String(normalised.dropFirst(consumedPrefix.count))
            guard !suffix.isEmpty else { break }

            let cands = candidates(for: chunk)
            guard !cands.isEmpty else {
                // Nothing to match against (empty reading + empty surface) —
                // skip the chunk so the user isn't blocked.
                advanceCurrentChunk(matched: false, transcriptForResult: nil)
                progressed = true
                continue
            }

            // Short-reading guard: only applied AFTER the user has already
            // consumed at least one chunk. For short kana readings (1-2 mora),
            // require enough new suffix growth since this chunk became active
            // so a stray particle at the end of the previous chunk doesn't
            // pre-match the next one. For the FIRST chunk (consumedPrefix
            // empty), no guard — the suffix IS the entire transcript and we
            // want auto-advance to fire immediately on the very first match.
            // We also restrict the "short" heuristic to kana-only candidates,
            // because a kanji surface like 人間 happens to be 2 characters
            // but represents 4 mora of speech — guarding it would be wrong.
            if !consumedPrefix.isEmpty {
                let kanaShortest = cands
                    .filter { cand in
                        cand.unicodeScalars.allSatisfy { (0x3040...0x309F).contains($0.value) }
                    }
                    .map(\.count)
                    .min() ?? Int.max
                let suffixGrowthSinceActive = consumedPrefix.count - chunkConsumedBaseline
                if kanaShortest <= 2, suffixGrowthSinceActive < max(kanaShortest - 1, 0) {
                    // Don't try to match this chunk yet — wait for more audio.
                    break
                }
            }

            // Look for the earliest position in `suffix` that contains any
            // candidate as a contiguous substring. Picking the earliest hit
            // keeps the consumed prefix tight against the spoken span.
            var bestEnd: Int?
            for cand in cands {
                if let range = suffix.range(of: cand) {
                    let endOffset = suffix.distance(from: suffix.startIndex, to: range.upperBound)
                    if bestEnd == nil || endOffset < bestEnd! {
                        bestEnd = endOffset
                    }
                }
            }

            // Strict substring failed — try fuzzy matching anchored at the
            // start of `suffix`. This catches the case where words running
            // together without a pause make the recognizer mangle a chunk
            // boundary (e.g. reading "ストレスでしょ" continuously gets
            // transcribed as "ストレッスでしょ" with a stray small-tsu, so
            // "すとれす" doesn't appear as a clean substring). Allowed edit
            // distance scales with candidate length: ≈ 1 edit per 4 chars.
            if bestEnd == nil {
                bestEnd = fuzzyMatchEnd(in: suffix, against: cands)
            }
            guard let endOffset = bestEnd else { break }

            // Snap consumedPrefix forward through the matched span.
            let newPrefixCount = consumedPrefix.count + endOffset
            consumedPrefix = String(normalised.prefix(newPrefixCount))
            advanceCurrentChunk(matched: true, transcriptForResult: chunk.surface)
            progressed = true
        }

        if shouldFinishAfterAdvance() {
            finishSession()
        }
    }

    /// True when the user has either reached the natural end of the sentence
    /// (`currentIndex >= chunks.count`) OR has matched their tap-chosen
    /// endpoint (`currentIndex > targetIndex`).
    private func shouldFinishAfterAdvance() -> Bool {
        if currentIndex >= chunks.count { return true }
        if let target = targetIndex, currentIndex > target { return true }
        return false
    }

    /// Marks the active chunk's outcome and bumps the index. Does NOT touch
    /// `consumedPrefix` — the caller handles that.
    private func advanceCurrentChunk(matched: Bool, transcriptForResult: String?, skipped: Bool = false) {
        guard currentIndex < chunks.count else { return }
        let chunk = chunks[currentIndex]
        results.removeAll { $0.id == chunk.id }
        results.append(ChunkResult(
            id: chunk.id,
            surface: chunk.surface,
            expectedReading: chunk.reading,
            matched: matched,
            skipped: skipped,
            transcript: transcriptForResult ?? ""
        ))
        if matched {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            chunkFeedback = .correct
        }
        currentIndex += 1
        chunkConsumedBaseline = consumedPrefix.count
    }

    /// User-initiated skip. The chunk doesn't count as correct, but it doesn't
    /// count as a hard failure either — it lands in the summary as a
    /// "skipped" entry the user can still save as a flashcard. Used when the
    /// speech recognizer is fighting them on a particular word.
    private func skipCurrentChunk() {
        guard currentIndex < chunks.count else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        chunkFeedback = nil
        advanceCurrentChunk(matched: false, transcriptForResult: nil, skipped: true)
        if shouldFinishAfterAdvance() {
            finishSession()
        }
    }

    /// Manual "I read this" override — checks the current live transcript
    /// against the chunk's candidate readings before advancing. If the user
    /// hasn't actually said the chunk yet, marks it WRONG and shows what was
    /// heard vs. what was expected, so the button can't be abused to skip
    /// past a chunk by saying the wrong word.
    private func manuallyAdvance(chunk: Chunk) {
        guard let idx = chunks.firstIndex(where: { $0.id == chunk.id }), idx == currentIndex else { return }

        let normalised = AnswerNormalizer.normalizeReading(speech.transcript)
        let suffix = String(normalised.dropFirst(consumedPrefix.count))
        let cands = candidates(for: chunk)

        // Match logic mirrors the auto-advance pass — any candidate appearing
        // in the un-consumed suffix counts. Empty transcript (user pressed the
        // button without saying anything) is treated as wrong.
        var matchedEnd: Int?
        for cand in cands where !cand.isEmpty {
            if let range = suffix.range(of: cand) {
                let endOffset = suffix.distance(from: suffix.startIndex, to: range.upperBound)
                if matchedEnd == nil || endOffset < matchedEnd! {
                    matchedEnd = endOffset
                }
            }
        }

        if let endOffset = matchedEnd {
            // Snap consumedPrefix forward through the matched span so further
            // auto-advance from the same transcript update keeps working.
            let newPrefixCount = consumedPrefix.count + endOffset
            consumedPrefix = String(normalised.prefix(newPrefixCount))
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            advanceCurrentChunk(matched: true, transcriptForResult: chunk.surface)
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            chunkFeedback = .wrong(
                expected: chunk.reading,
                heard: speech.transcript.isEmpty ? "(nothing yet)" : speech.transcript
            )
            // Record the failure as a chunk result but DON'T advance — the
            // user gets a try-again chance.
            results.removeAll { $0.id == chunk.id }
            results.append(ChunkResult(
                id: chunk.id,
                surface: chunk.surface,
                expectedReading: chunk.reading,
                matched: false,
                skipped: false,
                transcript: speech.transcript
            ))
            return
        }
        if shouldFinishAfterAdvance() {
            finishSession()
        }
    }

    /// Wraps up the session normally — recogniser off, summary on. Any chunks
    /// the user didn't reach simply have no `results` entry and the summary
    /// shows them as pending.
    private func finishSession() {
        if speech.isListening { speech.stop() }
        sessionComplete = true
        chunkFeedback = nil
    }

    /// User-initiated early end — same as `finishSession` but explicit so the
    /// call-site reads clearly.
    private func finishSessionEarly() {
        finishSession()
    }

    private func resetSession() {
        results.removeAll()
        currentIndex = 0
        input = ""
        chunkFeedback = nil
        sessionComplete = false
        consumedPrefix = ""
        chunkConsumedBaseline = 0
    }

    // MARK: - Edit operations

    private func mergeChunk(at index: Int) {
        guard index >= 0, index < chunks.count - 1 else { return }
        let first = chunks[index]
        let second = chunks[index + 1]
        let merged = Chunk(
            id: UUID(),
            surface: first.surface + second.surface,
            reading: AnswerNormalizer.normalizeReading(first.reading + second.reading),
            segmentIndices: first.segmentIndices + second.segmentIndices
        )
        chunks.replaceSubrange(index...(index + 1), with: [merged])
        resetSession()
    }

    private func splitChunk(at index: Int) {
        guard index >= 0, index < chunks.count else { return }
        let chunk = chunks[index]
        guard chunk.segmentIndices.count > 1 else { return }
        let segments = JapaneseAnalysisService.shared.segments(sentence)
        let replacements: [Chunk] = chunk.segmentIndices.map { segIdx in
            let surface = segIdx < segments.count ? segments[segIdx].surface : ""
            let reading = segIdx < segments.count ? segments[segIdx].reading : ""
            return Chunk(
                id: UUID(),
                surface: surface,
                reading: AnswerNormalizer.normalizeReading(reading),
                segmentIndices: [segIdx]
            )
        }.filter { !$0.surface.isEmpty }
        chunks.replaceSubrange(index...index, with: replacements)
        resetSession()
    }

    private func removeChunk(at index: Int) {
        guard index >= 0, index < chunks.count else { return }
        chunks.remove(at: index)
        resetSession()
    }

    // MARK: - Speech

    private func toggleListening() async {
        if !authChecked {
            _ = await speech.requestAuthorization()
            authChecked = true
        }
        if speech.isListening {
            // Pressing mic again while live ends the session — same flow as
            // tapping "Finish session". Anything not yet matched lands in
            // the pending bucket in the summary.
            finishSessionEarly()
        } else {
            input = ""
            chunkFeedback = nil
            consumedPrefix = ""
            chunkConsumedBaseline = 0
            // Continuous reading needs the service to keep listening across
            // silence pauses — flip the flag back on (it's the default but
            // KanjiTypedReviewView shares the same type and disables it).
            speech.continuousMode = true
            do { try speech.start() } catch {
                // Service exposes the error on its own publisher; we don't
                // surface inline failures here.
            }
        }
    }

    // MARK: - Chunk building

    /// Build the initial chunk list from the sentence. One chunk per content-
    /// bearing token (kanji-containing or kana run of length ≥ 2); particles,
    /// short kana, punctuation and whitespace glue onto the preceding chunk
    /// so each chunk reads as a natural sub-phrase. If the heuristic produces
    /// no content chunk, fall back to a single chunk for the entire sentence.
    fileprivate static func buildChunks(for sentence: String) -> [Chunk] {
        let segments = JapaneseAnalysisService.shared.segments(sentence)
        guard !segments.isEmpty else {
            let reading = JapaneseAnalysisService.shared.localReading(for: sentence)
            return [Chunk(
                id: UUID(),
                surface: sentence,
                reading: AnswerNormalizer.normalizeReading(reading),
                segmentIndices: []
            )]
        }

        var chunks: [Chunk] = []
        for (idx, seg) in segments.enumerated() {
            let isAnchor = seg.hasKanji || (seg.hasKana && seg.surface.count >= 2)
            if isAnchor || chunks.isEmpty {
                chunks.append(Chunk(
                    id: UUID(),
                    surface: seg.surface,
                    reading: AnswerNormalizer.normalizeReading(seg.reading),
                    segmentIndices: [idx]
                ))
            } else {
                // Glue onto the previous chunk.
                var last = chunks.removeLast()
                last.surface += seg.surface
                last.reading = AnswerNormalizer.normalizeReading(last.reading + seg.reading)
                last.segmentIndices.append(idx)
                chunks.append(last)
            }
        }

        // Drop any chunks that ended up empty / whitespace-only after gluing
        // AND any chunks whose surface is just punctuation / quote marks
        // (e.g. a leading 「 or trailing 。) — those have nothing to speak
        // and otherwise show up as empty / orphan capsules in the UI.
        chunks = chunks.filter { chunk in
            let trimmed = chunk.surface.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            return trimmed.unicodeScalars.contains { scalar in
                // Hiragana
                (0x3040...0x309F).contains(scalar.value)
                    // Katakana (full + halfwidth)
                    || (0x30A0...0x30FF).contains(scalar.value)
                    || (0xFF66...0xFF9D).contains(scalar.value)
                    // CJK Unified Ideographs + common extensions
                    || (0x4E00...0x9FFF).contains(scalar.value)
                    || (0x3400...0x4DBF).contains(scalar.value)
                    || (0xF900...0xFAFF).contains(scalar.value)
                    || (0x20000...0x2A6DF).contains(scalar.value)
            }
        }

        if chunks.isEmpty {
            let reading = JapaneseAnalysisService.shared.localReading(for: sentence)
            return [Chunk(
                id: UUID(),
                surface: sentence,
                reading: AnswerNormalizer.normalizeReading(reading),
                segmentIndices: Array(segments.indices)
            )]
        }
        return chunks
    }
}

// MARK: - Fuzzy matching

/// Find the earliest end-offset in `suffix` where any of `candidates` matches
/// with an edit distance below ≈ candidate.count / 4. Anchored at the start
/// of the suffix so we don't jump across chunks. Returns nil when no
/// candidate matches within the tolerance.
fileprivate func fuzzyMatchEnd(in suffix: String, against candidates: [String]) -> Int? {
    let suffixArr = Array(suffix)
    var bestEnd: Int?
    for cand in candidates where cand.count >= 2 {
        let candArr = Array(cand)
        // 1 edit per 4 chars, minimum 1. Cap at 3 so we don't accept wildly
        // different strings — for very long candidates that's still ≈ 25%
        // fuzziness which is plenty for transcription drift.
        let tolerance = min(3, max(1, candArr.count / 4))
        let minLen = max(1, candArr.count - tolerance)
        let maxLen = min(candArr.count + tolerance, suffixArr.count)
        guard minLen <= maxLen else { continue }
        for windowLen in minLen...maxLen {
            let window = Array(suffixArr.prefix(windowLen))
            if levenshtein(candArr, window) <= tolerance {
                if bestEnd == nil || windowLen < bestEnd! {
                    bestEnd = windowLen
                }
                break  // accept the shortest matching window for this candidate
            }
        }
    }
    return bestEnd
}

fileprivate func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
    let m = a.count
    let n = b.count
    if m == 0 { return n }
    if n == 0 { return m }
    var prev = Array(0...n)
    var curr = Array(repeating: 0, count: n + 1)
    for i in 1...m {
        curr[0] = i
        for j in 1...n {
            let cost = a[i - 1] == b[j - 1] ? 0 : 1
            curr[j] = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
        }
        swap(&prev, &curr)
    }
    return prev[n]
}

// MARK: - Normalization

private enum AnswerNormalizer {
    /// Fold a raw recognizer / user string into a comparable kana stem:
    ///   - strip okurigana markers (`.`, `-`), whitespace, common JP punctuation
    ///   - romaji → hiragana via CFStringTransform
    ///   - katakana → hiragana
    ///   - drop the long-vowel mark `ー` AND its trailing vowel-extension forms
    ///     (small tsu / long vowels) so `コーヒー` and `こうひい` both reduce to
    ///     `こひ` and match each other.
    ///
    /// The fold is intentionally loose so that the Japanese speech recognizer
    /// (which emits mixed kanji + katakana, often with long-vowel marks) and
    /// the local reading (which is pure hiragana from CFStringTransform) end
    /// up at the same canonical string.
    static func normalizeReading(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.filter { ch in
            ch != "." && ch != "-" && ch != "・"
                && ch != "、" && ch != "。" && ch != "「" && ch != "」"
                && ch != "?" && ch != "!" && ch != "?" && ch != "!"
        }
        if s.isEmpty { return "" }

        // Romaji → hiragana
        if s.unicodeScalars.contains(where: { $0.isASCII && $0.value > 32 }) {
            let lowered = s.lowercased() as NSString
            let mutable = NSMutableString(string: lowered)
            CFStringTransform(mutable, nil, kCFStringTransformLatinHiragana, false)
            s = mutable as String
        }

        // Katakana → hiragana (skip long-vowel mark and small punctuation —
        // those are handled below).
        var folded = ""
        for scalar in s.unicodeScalars {
            if (0x30A1...0x30F6).contains(scalar.value),
               let mapped = Unicode.Scalar(scalar.value - 0x60) {
                folded.unicodeScalars.append(mapped)
            } else {
                folded.unicodeScalars.append(scalar)
            }
        }
        s = folded

        // Strip the long-vowel mark `ー` (0x30FC) entirely. Also strip any
        // small kana that the recognizer occasionally emits but the local
        // reading omits (e.g. small ぁぃぅぇぉっゃゅょ). This is lossy but the
        // direction is consistent for both sides of the comparison.
        var compact = ""
        for scalar in s.unicodeScalars {
            switch scalar.value {
            case 0x30FC: continue                      // ー long-vowel mark
            case 0x3041, 0x3043, 0x3045, 0x3047, 0x3049: continue  // ぁぃぅぇぉ
            case 0x3063: continue                      // っ small tsu
            case 0x3083, 0x3085, 0x3087: continue      // ゃゅょ
            case 0x309B, 0x309C: continue              // ゛ ゜ standalone marks
            default:
                compact.unicodeScalars.append(scalar)
            }
        }

        return compact.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
