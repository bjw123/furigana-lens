import SwiftUI
import SwiftData

struct WordDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Deck.createdAt, order: .reverse) private var decks: [Deck]
    @Query private var knownMatches: [KnownWord]
    @AppStorage("jlptLevel") private var jlptLevel: Int = 0

    let token: JapaneseToken
    let contextSentence: String?

    @State private var expression: String
    @State private var reading: String
    @State private var meaningText = ""
    @State private var meaningRevealed = false
    @State private var dictionaryMatches: [DictionaryEntry] = []
    @State private var examples: [ExampleSentence] = []
    @State private var errorMessage: String?
    @State private var showSaveSheet = false
    @State private var isDictionaryDegraded = false

    init(token: JapaneseToken, contextSentence: String?) {
        self.token = token
        self.contextSentence = contextSentence
        _expression = State(initialValue: token.surface)
        _reading = State(initialValue: token.reading)
        let surface = token.surface
        _knownMatches = Query(filter: #Predicate<KnownWord> { $0.expression == surface })
    }

    private var isKnown: Bool {
        Knownness.isKnown(
            expression: expression,
            knownWords: knownMatches,
            userJLPTLevel: jlptLevel
        )
    }

    /// True when the word is "known" only because the user's JLPT level
    /// implies it — no explicit override row. Used to label the toggle
    /// differently so the source of the green-check is clear.
    private var isJLPTImplied: Bool {
        knownMatches.isEmpty
            && Knownness.jlptImplies(known: expression, userJLPTLevel: jlptLevel)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WashiBackground()

                ScrollView {
                    VStack(spacing: 20) {
                        if isDictionaryDegraded {
                            ErrorBanner.dictionaryDegraded()
                                .padding(.horizontal)
                        }

                        heroCard

                        if let contextSentence, !contextSentence.isEmpty {
                            contextCard(sentence: contextSentence)
                        }

                        editFieldsCard

                        knownToggle

                        if !meaningRevealed {
                            Button {
                                revealMeaning()
                            } label: {
                                Label("Show meaning", systemImage: "text.book.closed.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(SumiButtonStyle())
                            .padding(.horizontal)
                        } else {
                            meaningSection
                            KanjiBreakdownView(expression: expression)
                                .padding(.horizontal)
                            if !examples.isEmpty {
                                examplesSection
                            }
                        }

                        Spacer(minLength: 24)
                    }
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle("Word")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showSaveSheet = true
                    } label: {
                        Label("Save", systemImage: "bookmark.fill")
                            .labelStyle(.titleAndIcon)
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showSaveSheet) {
                SaveFlashcardSheet(
                    expression: expression,
                    reading: reading,
                    meaning: meaningRevealed ? meaningText : nil,
                    meaningSource: meaningRevealed
                        ? (dictionaryMatches.isEmpty ? "Custom" : "JMdict")
                        : nil,
                    contextSentence: contextSentence,
                    decks: decks
                )
            }
            .alert("Lookup", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .observingDictionaryDegraded($isDictionaryDegraded)
        }
    }

    private var displayReading: String {
        reading.isEmpty ? expression : reading
    }

    private var heroCard: some View {
        VStack(spacing: 10) {
            FuriganaWordView(expression: expression, reading: displayReading, fontSize: 52)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            HStack(spacing: 6) {
                MapleGlyph(size: 10)
                Text("Tap save to add to a deck")
                    .font(.caption2)
                    .foregroundStyle(Palette.mist)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
        }
        .washiCard(padding: 22, cornerRadius: 24)
        .padding(.horizontal)
    }

    private func contextCard(sentence: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Context")
            Text(sentence)
                .font(.system(.callout, design: .serif))
                .foregroundStyle(Palette.sumi.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .washiCard()
        .padding(.horizontal)
    }

    private var editFieldsCard: some View {
        VStack(spacing: 0) {
            editRow(label: "Word", binding: $expression)
            Divider()
                .padding(.leading, 16)
                .overlay(Palette.hairline)
            editRow(label: "Reading", binding: $reading)
        }
        .background(Palette.washi, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 0.75)
        )
        .padding(.horizontal)
    }

    private func editRow(label: String, binding: Binding<String>) -> some View {
        HStack {
            Text(label)
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundStyle(Palette.mist)
                .frame(width: 80, alignment: .leading)
            TextField(label, text: binding)
                .multilineTextAlignment(.trailing)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Palette.sumi)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var knownToggle: some View {
        Button {
            toggleKnown()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isKnown ? "checkmark.seal.fill" : "checkmark.seal")
                    .font(.system(size: 18, weight: .semibold))
                VStack(alignment: .leading, spacing: 1) {
                    Text(isKnown ? "Marked known" : "Mark as known")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    if isJLPTImplied {
                        Text("Implied by N\(jlptLevel) level")
                            .font(.caption2)
                            .foregroundStyle(Palette.bamboo.opacity(0.75))
                    }
                }
                Spacer()
                Text(isKnown ? "Tap to mark unknown" : "Tap to confirm")
                    .font(.caption2)
                    .foregroundStyle(Palette.mist)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .foregroundStyle(isKnown ? Palette.bamboo : Palette.indigo)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill((isKnown ? Palette.bamboo : Palette.indigo).opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder((isKnown ? Palette.bamboo : Palette.indigo).opacity(0.35), lineWidth: 0.75)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

    private func toggleKnown() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Knownness.setKnown(
            !isKnown,
            expression: expression,
            userJLPTLevel: jlptLevel,
            existing: knownMatches,
            modelContext: modelContext
        )
    }

    @ViewBuilder
    private var meaningSection: some View {
        let inDictionary = !dictionaryMatches.isEmpty
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Meaning",
                trailing: inDictionary ? "via JMdict" : "Custom"
            )
            BrushDivider()

            if !inDictionary {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "pencil.line")
                        .font(.caption)
                        .foregroundStyle(Palette.mist)
                    Text("Not in the dictionary — type your own meaning (game/manga terms, slang, names, etc.) and save as a flashcard.")
                        .font(.caption)
                        .foregroundStyle(Palette.mist)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            TextField(
                inDictionary ? "Edit if needed" : "Type the meaning here",
                text: $meaningText,
                axis: .vertical
            )
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Palette.sumi)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Palette.cream, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Palette.hairline, lineWidth: 0.75)
                )

            if dictionaryMatches.count > 1 {
                Text("Other entries")
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .foregroundStyle(Palette.mist)
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .padding(.top, 4)

                VStack(spacing: 8) {
                    ForEach(dictionaryMatches.dropFirst().prefix(3), id: \.id) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            if let kana = entry.kana.first {
                                Text(kana)
                                    .font(.system(.subheadline, design: .serif))
                                    .foregroundStyle(Palette.indigo)
                            }
                            Text(entry.glosses().joined(separator: "; "))
                                .font(.caption)
                                .foregroundStyle(Palette.sumi.opacity(0.8))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Palette.cream.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
        }
        .washiCard()
        .padding(.horizontal)
    }

    @ViewBuilder
    private var examplesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Examples", trailing: "Tanaka Corpus")
            BrushDivider()
            ForEach(examples, id: \.self) { example in
                ExampleRow(example: example)
            }
        }
        .washiCard()
        .padding(.horizontal)
    }

    private func revealMeaning() {
        let matches = DictionaryService.shared.lookup(expression)
        dictionaryMatches = matches
        if let top = matches.first {
            if let kana = top.kana.first, !kana.isEmpty {
                reading = kana
            }
            meaningText = top.glosses().joined(separator: "; ")
            let headwords = [expression] + top.kanji + top.kana
            examples = DictionaryService.shared.examples(for: headwords)
        } else {
            // Not in JMdict — common for game/manga slang, onomatopoeia, proper
            // nouns, or recently coined words. Let the user type their own meaning
            // and still save it as a flashcard.
            meaningText = ""
            examples = []
        }
        withAnimation(.easeOut(duration: 0.25)) {
            meaningRevealed = true
        }
    }
}

