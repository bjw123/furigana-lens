# Kanji Crush

Personal iOS app for reading Japanese from your TV while gaming. Point the camera, capture text, tap a word for furigana, optionally reveal meaning via opensourced data and libraries + internal iphone translation/language kit and save flashcards with SM-2 spaced repetition.

## Demo

[![Demo walkthrough — 81 seconds](docs/screenshots/01.png)](https://github.com/bjw123/kanji-crush/releases/download/v0.1.0/demo.mp4)

▶ [**Download the 81-second walkthrough**](https://github.com/bjw123/kanji-crush/releases/download/v0.1.0/demo.mp4) (released as a [v0.1.0](https://github.com/bjw123/kanji-crush/releases/tag/v0.1.0) asset). Point the camera at a TV running Persona 5, capture, tap a chip, reveal a reading, save it to a deck, then review it.

> Why not inline-embedded? GitHub's README sanitizer only allows `<video>` tags pointing at the `user-attachments` CDN, and repo paths (raw + release assets) are served with a sandbox CSP that forces download. To inline-embed: open `README.md` on github.com → Edit → drag the mp4 into the editor → GitHub uploads it to `user-attachments/assets/<uuid>` → replace the link above with the resulting markdown. The screenshot gallery below covers the same ground without that step.

## Screenshots

<table>
  <tr>
    <td align="center" width="20%">
      <img src="docs/screenshots/01.png" width="180"><br>
      <sub><b>Scan a TV</b><br>frozen frame + word chips</sub>
    </td>
    <td align="center" width="20%">
      <img src="docs/screenshots/02.png" width="180"><br>
      <sub><b>Tap for reading</b><br>furigana over the kanji</sub>
    </td>
    <td align="center" width="20%">
      <img src="docs/screenshots/03.png" width="180"><br>
      <sub><b>Word detail</b><br>mark known or look up meaning</sub>
    </td>
    <td align="center" width="20%">
      <img src="docs/screenshots/04.png" width="180"><br>
      <sub><b>Save flashcard</b><br>word card or sentence card</sub>
    </td>
    <td align="center" width="20%">
      <img src="docs/screenshots/05.png" width="180"><br>
      <sub><b>Decks</b><br>tagged by game / anime</sub>
    </td>
  </tr>
  <tr>
    <td align="center" width="20%">
      <img src="docs/screenshots/06.png" width="180"><br>
      <sub><b>Deck overview</b><br>new · learning · mature</sub>
    </td>
    <td align="center" width="20%">
      <img src="docs/screenshots/07.png" width="180"><br>
      <sub><b>Edit a card</b><br>expression · meaning · interval</sub>
    </td>
    <td align="center" width="20%">
      <img src="docs/screenshots/08.png" width="180"><br>
      <sub><b>Review home</b><br>review all, or pick a deck</sub>
    </td>
    <td align="center" width="20%">
      <img src="docs/screenshots/09.png" width="180"><br>
      <sub><b>Front of card</b><br>show answer when ready</sub>
    </td>
    <td align="center" width="20%">
      <img src="docs/screenshots/10.png" width="180"><br>
      <sub><b>Grade the answer</b><br>SM-2: Again · Hard · Good · Easy</sub>
    </td>
  </tr>
</table>

## Features

- **Freeze-frame camera** + on-device Vision OCR (Japanese)
- **Tap a word** — furigana for that word only, not the full sentence
- **Offline JMdict + Tanaka + Kanjidic2** — readings, meanings, JLPT levels, and example sentences resolve locally, no network roundtrip
- **Two flashcard types** — word cards (kanji + example on front; furigana + meaning + audio + further examples on back) and sentence cards (full sentence + furigana breakdown + per-token glosses + audio on back)
- **SRS review** — SM-2 scheduling (Again / Hard / Good / Easy)
- **Typed kanji review** — drill a kanji's on/kun readings and JLPT example words by typing the answer (accepts hiragana, katakana, or romaji); wrong answers requeue until you get them right
- **JLPT level integration** — pick your level in Settings; words at or below the level are auto-marked as known, and any flashcard for a "should-be-known" word gets a yellow warning
- **Struggling-kanji tiles, by reading** — Review home highlights kanji whose specific on/kun reading you keep missing (not just the kanji aggregate), with one-tap drill-in
- **Audio playback** — `AVSpeechSynthesizer` reads card backs and sentences aloud
- **Sentence translation** — Apple's on-device `Translation` framework wires up an inline ja→en option on captured sentences
- **$0 runtime** — fully offline; no paid APIs, no network calls for the main flow

## Requirements

- iPhone with iOS 18+
- Xcode 16+ (full Xcode, not Command Line Tools only)
- Apple Developer account to install on device

## Open in Xcode

```bash
cd kanjicrush
xcodegen generate   # requires: brew install xcodegen
open KanjiCrush.xcodeproj
```

Then select the **KanjiCrush** scheme, your iPhone simulator or device, and Run.

If `xcodegen` is unavailable, create a new **App** project in Xcode named `KanjiCrush`, set deployment target iOS 17, and add all files under `KanjiCrush/` to the target. Add camera usage description:

`NSCameraUsageDescription` = Point your camera at Japanese text on your TV or screen to read words and furigana.

## Project layout

```
KanjiCrush/
├── KanjiCrushApp.swift        @main, ModelContainer, global appearance
├── Features/
│   ├── Scan/                  Camera + OCR + sentence/word chip surface
│   ├── WordDetail/            Word sheet + SaveFlashcardSheet
│   ├── Decks/                 Deck list, deck detail, card edit
│   ├── Review/                Review home + ReviewSessionView (SRS)
│   ├── Kanji/                 KanjiDetailView + KanjiTypedReviewView
│   ├── Settings/              JLPT level, reading filters, appearance
│   └── RootTabView.swift
├── Services/
│   ├── OCRService              Vision text recognition
│   ├── JapaneseAnalysisService CFStringTokenizer + Latin→Hiragana
│   ├── DictionaryService       Offline JMdict + Tanaka + Kanjidic2 (SQLite)
│   ├── SRSService              SM-2 scheduling
│   ├── StatsService            Forecast, streak, struggling kanji-by-reading
│   ├── Knownness               Combines KnownWord + JLPT-implied known
│   ├── SpeechService           AVSpeechSynthesizer wrapper
│   ├── ReadingOverrideStore    User-editable per-word reading overrides
│   └── MockDataSeeder          Dev mode: -seedMockData reset|append
├── Models/                     SwiftData @Model: Deck, Flashcard, ReviewLog, KnownWord
├── Theme/Theme.swift           Palette + WashiBackground + GemTile primitives
├── Utilities/FuriganaText.swift CTRubyAnnotation-backed views
└── Resources/
    ├── Assets.xcassets         AppIcon, color sets
    ├── jmdict.sqlite.gz        Bundled offline dictionary (~50 MB)
    └── reading_overrides.json
tools/
├── build_jmdict.py             Builds jmdict.sqlite.gz from source data
└── generate_icon.swift         Renders AppIcon-1024.png via SwiftUI ImageRenderer
```

## Data sources

- **OCR**: Apple Vision (`VNRecognizeTextRequest`)
- **Tokenization & readings**: `CFStringTokenizer` with `kCFStringTokenizerAttributeLatinTranscription`, then `CFStringTransform(kCFStringTransformLatinHiragana)`
- **Dictionary, examples, JLPT, kanji metadata** — all baked into the bundled `jmdict.sqlite.gz`. Built locally via `tools/build_jmdict.py` from:
    - [JMdict-simplified](https://github.com/scriptin/jmdict-simplified) (`jmdict-eng-*.json`) — words + glosses
    - [Tanaka Corpus](https://ftp.edrdg.org/pub/Nihongo/examples.utf.gz) — example sentences
    - [davidluzgouveia/kanji-data](https://github.com/davidluzgouveia/kanji-data) — Kanjidic2 JSON for per-kanji on/kun readings, meanings, JLPT levels
    - [jamsinclair/open-anki-jlpt-decks](https://github.com/jamsinclair/open-anki-jlpt-decks) — JLPT N5–N1 word lists
- **Translation**: Apple `Translation` framework (on-device)
- **Text-to-speech**: `AVSpeechSynthesizer` (`ja-JP`)

## Rebuilding the bundled dictionary

```bash
python3 tools/build_jmdict.py \
  /path/to/jmdict-eng.json \
  KanjiCrush/Resources/jmdict.sqlite \
  --examples /path/to/examples.utf \
  --kanjidic /path/to/kanji.json \
  --jlpt /path/to/jlpt-words.json
gzip -9 -f KanjiCrush/Resources/jmdict.sqlite
```

The `DictionaryService` keys cache invalidation off the gzip file size, so a fresh build automatically re-unpacks on next launch.

## License

Personal project. JMdict, Kanjidic2, Tanaka Corpus, and the JLPT word lists are subject to their respective licenses; see each source repo for terms.
