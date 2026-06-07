import SwiftUI
import SwiftData
import PhotosUI
import Translation

struct SentenceSaveRequest: Identifiable {
    let id = UUID()
    let sentence: String
}

struct SentenceGroup: Identifiable {
    let id = UUID()
    let lines: [OCRLine]
    var text: String { lines.map { $0.text }.joined(separator: " ") }
}

/// Splits a block of text into individual sentences using Japanese + Latin
/// terminators (。！？．!?). Closing punctuation (」 』 ）) stays attached to
/// the preceding sentence; consecutive terminators (e.g. `！？`) are grouped.
func splitIntoSentences(_ text: String) -> [String] {
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
func groupOCRLines(_ lines: [OCRLine]) -> [SentenceGroup] {
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
    @Query var flashcards: [Flashcard]
    @Query var knownWords: [KnownWord]
    @Query var reviewLogs: [ReviewLog]
    @Query(sort: \Deck.createdAt, order: .reverse) var decks: [Deck]
    @StateObject var camera = CameraController()
    @StateObject var frameCoordinator = FrameScanCoordinator()
    @AppStorage("autoCaptureEnabled") var autoCaptureEnabled = true
    @State var frozenImage: UIImage?
    @State var recognizedText = ""
    @State var tokens: [JapaneseToken] = []
    @State var isProcessing = false
    @State var errorMessage: String?
    @State var selectedToken: JapaneseToken?
    @State var highlightedToken: JapaneseToken?
    @State var ocrLines: [OCRLine] = []
    @State var sentenceSaveRequest: SentenceSaveRequest?
    @State var showManualLookup = false
    @State var manualWord = ""
    @State var pinchBaseZoom: CGFloat = 1.0
    @State var pickedPhoto: PhotosPickerItem?
    @State var isDictionaryDegraded = false
    @AppStorage("hideKanaOnlyTokens") var hideKanaOnlyTokens = true
    @AppStorage("hideKnownWords") var hideKnownWords = false
    @AppStorage("jlptLevel") var jlptLevel: Int = 0

    var displayedTokens: [JapaneseToken] {
        var result = tokens
        if hideKanaOnlyTokens {
            result = result.filter { $0.surface.containsKanji }
        }
        if hideKnownWords {
            result = result.filter { !isKnown($0.surface) }
        }
        return result
    }

    func isKnown(_ expression: String) -> Bool {
        Knownness.isKnown(
            expression: expression,
            knownWords: knownWords,
            userJLPTLevel: jlptLevel
        )
    }

    var inDeckExpressions: Set<String> {
        Set(flashcards.map { $0.expression })
    }

    var strugglingKanjiChars: Set<Character> {
        Set(
            StatsService.strugglingKanjiReadings(
                logs: reviewLogs,
                cards: flashcards,
                days: 30,
                limit: 24
            ).map(\.kanji)
        )
    }

    /// Sentences ready to render as individual cards: first cluster OCR lines by
    /// vertical gap, then within each cluster split on punctuation.
    func detectedSentences() -> [String] {
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

                if isDictionaryDegraded {
                    // Pinned to the top so word taps still surface the missing-
                    // entry context without taking over the camera viewfinder.
                    VStack {
                        ErrorBanner.dictionaryDegraded()
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                        Spacer()
                    }
                }
            }
            .observingDictionaryDegraded($isDictionaryDegraded)
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
                frameCoordinator.attach(to: camera.session)
                frameCoordinator.onAutoFire = {
                    Task { await captureAndProcess() }
                }
                frameCoordinator.setEnabled(autoCaptureEnabled && frozenImage == nil)
            }
            .onChange(of: autoCaptureEnabled) { _, on in
                frameCoordinator.setEnabled(on && frozenImage == nil)
            }
            .onChange(of: frozenImage) { _, frozen in
                frameCoordinator.setEnabled(autoCaptureEnabled && frozen == nil)
                if frozen != nil { frameCoordinator.noteAutoFireConsumed() }
            }
            .onDisappear {
                camera.stop()
                frameCoordinator.detach()
            }
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
    var toolbarContent: some ToolbarContent {
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
            .accessibilityIdentifier("scan.menu")
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

    // MARK: - Actions

    func loadPickedPhoto(_ item: PhotosPickerItem) async {
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

    func captureAndProcess() async {
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

    func runOCR() async {
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

    func rebuildTokens() {
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

    func resetCapture() {
        frozenImage = nil
        recognizedText = ""
        tokens = []
        ocrLines = []
        selectedToken = nil
        highlightedToken = nil
        camera.start()
    }
}

fileprivate extension String {
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
