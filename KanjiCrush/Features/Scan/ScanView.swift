import SwiftUI
import SwiftData
import PhotosUI
import Translation

private struct SentenceSaveRequest: Identifiable {
    let id = UUID()
    let sentence: String
}

private struct SentenceGroup: Identifiable {
    let id = UUID()
    let lines: [OCRLine]
    var text: String { lines.map { $0.text }.joined(separator: " ") }
}

/// Splits a block of text into individual sentences using Japanese + Latin
/// terminators (。！？．!?). Closing punctuation (」 』 ）) stays attached to
/// the preceding sentence; consecutive terminators (e.g. `！？`) are grouped.
private func splitIntoSentences(_ text: String) -> [String] {
    let terminators: Set<Character> = ["。", "！", "？", "．", "!", "?"]
    let closers: Set<Character> = ["」", "』", "）", ")", "】", "〕"]

    var sentences: [String] = []
    var current = ""
    var pendingTerminator = false

    for char in text {
        if pendingTerminator && !terminators.contains(char) && !closers.contains(char) {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { sentences.append(trimmed) }
            current = ""
            pendingTerminator = false
        }
        current.append(char)
        if terminators.contains(char) { pendingTerminator = true }
    }

    let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty { sentences.append(trimmed) }

    return sentences
}

/// Groups OCR lines into vertical clusters separated by gaps larger than a
/// typical line height. Lines are assumed already sorted top-to-bottom
/// (descending Vision-coord minY) by `OCRService`.
private func groupOCRLines(_ lines: [OCRLine]) -> [SentenceGroup] {
    guard !lines.isEmpty else { return [] }

    let avgHeight = lines.map(\.boundingBox.height).reduce(0, +) / CGFloat(lines.count)
    let gapThreshold = max(avgHeight * 0.8, 0.012)  // Vision coords are 0…1

    var clusters: [[OCRLine]] = [[lines[0]]]
    for i in 1..<lines.count {
        let prev = lines[i - 1].boundingBox
        let curr = lines[i].boundingBox
        // Vision origin is bottom-left → prev (upper) has higher minY/maxY.
        // Visual gap between them on the page = prev.minY (bottom of prev) − curr.maxY (top of curr).
        let gap = prev.minY - curr.maxY
        if gap > gapThreshold {
            clusters.append([lines[i]])
        } else {
            clusters[clusters.count - 1].append(lines[i])
        }
    }
    return clusters.map { SentenceGroup(lines: $0) }
}

struct ScanView: View {
    @Query private var flashcards: [Flashcard]
    @Query private var knownWords: [KnownWord]
    @Query(sort: \Deck.createdAt, order: .reverse) private var decks: [Deck]
    @StateObject private var camera = CameraController()
    @State private var frozenImage: UIImage?
    @State private var recognizedText = ""
    @State private var tokens: [JapaneseToken] = []
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var selectedToken: JapaneseToken?
    @State private var highlightedToken: JapaneseToken?
    @State private var ocrLines: [OCRLine] = []
    @State private var sentenceSaveRequest: SentenceSaveRequest?
    @State private var showManualLookup = false
    @State private var manualWord = ""
    @State private var pinchBaseZoom: CGFloat = 1.0
    @State private var pickedPhoto: PhotosPickerItem?
    @AppStorage("hideKanaOnlyTokens") private var hideKanaOnlyTokens = true
    @AppStorage("hideKnownWords") private var hideKnownWords = false
    @AppStorage("jlptLevel") private var jlptLevel: Int = 0

    private var displayedTokens: [JapaneseToken] {
        var result = tokens
        if hideKanaOnlyTokens {
            result = result.filter { $0.surface.containsKanji }
        }
        if hideKnownWords {
            result = result.filter { !isKnown($0.surface) }
        }
        return result
    }

    private func isKnown(_ expression: String) -> Bool {
        Knownness.isKnown(
            expression: expression,
            knownWords: knownWords,
            userJLPTLevel: jlptLevel
        )
    }

    private var inDeckExpressions: Set<String> {
        Set(flashcards.map { $0.expression })
    }

