# AGENTS.md

Operating notes for AI coding agents working on this repo. If you're a human, the README has the user-facing story; this file is the "what you actually need to know to be useful here" version.

---

## 1. The app in two sentences

Kanji Crush is a SwiftUI iOS 18 app that points your camera at Japanese text (a TV, a manga page, a screen), runs Vision OCR + an on-device tokenizer, and lets you save SRS flashcards. Dictionary, examples, JLPT levels, and per-kanji on/kun readings are baked into a bundled offline SQLite, so the main flow has no network calls.

---

## 2. Build / run

Project is generated, not hand-edited. The source of truth for targets, schemes, and bundle IDs is `project.yml`.

```bash
brew install xcodegen          # one-off
xcodegen generate              # whenever project.yml, source layout, or assets change
open KanjiCrush.xcodeproj
```

Three targets: `KanjiCrush` (app), `KanjiCrushTests` (unit), `KanjiCrushUITests` (UI). Bundle IDs are `com.kanjicrush.app[.tests|.uitests]`. Display name is set via `INFOPLIST_KEY_CFBundleDisplayName` — don't try to set it in Info.plist directly, plists are generated.

**The Xcode project file should not be hand-edited.** If you need to add a Swift file under `KanjiCrush/`, just write it — `xcodegen` picks it up on the next regenerate. If you add a *new* file while Xcode is open, re-run `xcodegen generate` and reload the project window.

---

## 3. Source layout & conventions

```
KanjiCrush/
├── KanjiCrushApp.swift     @main + ModelContainer for the SwiftData schema
├── Features/<area>/        One folder per top-level surface (Scan, Decks, …)
├── Services/               Pure-ish helpers, services, SwiftData-free where possible
├── Models/                 SwiftData @Model classes only
├── Theme/                  Palette + reusable visual primitives
├── Utilities/              CTRubyAnnotation furigana views
└── Resources/              Asset catalog, jmdict.sqlite.gz, JSON
tools/                      Python data pipeline + Swift icon generator
KanjiCrushTests/            Unit tests + Fixtures/ image fixtures
KanjiCrushUITests/          UI smoke tests
```

### SwiftData

- Schema lives at `KanjiCrush/Models/`: `Deck`, `Flashcard`, `ReviewLog`, `KnownWord`.
- The `ModelContainer` is instantiated in `KanjiCrushApp.init()` with the explicit `Schema([…])` list — when you add a `@Model`, add it there too.
- `Flashcard.cardType` is stored as `cardTypeRaw: String` for forward-compat; `CardType.from(rawValue:)` maps legacy `"reading"` / `"meaning"` rows onto the current `.word` case. Preserve that mapping when touching the type.
- `KnownWord.isKnown: Bool` defaults to `true`. A row with `isKnown == false` means the user explicitly overrode a JLPT-implied "known" — see `Services/Knownness.swift`. Don't insert rows when the desired state matches the JLPT default.

### Theme / visual primitives

`KanjiCrush/Theme/Theme.swift` is the single source of truth for visuals. Don't redefine palette colors locally; pull from `Palette.sakura`, `Palette.indigo`, `Palette.bamboo`, `Palette.gold`, `Palette.sumi`, `Palette.mist`, `Palette.washi`, `Palette.cream`. Reusable views:

- `WashiBackground` — root background gradient + optional seigaiha wave.
- `WashiCard` / `.washiCard()` modifier — default surface for content cards.
- `GemTile`, `KanjiGemBadge`, `KanjiGemBoard`, `SparkleAccent` — the "Kanji Crush" candy-tile identity (matches the app icon). Use these for hero/brand surfaces.
- `BrushDivider`, `SectionHeader`, `MapleGlyph` — section/decorative helpers.

### Naming + style

- Filenames match the primary type: `KanjiTypedReviewView.swift` → `struct KanjiTypedReviewView`.
- Prefer composition (small `private` view properties) over giant single bodies — the existing screens follow that pattern (`var dueHero`, `var deckRows`, etc.).
- Comments: keep them load-bearing (why / non-obvious invariant). Don't restate what the code says. Existing comments are tight; keep yours tighter.
- No emojis in source unless asked.

---

## 4. Dictionary data pipeline