private struct ExampleRow: View {
    let example: ExampleSentence
    @State private var englishRevealed = false
    @State private var revealedTokenIds: Set<UUID> = []
    @State private var segments: [JapaneseToken]

    init(example: ExampleSentence) {
        self.example = example
        _segments = State(initialValue: JapaneseAnalysisService.shared.segments(example.japanese))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 0) {
                ForEach(segments) { token in
                    tokenView(for: token)
                }
            }

            Button {
                withAnimation(.easeInOut(duration: 0.15)) { englishRevealed.toggle() }
            } label: {
                Group {
                    if englishRevealed {
                        HStack(spacing: 6) {
                            Image(systemName: "globe")
                                .font(.caption2)
                                .foregroundStyle(Palette.indigo)
                            Text(example.english)
                                .font(.caption)
                                .foregroundStyle(Palette.sumi.opacity(0.85))
                                .multilineTextAlignment(.leading)
                        }
                    } else {
                        Text("Tap to reveal translation")
                            .font(.caption2)
                            .foregroundStyle(Palette.mist)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
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
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(Palette.indigo)
                        Text(token.surface)
                            .font(.system(.body, design: .serif))
                            .foregroundStyle(Palette.sumi)
                    }
                    .fixedSize()
                } else {
                    Text(token.surface)
                        .font(.system(.body, design: .serif))
                        .foregroundStyle(Palette.indigo)
                        .underline(true, pattern: .dot)
                }
            }
            .buttonStyle(.plain)
        } else {
            Text(token.surface)
                .font(.system(.body, design: .serif))
                .foregroundStyle(Palette.sumi.opacity(0.85))
        }
    }

    private func toggle(_ id: UUID) {
        if revealedTokenIds.contains(id) {
            revealedTokenIds.remove(id)
        } else {
            revealedTokenIds.insert(id)
        }
    }
}