    /// Sentences ready to render as individual cards: first cluster OCR lines by
    /// vertical gap, then within each cluster split on punctuation.
    private func detectedSentences() -> [String] {
        groupOCRLines(ocrLines)
            .flatMap { splitIntoSentences($0.text) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if let image = frozenImage {
                    frozenCaptureView(image: image)
                } else {
                    liveCameraView
                }

                if isProcessing {
                    ProgressView("読み込み中…")
                        .font(.system(.subheadline, design: .rounded).weight(.medium))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Palette.hairline, lineWidth: 0.75)
                        )
                        .shadow(color: Palette.sumi.opacity(0.15), radius: 14, y: 6)
                }
            }
            .navigationTitle("Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .alert("Scan", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .sheet(item: $selectedToken) { token in
                WordDetailView(
                    token: token,
                    contextSentence: recognizedText.isEmpty ? nil : recognizedText
                )
            }
            .sheet(item: $sentenceSaveRequest) { req in
                SaveFlashcardSheet(
                    expression: req.sentence,
                    reading: "",
                    meaning: nil,
                    contextSentence: req.sentence,
                    decks: decks,
                    cardType: .sentence
                )
            }
            .task {
                await camera.configure()
                camera.start()
            }
            .onDisappear { camera.stop() }
            .onChange(of: pickedPhoto) { _, newItem in
                guard let newItem else { return }
                Task { await loadPickedPhoto(newItem) }
            }
            .sheet(isPresented: $showManualLookup) {
                manualLookupSheet
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Toggle("Kanji words only", isOn: $hideKanaOnlyTokens)
                Toggle("Hide known words", isOn: $hideKnownWords)
                if frozenImage == nil {
                    Button {
                        showManualLookup = true
                    } label: {
                        Label("Type word", systemImage: "character.cursor.ibeam")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Palette.indigo)
            }
        }
        if frozenImage != nil {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    resetCapture()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Palette.sumi.opacity(0.7))
                }
            }
        }
    }

    // MARK: - Live camera

    private var liveCameraView: some View {
        ZStack(alignment: .bottom) {
            CameraPreviewView(session: camera.session)
                .ignoresSafeArea()
                .gesture(
                    MagnificationGesture()
                        .onChanged { scale in
                            camera.setZoom(pinchBaseZoom * scale)
                        }
                        .onEnded { _ in
                            pinchBaseZoom = camera.zoomFactor
                        }
                )
                .onAppear { pinchBaseZoom = camera.zoomFactor }

            if camera.zoomFactor > 1.05 {
                HStack {
                    Spacer()
                    Text(String(format: "%.1f×", camera.zoomFactor))
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(.black.opacity(0.32)))
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .frame(maxHeight: .infinity, alignment: .top)
            }

            if camera.permissionDenied {
                ContentUnavailableView(
                    "Camera Access Required",
                    systemImage: "camera.fill",
                    description: Text("Enable camera access in Settings to scan Japanese text from your TV.")
                )
                .background(.ultraThinMaterial)
            } else {
                bottomControlBar
            }
        }
    }

    private var bottomControlBar: some View {
        VStack(spacing: 14) {
            Text("TVの日本語にカメラを向けて、撮影してください。")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            HStack(alignment: .center, spacing: 28) {
                PhotosPicker(selection: $pickedPhoto, matching: .images) {
                    VStack(spacing: 4) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.title2)
                            .frame(width: 52, height: 52)
                            .foregroundStyle(.white)
                            .background(Circle().fill(.white.opacity(0.16)))
                            .overlay(Circle().strokeBorder(.white.opacity(0.30), lineWidth: 0.75))
                        Text("Photos")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }

                Button {
                    Task { await captureAndProcess() }
                } label: {
                    ZStack {
                        Circle()
                            .strokeBorder(Palette.sakura.opacity(0.95), lineWidth: 4)
                            .frame(width: 78, height: 78)
                        Circle()
                            .fill(LinearGradient(
                                colors: [Palette.indigo, Palette.indigo.opacity(0.82)],
                                startPoint: .top,
                                endPoint: .bottom
                            ))
                            .frame(width: 64, height: 64)
                            .shadow(color: Palette.indigo.opacity(0.4), radius: 12, y: 4)
                        Image(systemName: "camera.fill")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                }
                .accessibilityLabel("Capture")

                Button {
                    showManualLookup = true
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "character.cursor.ibeam")
                            .font(.title3)
                            .frame(width: 52, height: 52)
                            .foregroundStyle(.white)
                            .background(Circle().fill(.white.opacity(0.16)))
                            .overlay(Circle().strokeBorder(.white.opacity(0.30), lineWidth: 0.75))
                        Text("Type")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
            .padding(.bottom, 22)
        }
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.30), .black.opacity(0.65)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Frozen capture view

    private func frozenCaptureView(image: UIImage) -> some View {
        ZStack {
            WashiBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ZoomableImageView(
                        image: image,
                        lines: ocrLines,
                        highlightedToken: highlightedToken
                    )
                        .frame(height: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(Palette.hairline, lineWidth: 0.75)
                        )
                        .shadow(color: Palette.sumi.opacity(0.12), radius: 18, y: 8)
                        .padding(.horizontal)
                        .padding(.top, 8)

                    if !displayedTokens.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(
                                title: "Tap reading · 2× details",
                                trailing: "\(displayedTokens.count) found"
                            )
                            BrushDivider()

                            WordChipFlow(
                                tokens: displayedTokens,
                                knownPredicate: { isKnown($0) },
                                inDeckExpressions: inDeckExpressions,
                                onTap: { token, revealed in
                                    highlightedToken = revealed ? token : nil
                                },
                                onLongPress: { token in
                                    selectedToken = token
                                }
                            )
                        }
                        .padding(.horizontal)

                        ForEach(detectedSentences(), id: \.self) { sentence in
                            SentenceCard(
                                sentence: sentence,
                                onDoubleTap: {
                                    sentenceSaveRequest = SentenceSaveRequest(sentence: sentence)
                                },
                                onTapKanaWord: { token in
                                    selectedToken = token
                                }
                            )
                            .padding(.horizontal)
                        }
                    } else if !recognizedText.isEmpty {
                        VStack(spacing: 8) {
                            MapleGlyph(size: 22)
                            Text("No words to show")
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .foregroundStyle(Palette.sumi)
                            Text("Try toggling the filters above.")
                                .font(.caption)
                                .foregroundStyle(Palette.mist)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
        }
    }

    // MARK: - Manual lookup sheet

    private var manualLookupSheet: some View {
        NavigationStack {
            ZStack {
                WashiBackground()
                VStack(spacing: 16) {
                    SectionHeader(title: "Lookup a word")
                    TextField("Japanese word", text: $manualWord)
                        .font(.system(.title3, design: .rounded))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Palette.washi, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Palette.hairline, lineWidth: 0.75)
                        )
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Lookup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showManualLookup = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Look up") {
                        let word = manualWord.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !word.isEmpty else { return }
                        let tokens = JapaneseAnalysisService.shared.tokenize(word)
                        let token = tokens.first ?? JapaneseToken(
                            surface: word,
                            reading: JapaneseAnalysisService.shared.localReading(for: word),
                            range: word.startIndex..<word.endIndex
                        )
                        showManualLookup = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            selectedToken = token
                        }
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Actions

    private func loadPickedPhoto(_ item: PhotosPickerItem) async {
        isProcessing = true
        defer {
            isProcessing = false
            pickedPhoto = nil
        }
        guard
            let data = try? await item.loadTransferable(type: Data.self),
            let image = UIImage(data: data)
        else {
            errorMessage = "Could not load that image."
            return
        }
        camera.stop()
        frozenImage = image
        await runOCR()
    }

    private func captureAndProcess() async {
        isProcessing = true
        defer { isProcessing = false }
        guard let image = await camera.capturePhoto() else {
            errorMessage = "Could not take photo."
            return
        }
        camera.stop()
        frozenImage = image
        await runOCR()
    }

    private func runOCR() async {
        guard let image = frozenImage else { return }
        isProcessing = true
        defer { isProcessing = false }
        do {
            let lines = try await OCRService.shared.recognize(in: image)
            ocrLines = lines.filter { $0.text.containsJapanese }
            rebuildTokens()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func rebuildTokens() {
        var merged: [JapaneseToken] = []
        for line in ocrLines {
            for token in JapaneseAnalysisService.shared.tokenize(line.text) {
                let lower = line.text.distance(from: line.text.startIndex, to: token.range.lowerBound)
                let upper = line.text.distance(from: line.text.startIndex, to: token.range.upperBound)
                var tagged = token
                tagged.lineId = line.id
                tagged.lineCharRange = lower..<upper
                merged.append(tagged)
            }
        }
        tokens = merged
        recognizedText = ocrLines.map { $0.text }.joined(separator: " ")
        highlightedToken = nil
    }

    private func resetCapture() {
        frozenImage = nil
        recognizedText = ""
        tokens = []
        ocrLines = []
        selectedToken = nil
        highlightedToken = nil
        camera.start()
    }
}

// MARK: - Sentence card

private struct SentenceCard: View {
    let sentence: String
    let onDoubleTap: () -> Void
    var onTapKanaWord: ((JapaneseToken) -> Void)? = nil

    @State private var revealedTokenIds: Set<UUID> = []
    @State private var segments: [JapaneseToken]
    @State private var translation: String?
    @State private var translationError: String?
    @State private var translationConfig: TranslationSession.Configuration?
    @State private var isTranslating = false
    @ObservedObject private var speech = SpeechService.shared

    init(
        sentence: String,
        onDoubleTap: @escaping () -> Void,
        onTapKanaWord: ((JapaneseToken) -> Void)? = nil
    ) {
        self.sentence = sentence
        self.onDoubleTap = onDoubleTap
        self.onTapKanaWord = onTapKanaWord
        _segments = State(initialValue: JapaneseAnalysisService.shared.segments(sentence))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Sentence")
            BrushDivider()

            FlowLayout(spacing: 1) {
                ForEach(segments) { token in
                    tokenView(for: token)
                }
            }

            translationView
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Palette.washi, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 0.75)
        )
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture(count: 2) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onDoubleTap()
        }
        .translationTask(translationConfig) { session in
            do {
                let response = try await session.translate(sentence)
                await MainActor.run {
                    translation = response.targetText
                    translationError = nil
                    isTranslating = false
                }
            } catch {
                await MainActor.run {
                    translationError = error.localizedDescription
                    isTranslating = false
                }
            }
        }
    }

    @ViewBuilder
    private var translationView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                playButton
                if translation == nil && !isTranslating && translationError == nil {
                    translateButton
                }
                saveButton
                Spacer()
            }
            .padding(.top, 6)

            if let translation {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Translation")
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(Palette.mist)
                        .textCase(.uppercase)
                        .tracking(0.6)
                    Text(translation)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Palette.sumi.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if isTranslating {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Translating…")
                        .font(.caption)
                        .foregroundStyle(Palette.mist)
                }
            } else if let translationError {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Translation failed")
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(Palette.vermillion.opacity(0.85))
                        Text(translationError)
                            .font(.caption2)
                            .foregroundStyle(Palette.mist)
                            .lineLimit(2)
                    }
                    Spacer()
                    Button {
                        startTranslation()
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Palette.indigo.opacity(0.12)))
                            .foregroundStyle(Palette.indigo)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var playButton: some View {
        let isActive = speech.isSpeaking(sentence)
        return Button {
            if isActive {
                speech.stop()
            } else {
                speech.speak(sentence)
            }
        } label: {
            Image(systemName: isActive ? "stop.fill" : "play.fill")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Palette.indigo.opacity(0.12)))
                .foregroundStyle(Palette.indigo)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isActive ? "Stop audio" : "Play sentence audio")
    }

    private var translateButton: some View {
        Button {
            startTranslation()
        } label: {
            Label("Show translation", systemImage: "character.bubble")
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Palette.indigo.opacity(0.12)))
                .foregroundStyle(Palette.indigo)
        }
        .buttonStyle(.plain)
    }

    private var saveButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onDoubleTap()
        } label: {
            Label("Save flashcard", systemImage: "bookmark.fill")
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Palette.sakura.opacity(0.18)))
                .foregroundStyle(Palette.sakura)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Save sentence as flashcard")
    }

    private func startTranslation() {
        isTranslating = true
        translationError = nil
        // Force a new configuration so .translationTask re-fires even if same languages.
        translationConfig = TranslationSession.Configuration(
            source: Locale.Language(identifier: "ja"),
            target: Locale.Language(identifier: "en")
        )
    }

    @ViewBuilder
    private func tokenView(for token: JapaneseToken) -> some View {
        if token.hasKanji {
            let revealed = revealedTokenIds.contains(token.id)
            Button {
                toggle(token.id)
            } label: {
                if revealed, !token.reading.isEmpty, token.reading != token.surface {
                    VStack(spacing: 0) {
                        Text(token.reading)
                            .font(.system(size: 10, design: .rounded).weight(.medium))
                            .foregroundStyle(Palette.indigo.opacity(0.85))
                        Text(token.surface)
                            .font(.system(.title3, design: .serif))
                            .foregroundStyle(Palette.sumi)
                    }
                    .fixedSize()
                } else {
                    Text(token.surface)
                        .font(.system(.title3, design: .serif))
                        .foregroundStyle(Palette.indigo)
                        .underline(true, pattern: .dot)
                }
            }
            .buttonStyle(.plain)
        } else if isLookupableKana(token) {
            Button {
                onTapKanaWord?(token)
            } label: {
                Text(token.surface)
                    .font(.system(.title3, design: .serif))
                    .foregroundStyle(Palette.sumi)
                    .underline(true, pattern: .dot, color: Palette.mist.opacity(0.45))
            }
            .buttonStyle(.plain)
        } else {
            Text(token.surface)
                .font(.system(.title3, design: .serif))
                .foregroundStyle(Palette.sumi)
        }
    }

    /// Kana tokens that look like content words (not single-mora particles).
    private func isLookupableKana(_ token: JapaneseToken) -> Bool {
        token.hasKana && !token.hasKanji && token.surface.count >= 2
    }

    private func toggle(_ id: UUID) {
        if revealedTokenIds.contains(id) {
            revealedTokenIds.remove(id)
        } else {
            revealedTokenIds.insert(id)
        }
    }
}