The bundled `KanjiCrush/Resources/jmdict.sqlite.gz` is built by `tools/build_jmdict.py`:

```
python3 tools/build_jmdict.py jmdict-eng.json out.sqlite \
  --examples examples.utf \
  --kanjidic kanji.json \
  --jlpt jlpt-words.json
gzip -9 -f out.sqlite
```

Tables / indexes in the resulting DB:

| Table          | Purpose                                                  |
|----------------|----------------------------------------------------------|
| `entries`      | JMdict entries (kanji/kana/senses as JSON columns)       |
| `forms`        | Every kanji + kana form → entry, indexed for lookup      |
| `examples`     | Tanaka Corpus sentence pairs                             |
| `word_examples`| Headword → example_id, indexed                           |
| `kanji`        | Kanjidic2: char → on_json, kun_json, meanings_json, jlpt |
| `kanji_words`  | char → entry_id, indexed (used by JLPT examples query)   |
| `word_jlpt`    | form → JLPT level (1..5, 5=N5)                           |

`DictionaryService` is the only consumer; queries use SQLite's `json_each` (available via the system SQLite shipped with iOS).

**Cache stamp**: `ensureDatabaseUnpacked()` keys off the gzip file size. Any change to the bundled DB triggers a re-unpack on next launch — no manual bump needed.

---

## 5. Tokenization & furigana

- `JapaneseAnalysisService` uses `CFStringTokenizer` with `kCFStringTokenizerAttributeLatinTranscription`, then `CFStringTransform(kCFStringTransformLatinHiragana)` to convert romaji → hiragana. Same path Apple uses for VoiceOver / TTS, so it handles conjugations reasonably.
- `JapaneseToken` is the canonical token type. `segments(_:)` keeps punctuation/spacing (used for rendering whole sentences); `tokenize(_:)` drops them (used for word chips).
- `Utilities/FuriganaText.swift` exposes `FuriganaWordView` (single word + ruby) and `FuriganaSentenceView` (sentence with per-token ruby on kanji tokens). They wrap a `UILabel` because SwiftUI doesn't have a native `CTRubyAnnotation` API.
- **Ruby clipping gotcha**: at small font sizes, `UILabel`'s default line height doesn't reserve enough room above the baseline for `CTRubyAnnotation`. Where it matters (word-card back, kanji detail rows, sentence breakdown), the views additionally render the reading as plain text below — belt-and-suspenders, not redundancy.

---

## 6. Known footguns

- **SourceKit macro plugin errors** (`SwiftDataMacros.QueryMacro could not be found`) are diagnostic noise when SourceKit runs outside Xcode (e.g. from a CLI editor or LSP). They are not compile errors. Build through Xcode (`xcodebuild` or the IDE) to confirm real issues.
- **iOS icon cache** is aggressive — replacing `Icon-1024.png` and rebuilding often shows the old icon. Delete the app from the device + Clean Build Folder, or live with the cache for 24h.
- **Bundle ID changes wipe SwiftData** — the on-device SwiftData store is keyed off the bundle ID. Changing it produces a fresh app with empty state on next install. The repo went through this once (`com.furiganalens.app` → `com.kanjicrush.app`).
- **Simulator has no camera** — `FigCaptureSourceRemote err=-17281` and `AVAudioBuffer.mm:281` log noise are simulator-only; the app still launches. Don't waste time chasing them.
- **`-seedMockData reset` wipes data** then reseeds. `append` is a no-op if any deck already exists. Use launch arguments in Xcode's scheme editor.

---

## 7. Testing

- Unit tests live in `KanjiCrushTests/` and import the app module via `@testable import KanjiCrush`.
- `Fixtures/` holds real game screenshots used by `OCRPipelineTests` — these are the only assertions we have that the OCR + tokenizer chain actually produces useful tokens end-to-end. If you change tokenization, expect these to be the early-warning system.
- UI tests in `KanjiCrushUITests/` are smoke-only: launch, tab navigation, a manual lookup roundtrip. Keep them fast.

---

## 8. When in doubt

- The README has the human-facing pitch and the rebuild commands for the bundled dictionary.
- The git log is the changelog; commit messages here are kept short, lead with the "why" not the "what".
- If a piece of state could be derived (e.g. JLPT-implied known) instead of stored, prefer derivation. We persist only the override cases.