struct SaveFlashcardSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let expression: String
    let reading: String
    let meaning: String?
    let meaningSource: String?
    let contextSentence: String?
    let hint: String?
    let decks: [Deck]
    let cardType: CardType

    @State private var selectedDeck: Deck?
    @State private var newDeckName = ""
    @State private var newDeckTag = "Game"
    @State private var createNewDeck = false
    @State private var hintText: String = ""

    init(
        expression: String,
        reading: String,
        meaning: String?,
        meaningSource: String? = nil,
        contextSentence: String?,
        hint: String? = nil,
        decks: [Deck],
        cardType: CardType = .word
    ) {
        self.expression = expression
        self.reading = reading
        self.meaning = meaning
        self.meaningSource = meaningSource
        self.contextSentence = contextSentence
        self.hint = hint
        self.decks = decks
        self.cardType = cardType
        _hintText = State(initialValue: hint ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WashiBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Card preview", trailing: cardType.label)
                            if cardType == .sentence {
                                Text(expression)
                                    .font(.system(.body, design: .serif))
                                    .foregroundStyle(Palette.sumi)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                FuriganaWordView(expression: expression, reading: reading, fontSize: 32)
                                    .frame(maxWidth: .infinity)
                            }
                            if let meaning, !meaning.isEmpty {
                                Text(meaning)
                                    .font(.system(.footnote, design: .rounded))
                                    .foregroundStyle(Palette.sumi.opacity(0.8))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .washiCard()
                        .padding(.horizontal)

                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Hint")
                            TextField("Hint", text: $hintText, axis: .vertical)
                                .font(.system(.body, design: .rounded))
                                .foregroundStyle(Palette.sumi)
                                .padding(12)
                                .background(Palette.washi, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(Palette.hairline, lineWidth: 0.75)
                                )
                        }
                        .washiCard()
                        .padding(.horizontal)

                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Deck")
                            Toggle(isOn: $createNewDeck) {
                                Text("Create new deck")
                                    .font(.system(.body, design: .rounded))
                            }
                            .tint(Palette.indigo)

                            if createNewDeck {
                                deckTextField(placeholder: "Deck name", text: $newDeckName)
                                deckTextField(placeholder: "Tag (Game, Anime, …)", text: $newDeckTag)
                            } else if decks.isEmpty {
                                Text("No decks yet — toggle on to create one.")
                                    .font(.caption)
                                    .foregroundStyle(Palette.mist)
                            } else {
                                Picker("Deck", selection: $selectedDeck) {
                                    Text("Select…").tag(Optional<Deck>.none)
                                    ForEach(decks) { deck in
                                        Text(deck.name).tag(Optional(deck))
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(Palette.indigo)
                            }
                        }
                        .washiCard()
                        .padding(.horizontal)

                        Spacer(minLength: 12)
                    }
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle("Save flashcard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                selectedDeck = decks.first
            }
        }
    }

    private func deckTextField(placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(.system(.body, design: .rounded))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Palette.cream, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 0.75)
            )
    }

    private var canSave: Bool {
        if createNewDeck { return !newDeckName.trimmingCharacters(in: .whitespaces).isEmpty }
        return selectedDeck != nil
    }

    private func save() {
        let deck: Deck
        if createNewDeck {
            deck = Deck(name: newDeckName.trimmingCharacters(in: .whitespaces), mediaTag: newDeckTag)
            modelContext.insert(deck)
        } else if let selectedDeck {
            deck = selectedDeck
        } else {
            return
        }

        let trimmedMeaning = meaning?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedMeaning = (trimmedMeaning?.isEmpty ?? true) ? nil : trimmedMeaning
        let card = Flashcard(
            expression: expression,
            reading: reading.isEmpty ? expression : reading,
            meaning: normalizedMeaning,
            meaningSource: normalizedMeaning != nil ? (meaningSource ?? "Custom") : nil,
            contextSentence: contextSentence,
            cardType: cardType,
            deck: deck
        )
        let trimmedHint = hintText.trimmingCharacters(in: .whitespacesAndNewlines)
        card.hint = trimmedHint.isEmpty ? nil : trimmedHint
        deck.cards.append(card)
        modelContext.insert(card)
        try? modelContext.save()
        dismiss()
    }
}