// MARK: - Word chips

struct WordChipFlow: View {
    let tokens: [JapaneseToken]
    /// Predicate so JLPT-implied known words are flagged without prebuilding
    /// a giant Set in the caller.
    var knownPredicate: (String) -> Bool = { _ in false }
    var inDeckExpressions: Set<String> = []
    /// Single tap: toggle inline reading. Second arg = new revealed state.
    var onTap: ((JapaneseToken, Bool) -> Void)? = nil
    /// Double tap: open the full word detail sheet.
    let onLongPress: (JapaneseToken) -> Void

    @State private var revealedTokenIds: Set<UUID> = []

    fileprivate enum ChipState {
        case fresh
        case inDeck
        case known
        /// In a deck *and* considered known (explicit mark or JLPT-implied).
        /// Surfaces as a yellow chip — "you have a card for a word you
        /// should already know".
        case strugglingKnown

        var tint: Color {
            switch self {
            case .fresh: return Palette.mist
            case .inDeck: return Palette.indigo
            case .known: return Palette.bamboo
            case .strugglingKnown: return Palette.gold
            }
        }

        var icon: String? {
            switch self {
            case .fresh: return nil
            case .inDeck: return "bookmark.fill"
            case .known: return "checkmark.seal.fill"
            case .strugglingKnown: return "exclamationmark.triangle.fill"
            }
        }

        var emphasized: Bool {
            switch self {
            case .fresh: return false
            case .inDeck, .known, .strugglingKnown: return true
            }
        }
    }

