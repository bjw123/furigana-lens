import SwiftUI

extension ScanView {

    // MARK: - Frozen capture view

    func frozenCaptureView(image: UIImage) -> some View {
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
                                strugglingKanji: strugglingKanjiChars,
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
                                strugglingKanji: strugglingKanjiChars,
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

    var manualLookupSheet: some View {
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
}
