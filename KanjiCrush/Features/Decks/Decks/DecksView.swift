import SwiftUI
import SwiftData

struct DecksView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Deck.createdAt, order: .reverse) private var decks: [Deck]
    @Query private var allCards: [Flashcard]
    @Query private var knownWords: [KnownWord]
    @AppStorage("jlptLevel") private var jlptLevel: Int = 0
    @State private var showNewDeck = false
    @State private var showArchived = false
    @State private var searchText = ""
    @State private var showImporter = false
    @State private var importError: String?

    private var activeDecks: [Deck] { decks.filter { !$0.isArchived } }
    private var archivedDecks: [Deck] { decks.filter { $0.isArchived } }

    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var isSearching: Bool { !trimmedQuery.isEmpty }

    /// Cards whose expression / reading / meaning / deck name match the query.
    private var searchResults: [Flashcard] {
        guard isSearching else { return [] }
        let q = trimmedQuery
        return allCards.filter { card in
            if card.expression.lowercased().contains(q) { return true }
            if card.reading.lowercased().contains(q) { return true }
            if let m = card.meaning?.lowercased(), m.contains(q) { return true }
            if let d = card.deck?.name.lowercased(), d.contains(q) { return true }
            if card.tags.contains(where: { $0.lowercased().contains(q) }) { return true }
            return false
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                WashiBackground()

                if isSearching {
                    searchResultsList
                } else if decks.isEmpty {
                    emptyState
                } else {
                    decksList
                }
            }
            .navigationTitle("Decks")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showNewDeck = true
                        } label: {
                            Label("New deck", systemImage: "plus")
                        }
                        Button {
                            showImporter = true
                        } label: {
                            Label("Import .kcdeck file", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Palette.indigo)
                    }
                }
            }
            .sheet(isPresented: $showNewDeck) {
                NewDeckSheet()
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.kanjiCrushDeck, .json],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
            .alert("Import failed", isPresented: .init(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importError ?? "")
            }
        }
        .searchable(text: $searchText, prompt: "Search cards…")
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }
            // Security-scoped URL when the file is outside the app sandbox.
            let needsScope = url.startAccessingSecurityScopedResource()
            defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let existingNames = Set(decks.map { $0.name })
            _ = try DeckExportService.import(
                data: data,
                into: modelContext,
                existingDeckNames: existingNames
            )
        } catch {
            importError = error.localizedDescription
        }
    }

    private var decksList: some View {
        ScrollView {
            VStack(spacing: 14) {
                ForEach(activeDecks) { deck in
                    NavigationLink {
                        DeckDetailView(deck: deck)
                    } label: {
                        DeckRowCard(deck: deck)
                    }
                    .buttonStyle(.plain)
                }

                if !archivedDecks.isEmpty {
                    archivedSection
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private var searchResultsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(searchResults.count) match\(searchResults.count == 1 ? "" : "es")")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(Palette.mist)
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .padding(.horizontal, 4)

                if searchResults.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 36))
                            .foregroundStyle(Palette.mist)
                        Text("No cards match \"\(searchText)\"")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Palette.mist)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                } else {
                    VStack(spacing: 10) {
                        ForEach(searchResults) { card in
                            NavigationLink {
                                CardEditView(card: card)
                            } label: {
                                SearchResultRow(
                                    card: card,
                                    isKnown: Knownness.isKnown(
                                        expression: card.expression,
                                        knownWords: knownWords,
                                        userJLPTLevel: jlptLevel
                                    )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private var archivedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showArchived.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showArchived ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                    Text("Archived")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .textCase(.uppercase)
                        .tracking(0.6)
                    Text("(\(archivedDecks.count))")
                        .font(.caption2)
                        .foregroundStyle(Palette.mist)
                    Spacer()
                }
                .foregroundStyle(Palette.mist)
                .padding(.top, 12)
            }
            .buttonStyle(.plain)

            if showArchived {
                ForEach(archivedDecks) { deck in
                    NavigationLink {
                        DeckDetailView(deck: deck)
                    } label: {
                        DeckRowCard(deck: deck)
                            .opacity(0.7)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Palette.sakura.opacity(0.18))
                    .frame(width: 96, height: 96)
                MapleGlyph(size: 56)
            }
            VStack(spacing: 6) {
                Text("No decks yet")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(Palette.sumi)
                Text("Save a flashcard from a scan to create your first deck.")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Palette.mist)
                    .multilineTextAlignment(.center)
            }
            Button {
                showNewDeck = true
            } label: {
                Label("New deck", systemImage: "plus")
            }
            .buttonStyle(WashiButtonStyle())
        }
        .padding(.horizontal, 32)
    }
}