    private func state(for token: JapaneseToken) -> ChipState {
        let known = knownPredicate(token.surface)
        let inDeck = inDeckExpressions.contains(token.surface)
        if known && inDeck { return .strugglingKnown }
        if known { return .known }
        if inDeck { return .inDeck }
        return .fresh
    }

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(tokens) { token in
                WordChip(
                    token: token,
                    chip: state(for: token),
                    revealed: revealedTokenIds.contains(token.id),
                    onSingleTap: { toggle(token) },
                    onDoubleTap: { onLongPress(token) }
                )
            }
        }
    }

    private func toggle(_ token: JapaneseToken) {
        let nowRevealed: Bool
        if revealedTokenIds.contains(token.id) {
            revealedTokenIds.remove(token.id)
            nowRevealed = false
        } else {
            revealedTokenIds.insert(token.id)
            nowRevealed = true
        }
        onTap?(token, nowRevealed)
    }
}

private struct WordChip: View {
    let token: JapaneseToken
    let chip: WordChipFlow.ChipState
    let revealed: Bool
    let onSingleTap: () -> Void
    let onDoubleTap: () -> Void

    var body: some View {
        let showReading = revealed && token.hasKanji
            && !token.reading.isEmpty && token.reading != token.surface

        VStack(spacing: 1) {
            if showReading {
                Text(token.reading)
                    .font(.system(size: 11, design: .rounded).weight(.medium))
                    .foregroundStyle(Palette.indigo.opacity(0.85))
            }
            HStack(spacing: 5) {
                Text(token.surface)
                    .font(.system(.title3, design: .serif))
                    .foregroundStyle(Palette.sumi)
                if let icon = chip.icon {
                    Image(systemName: icon)
                        .font(.caption2)
                        .foregroundStyle(chip.tint)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            Capsule(style: .continuous)
                .fill(chip.tint.opacity(chip.emphasized ? 0.18 : 0.10))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(chip.tint.opacity(chip.emphasized ? 0.55 : 0.30), lineWidth: 0.75)
        )
        .contentShape(Capsule())
        .onTapGesture(count: 2) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onDoubleTap()
        }
        .onTapGesture(count: 1) {
            onSingleTap()
        }
    }
}

/// Simple wrapping layout for word chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}

struct ZoomableImageView: View {
    let image: UIImage
    var lines: [OCRLine] = []
    var highlightedToken: JapaneseToken? = nil

