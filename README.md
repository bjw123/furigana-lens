# Kanji Crush

Personal iOS app for reading Japanese from your TV while gaming. Point the camera, capture text, tap a word for furigana, optionally reveal meaning via [Jisho](https://jisho.org/), and save flashcards with SM-2 spaced repetition.

## Demo

[![Demo walkthrough — 81 seconds](docs/screenshots/01.png)](https://github.com/bjw123/kanjicrush/releases/download/v0.1.0/demo.mp4)

▶ [**Download the 81-second walkthrough**](https://github.com/bjw123/kanjicrush/releases/download/v0.1.0/demo.mp4) (released as a [v0.1.0](https://github.com/bjw123/kanjicrush/releases/tag/v0.1.0) asset). Point the camera at a TV running Persona 5, capture, tap a chip, reveal a reading, save it to a deck, then review it.

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
      <sub><b>Save flashcard</b><br>reading / meaning / sentence</sub>
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
├── KanjiCrushApp.swift
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