private struct DeckRowCard: View {
    let deck: Deck

    var body: some View {
        let pair = Palette.gradientPair(for: gemTint)
        HStack(spacing: 14) {
            // Candy-gem avatar carrying the deck's first character — adopts
            // a brand colour cycled per mediaTag so the list reads colourful.
            GemTile(
                tint: pair.0,
                deeperTint: pair.1,
                cornerRadius: 14,
                size: 52
            ) {
                Text(initials)
                    .font(.system(.title3, design: .serif).weight(.semibold))
                    .foregroundStyle(Palette.cream)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(deck.name)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Palette.sumi)
                HStack(spacing: 8) {
                    Text(deck.mediaTag)
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(pair.0)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(pair.0.opacity(0.14)))
                        .overlay(Capsule().strokeBorder(pair.0.opacity(0.4), lineWidth: 0.5))
                    Text("\(deck.cards.count) cards")
                        .font(.caption)
                        .foregroundStyle(Palette.mist)
                    if deck.isExcludedFromReviews {
                        statusBadge(
                            text: "Paused",
                            icon: "pause.fill",
                            tint: Palette.gold
                        )
                    }
                    if deck.isArchived {
                        statusBadge(
                            text: "Archived",
                            icon: "archivebox.fill",
                            tint: Palette.mist
                        )
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.mist.opacity(0.7))
        }
        .padding(14)
        .washiCard(padding: 0, cornerRadius: 20)
    }

    /// Brand colour cycled off the mediaTag so each deck row reads as a
    /// distinct gem in the list. Falls back to sakura for unknown tags.
    private var gemTint: Color {
        switch deck.mediaTag.lowercased() {
        case "game", "ゲーム": return Palette.indigo
        case "manga", "漫画": return Palette.sakura
        case "anime", "アニメ": return Palette.vermillion
        case "book", "novel", "小説": return Palette.bamboo
        case "music", "音楽": return Palette.gold
        default: return Palette.sakura
        }
    }

    private var initials: String {
        let trimmed = deck.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(1))
    }

    private func statusBadge(text: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8).weight(.semibold))
            Text(text)
                .font(.system(.caption2, design: .rounded).weight(.semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(tint.opacity(0.12)))
        .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 0.5))
    }
}

/// One row in the cross-deck search results. Compact card row with the deck
/// label so the user can tell where the match lives.
private struct SearchResultRow: View {
    let card: Flashcard
    var isKnown: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(card.expression)
                        .font(.system(.title3, design: .serif))
                        .foregroundStyle(Palette.sumi)
                    if let deck = card.deck {
                        Text(deck.name)
                            .font(.system(.caption2, design: .rounded).weight(.semibold))
                            .foregroundStyle(Palette.indigo.opacity(0.85))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Palette.indigo.opacity(0.10)))
                            .overlay(Capsule().strokeBorder(Palette.indigo.opacity(0.3), lineWidth: 0.5))
                    }
                    if isKnown {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.gold)
                    }
                }
                if !card.reading.isEmpty, card.reading != card.expression {
                    Text(card.reading)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Palette.indigo.opacity(0.85))
                }
                if let meaning = card.meaning, !meaning.isEmpty {
                    Text(meaning)
                        .font(.caption)
                        .foregroundStyle(Palette.mist)
                        .lineLimit(2)
                }
                if !card.tags.isEmpty {
                    FlowLayout(spacing: 4) {
                        ForEach(card.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.system(.caption2, design: .rounded).weight(.medium))
                                .foregroundStyle(Palette.sakura)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Palette.sakura.opacity(0.14)))
                        }
                    }
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Palette.mist.opacity(0.6))
        }
        .padding(14)
        .background(
            (isKnown ? Palette.gold.opacity(0.07) : Palette.washi),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    isKnown ? Palette.gold.opacity(0.45) : Palette.hairline,
                    lineWidth: isKnown ? 1 : 0.75
                )
        )
    }
}