    @State private var scale: CGFloat = 1.0
    @State private var pinchBase: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var dragBase: CGSize = .zero

    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 5.0

    var body: some View {
        GeometryReader { geo in
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: geo.size.width, height: geo.size.height)
                .overlay(highlightOverlay(in: geo.size))
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    SimultaneousGesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = clamp(pinchBase * value)
                            }
                            .onEnded { _ in
                                pinchBase = scale
                                if scale <= 1.0 {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        offset = .zero
                                        dragBase = .zero
                                    }
                                }
                            },
                        DragGesture()
                            .onChanged { value in
                                guard scale > 1.0 else { return }
                                offset = CGSize(
                                    width: dragBase.width + value.translation.width,
                                    height: dragBase.height + value.translation.height
                                )
                            }
                            .onEnded { _ in
                                dragBase = offset
                            }
                    )
                )
                .onTapGesture(count: 2) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if scale > 1.0 {
                            scale = 1.0
                            pinchBase = 1.0
                            offset = .zero
                            dragBase = .zero
                        } else {
                            scale = 2.5
                            pinchBase = 2.5
                        }
                    }
                }
        }
        .contentShape(Rectangle())
        .clipped()
    }

    private func clamp(_ value: CGFloat) -> CGFloat {
        max(minScale, min(value, maxScale))
    }

    @ViewBuilder
    private func highlightOverlay(in size: CGSize) -> some View {
        if let bbox = highlightedTokenBox() {
            let rect = mapBox(bbox, in: size)
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Palette.sakura.opacity(0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .strokeBorder(Palette.sakura.opacity(0.9), lineWidth: 1 / max(scale, 1))
                )
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    private func mapBox(_ bbox: CGRect, in size: CGSize) -> CGRect {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let fit = min(size.width / imageSize.width, size.height / imageSize.height)
        let displayedW = imageSize.width * fit
        let displayedH = imageSize.height * fit
        let offsetX = (size.width - displayedW) / 2
        let offsetY = (size.height - displayedH) / 2
        return CGRect(
            x: offsetX + bbox.minX * displayedW,
            y: offsetY + (1 - bbox.maxY) * displayedH,
            width: bbox.width * displayedW,
            height: bbox.height * displayedH
        )
    }

    private func highlightedTokenBox() -> CGRect? {
        guard let token = highlightedToken,
              let lineId = token.lineId,
              let charRange = token.lineCharRange,
              let line = lines.first(where: { $0.id == lineId }),
              !line.charBoxes.isEmpty
        else { return nil }

        let lower = max(0, min(charRange.lowerBound, line.charBoxes.count - 1))
        let upper = max(lower + 1, min(charRange.upperBound, line.charBoxes.count))
        let boxes = Array(line.charBoxes[lower..<upper])
        guard !boxes.isEmpty else { return nil }
        return boxes.dropFirst().reduce(boxes[0]) { $0.union($1) }
    }
}

private extension String {
    var containsKanji: Bool {
        unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value) ||  // CJK Unified Ideographs
            (0x3400...0x4DBF).contains(scalar.value) ||  // CJK Extension A
            (0x20000...0x2A6DF).contains(scalar.value)   // CJK Extension B
        }
    }

    /// True if the string has any hiragana, katakana, or kanji character.
    var containsJapanese: Bool {
        unicodeScalars.contains { scalar in
            (0x3040...0x309F).contains(scalar.value) ||   // Hiragana
            (0x30A0...0x30FF).contains(scalar.value) ||   // Katakana
            (0xFF66...0xFF9D).contains(scalar.value) ||   // Halfwidth katakana
            (0x4E00...0x9FFF).contains(scalar.value) ||   // CJK Unified Ideographs
            (0x3400...0x4DBF).contains(scalar.value) ||   // CJK Extension A
            (0x20000...0x2A6DF).contains(scalar.value)    // CJK Extension B
        }
    }
}
