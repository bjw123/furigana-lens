# Furigana Lens

Personal iOS app for reading Japanese from your TV while gaming. Point the camera, capture text, tap a word for furigana, optionally reveal meaning via [Jisho](https://jisho.org/), and save flashcards with SM-2 spaced repetition.

## Features

- **Freeze-frame camera** + on-device Vision OCR (Japanese)
- **Tap a word** — furigana for that word only, not the full sentence
- **Show meaning** — Jisho lookup (free); edit before saving
- **Optional flashcards** — decks by game/anime/manga; reading / meaning / sentence card types
- **SRS review** — SM-2 scheduling (Again / Hard / Good / Easy)
- **$0 runtime** — no paid APIs; readings use on-device tokenization + Jisho when needed

## Requirements

- iPhone with iOS 17+
- Xcode 15+ (full Xcode, not Command Line Tools only)
- Apple Developer account to install on device

## Open in Xcode

```bash
cd furigana-lens
xcodegen generate   # requires: brew install xcodegen
open FuriganaLens.xcodeproj
```

Then select the **FuriganaLens** scheme, your iPhone simulator or device, and Run.

If `xcodegen` is unavailable, create a new **App** project in Xcode named `FuriganaLens`, set deployment target iOS 17, and add all files under `FuriganaLens/` to the target. Add camera usage description:

`NSCameraUsageDescription` = Point your camera at Japanese text on your TV or screen to read words and furigana.

## Project layout

```
FuriganaLens/
├── FuriganaLensApp.swift
├── Features/Scan/          Camera + OCR + word chips
├── Features/WordDetail/    Furigana sheet, Jisho, save card
├── Features/Decks/
├── Features/Review/
├── Services/               OCR, Japanese analysis, Jisho, SRS
├── Models/                 SwiftData Deck + Flashcard
└── Resources/              reading_overrides.json
```

## Data sources

- OCR: Apple Vision (`VNRecognizeTextRequest`)
- Tokenization: `NaturalLanguage` (`NLTokenizer`) on device
- Readings/meanings: [Jisho API](https://jisho.org/api/v1/search/words) (unofficial; use respectfully)
- Dictionary data attribution: JMdict (via Jisho)

## License

Personal project. JMdict/Jisho data subject to their respective licenses.
