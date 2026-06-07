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
        VStack(spacing: 0) {
            if showFuriganaState && chunk.hasKanji && !chunk.reading.isEmpty && chunk.reading != chunk.surface {
                Text(chunk.reading)
                    .font(.system(size: 10, design: .rounded).weight(.medium))
                    .foregroundStyle(state.readingColor)
            }
            Text(chunk.surface)
                .font(.system(.title3, design: .serif))
                .foregroundStyle(state.surfaceColor)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(state.background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(state.border, lineWidth: state.borderWidth)
        )
        .opacity(state.opacity)
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
                Text("Tap the mic, read the highlighted part, then Submit. Edit the transcript if needed.")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Palette.mist)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                chunkFeedbackView
                actionButton
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

    private var transcriptField: some View {
        TextField("What you said", text: $input)
            .focused($inputFocused)
            .submitLabel(.go)
            .onSubmit { submitChunk() }
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

    @ViewBuilder
    private var actionButton: some View {
        switch chunkFeedback {
        case nil:
            Button { submitChunk() } label: {
                Text("Submit").frame(maxWidth: .infinity)
            }
            .buttonStyle(SumiButtonStyle())
            .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
        case .wrong:
            VStack(spacing: 8) {
                Button { retryChunk() } label: {
                    Text("Try again").frame(maxWidth: .infinity)
                }
                .buttonStyle(SumiButtonStyle())
                Button { advanceChunk() } label: {
                    Text(isLastChunk ? "Move on · Finish" : "Move on").frame(maxWidth: .infinity)
                }
                .buttonStyle(WashiButtonStyle())
            }
        case .correct:
            Button { advanceChunk() } label: {
                Text(isLastChunk ? "Finish" : "Next chunk").frame(maxWidth: .infinity)
            }
            .buttonStyle(SumiButtonStyle())
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
        let matched = results.allSatisfy(\.matched) && !results.isEmpty
        let solvedStruggling: [Character] = matched
            ? Array(Set(sentence.filter { isKanji($0) }).intersection(strugglingKanjiChars)).sorted()
            : []
        VStack(spacing: 14) {
            if matched {
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
                    Text("Some chunks were missed")
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

    @ViewBuilder
    private var missedChunksSection: some View {
        let missed = results.filter { !$0.matched }
        if !missed.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Save missed words as flashcards")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(Palette.sumi.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
                FlowLayout(spacing: 6) {
                    ForEach(missed.filter { containsKanji($0.surface) }) { result in
                        Button {
                            pendingSaveToken = SaveTokenRequest(
                                surface: result.surface,
                                reading: result.expectedReading,
                                context: sentence
                            )
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "bookmark.fill")
                                    .font(.caption2)
                                Text(result.surface)
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

    // MARK: - Submit / advance

    private func submitChunk() {
        guard let chunk = activeChunk else { return }
        if speech.isListening { speech.stop() }
        let answer = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { return }

        // Apple's Japanese recognizer emits mixed kanji+kana (e.g. "見る"),
        // not pure hiragana, so we have to accept either form. Build a small
        // set of acceptable canonical strings:
        //   1. The chunk's reading from the tokenizer — fast but unreliable on
        //      compounds (CFStringTokenizer often returns the sum-of-characters
        //      reading, e.g. 人間 → "じんかん" instead of "にんげん").
        //   2. The chunk's surface (so a transcript that came back as the kanji
        //      still matches).
        //   3. Every JMdict kana form for the chunk's surface — this is the
        //      canonical reading for the compound, so user typing "ningen" for
        //      人間 lands on "にんげん" from JMdict and matches.
        // All candidates get folded through AnswerNormalizer so the comparison
        // is invariant to hiragana/katakana/romaji.
        let normalisedAnswer = AnswerNormalizer.normalizeReading(answer)
        var rawCandidates: [String] = [chunk.reading, chunk.surface]
        let dictEntries = DictionaryService.shared.lookup(chunk.surface, limit: 3)
        rawCandidates.append(contentsOf: dictEntries.flatMap { $0.kana })
        let candidates = rawCandidates
            .map(AnswerNormalizer.normalizeReading)
            .filter { !$0.isEmpty }
        let matched: Bool = candidates.contains { candidate in
            if normalisedAnswer == candidate { return true }
            // Either-direction containment so the recogniser picking up a
            // slightly longer or shorter span still counts.
            return normalisedAnswer.contains(candidate) || candidate.contains(normalisedAnswer)
        }

        if matched {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            chunkFeedback = .correct
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            chunkFeedback = .wrong(expected: chunk.reading, heard: answer)
        }

        // Replace any prior result for this chunk id.
        results.removeAll { $0.id == chunk.id }
        results.append(ChunkResult(
            id: chunk.id,
            surface: chunk.surface,
            expectedReading: chunk.reading,
            matched: matched,
            transcript: answer
        ))
    }

    private func retryChunk() {
        // Drop the failed attempt so the chunk-pill goes back to the active
        // state instead of staying tinted vermillion.
        if let chunk = activeChunk {
            results.removeAll { $0.id == chunk.id }
        }
        input = ""
        chunkFeedback = nil
        inputFocused = true
    }

    private func advanceChunk() {
        input = ""
        chunkFeedback = nil
        if currentIndex + 1 >= chunks.count {
            sessionComplete = true
        } else {
            currentIndex += 1
        }
    }

    private func resetSession() {
        results.removeAll()
        currentIndex = 0
        input = ""
        chunkFeedback = nil
        sessionComplete = false
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
            speech.stop()
        } else {
            input = ""
            chunkFeedback = nil
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

        // Drop any chunks that ended up empty / whitespace-only after gluing.
        chunks = chunks.filter { !$0.surface.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

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
