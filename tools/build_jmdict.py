#!/usr/bin/env python3
"""
Convert jmdict-simplified JSON (optionally Tanaka Corpus examples.utf,
Kanjidic2 kanji metadata, and a Tanos-style JLPT word list) into a SQLite
database the iOS app can query.

Usage:
    python3 build_jmdict.py <jmdict-eng.json> <output.sqlite>
        [--examples <examples.utf>]
        [--kanjidic <kanjidic.json>]
        [--jlpt <jlpt-words.json>]

Schema:
    entries(id, kanji_json, kana_json, senses_json)
    forms(form, entry_id, is_kana, is_common)
    INDEX idx_forms_form ON forms(form)

If --examples is supplied:
    examples(id, ja, en)
    word_examples(headword, example_id)
    INDEX idx_word_examples_headword ON word_examples(headword)

If --kanjidic is supplied:
    kanji(char PRIMARY KEY, on_json, kun_json, meanings_json, jlpt)
    kanji_words(char, entry_id, is_common)
    INDEX idx_kanji_words_char ON kanji_words(char)

    Expected input format is a JSON object keyed by kanji character with
    fields readings_on / readings_kun / meanings (lists) and an optional
    jlpt int (1..5, where 5 = N5). The KanjiVG/davidluzgouveia/kanji-data
    JSON layout works directly.

If --jlpt is supplied:
    word_jlpt(form, level)
    INDEX idx_word_jlpt_form ON word_jlpt(form)
    INDEX idx_word_jlpt_level ON word_jlpt(level)

    Expected input format is a JSON array of {"word", "kana"?, "level"}
    objects (level 1..5, where 5 = N5). Tanos / elzup-style JLPT vocab
    lists fit directly.
"""
import argparse
import json
import os
import re
import sqlite3
import sys


# Strip the first (reading), [sense], {surface}, (#ref), ~ suffix from a B-line token.
# Everything before the first delimiter is the headword (dictionary form).
_HEADWORD_RE = re.compile(r"^([^()\[\]{}~]+)")
# Pull out the surface form from {...} if the token records one.
_SURFACE_RE = re.compile(r"\{([^}]+)\}")

# CJK Unified Ideographs (and extensions) — used to enumerate kanji inside a
# JMdict kanji form so we can build kanji_words (kanji char → entry).
def _is_kanji(ch: str) -> bool:
    code = ord(ch)
    return (
        0x4E00 <= code <= 0x9FFF
        or 0x3400 <= code <= 0x4DBF
        or 0xF900 <= code <= 0xFAFF
        or 0x20000 <= code <= 0x2A6DF
    )


def parse_kanjidic(path: str):
    """Yield (char, on_list, kun_list, meanings, jlpt_or_none) tuples.

    Supports two layouts:
      • Object map: {"亜": {"readings_on": [...], ...}, ...}  (davidluzgouveia)
      • Array of entries with a "literal" or "kanji" field.
    Field name fallbacks cover the common Kanjidic2 JSON variants.
    """
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)

    def pick_list(entry: dict, *keys):
        for k in keys:
            v = entry.get(k)
            if isinstance(v, list):
                return [str(x) for x in v if x]
        return []

    def pick_jlpt(entry: dict):
        for k in ("jlpt", "jlpt_new", "jlptNew"):
            v = entry.get(k)
            if isinstance(v, int) and 1 <= v <= 5:
                return v
        # Old JLPT (4 levels) is sometimes the only thing present. Map it:
        # old 4→N5, 3→N4, 2→N3, 1→N2 (approximate; old level 1 covered N1+N2).
        old = entry.get("jlpt_old")
        if isinstance(old, int):
            return {4: 5, 3: 4, 2: 3, 1: 2}.get(old)
        return None

    items = data.items() if isinstance(data, dict) else (
        ((entry.get("literal") or entry.get("kanji") or ""), entry)
        for entry in data
        if isinstance(entry, dict)
    )

    for char, entry in items:
        if not char or not isinstance(entry, dict):
            continue
        on = pick_list(entry, "readings_on", "on", "on_yomi", "onyomi", "on_readings")
        kun = pick_list(entry, "readings_kun", "kun", "kun_yomi", "kunyomi", "kun_readings")
        meanings = pick_list(entry, "meanings", "meaning", "english", "gloss")
        yield char, on, kun, meanings, pick_jlpt(entry)


def parse_jlpt_words(path: str):
    """Yield (form, level) tuples from a Tanos-style JLPT word list.

    Supports two layouts:
      • Array: [{"word": "会う", "kana": "あう", "level": 5}, ...]
      • Object map keyed by level: {"5": ["会う", "あう", ...], "4": [...]}.
    Both kanji form and kana form (if present and different) are emitted so
    lookups by either surface hit the JLPT table.
    """
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)

    if isinstance(data, dict):
        for level_key, words in data.items():
            try:
                level = int(level_key)
            except (TypeError, ValueError):
                continue
            if not (1 <= level <= 5) or not isinstance(words, list):
                continue
            for w in words:
                if isinstance(w, str) and w:
                    yield w, level
        return

    if not isinstance(data, list):
        return

    for entry in data:
        if not isinstance(entry, dict):
            continue
        level = entry.get("level") or entry.get("jlpt")
        if not isinstance(level, int) or not (1 <= level <= 5):
            continue
        forms = []
        for key in ("word", "kanji", "expression"):
            v = entry.get(key)
            if isinstance(v, str) and v:
                forms.append(v)
        for key in ("kana", "reading", "hiragana"):
            v = entry.get(key)
            if isinstance(v, str) and v:
                forms.append(v)
        for f in set(forms):
            yield f, level


def parse_examples(path: str):
    """Yield (ja, en, headwords:set[str]) tuples from a Tanaka examples.utf file."""
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        a_line = None
        for raw in f:
            line = raw.rstrip("\n").rstrip("\r")
            if line.startswith("A: "):
                a_line = line[3:]
            elif line.startswith("B: ") and a_line is not None:
                # A: 〜JP〜\t〜EN〜#ID=...
                parts = a_line.split("\t", 1)
                if len(parts) != 2:
                    a_line = None
                    continue
                ja = parts[0].strip()
                en = parts[1].split("#ID=", 1)[0].strip()
                tokens = line[3:].split()
                headwords = set()
                for tok in tokens:
                    m = _HEADWORD_RE.match(tok)
                    if m:
                        headwords.add(m.group(1))
                    for sm in _SURFACE_RE.finditer(tok):
                        # also index the actual surface form in the sentence
                        headwords.add(sm.group(1))
                yield ja, en, headwords
                a_line = None


def build(
    json_path: str,
    sqlite_path: str,
    examples_path: str | None,
    kanjidic_path: str | None,
    jlpt_path: str | None,
) -> None:
    with open(json_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    words = data.get("words", [])
    print(f"loaded {len(words):,} entries from {json_path}")

    if os.path.exists(sqlite_path):
        os.remove(sqlite_path)

    conn = sqlite3.connect(sqlite_path)
    conn.execute("PRAGMA journal_mode = OFF")
    conn.execute("PRAGMA synchronous = OFF")
    conn.executescript(
        """
        CREATE TABLE entries (
            id INTEGER PRIMARY KEY,
            kanji_json TEXT NOT NULL,
            kana_json TEXT NOT NULL,
            senses_json TEXT NOT NULL
        );
        CREATE TABLE forms (
            form TEXT NOT NULL,
            entry_id INTEGER NOT NULL,
            is_kana INTEGER NOT NULL,
            is_common INTEGER NOT NULL
        );
        CREATE TABLE examples (
            id INTEGER PRIMARY KEY,
            ja TEXT NOT NULL,
            en TEXT NOT NULL
        );
        CREATE TABLE word_examples (
            headword TEXT NOT NULL,
            example_id INTEGER NOT NULL
        );
        CREATE TABLE kanji (
            char TEXT PRIMARY KEY,
            on_json TEXT NOT NULL,
            kun_json TEXT NOT NULL,
            meanings_json TEXT NOT NULL,
            jlpt INTEGER
        );
        CREATE TABLE kanji_words (
            char TEXT NOT NULL,
            entry_id INTEGER NOT NULL,
            is_common INTEGER NOT NULL
        );
        CREATE TABLE word_jlpt (
            form TEXT NOT NULL,
            level INTEGER NOT NULL
        );
        """
    )

    entry_rows = []
    form_rows = []
    kanji_word_rows = []
    seen_kanji_word: set[tuple[str, int]] = set()

    for w in words:
        try:
            entry_id = int(w["id"])
        except (KeyError, ValueError):
            continue

        kanji_list = [k["text"] for k in w.get("kanji", [])]
        kana_list = [k["text"] for k in w.get("kana", [])]

        senses = []
        for s in w.get("sense", []):
            glosses = [g["text"] for g in s.get("gloss", []) if g.get("text")]
            if not glosses:
                continue
            senses.append({
                "pos": s.get("partOfSpeech", []),
                "gloss": glosses,
            })

        if not senses:
            continue

        entry_rows.append((
            entry_id,
            json.dumps(kanji_list, ensure_ascii=False),
            json.dumps(kana_list, ensure_ascii=False),
            json.dumps(senses, ensure_ascii=False, separators=(",", ":")),
        ))

        is_entry_common = any(k.get("common") for k in w.get("kanji", []))

        for k in w.get("kanji", []):
            form_rows.append((k["text"], entry_id, 0, 1 if k.get("common") else 0))
            for ch in k["text"]:
                if not _is_kanji(ch):
                    continue
                key = (ch, entry_id)
                if key in seen_kanji_word:
                    continue
                seen_kanji_word.add(key)
                kanji_word_rows.append((ch, entry_id, 1 if is_entry_common else 0))
        for k in w.get("kana", []):
            form_rows.append((k["text"], entry_id, 1, 1 if k.get("common") else 0))

    print(
        f"writing {len(entry_rows):,} entries / {len(form_rows):,} forms / "
        f"{len(kanji_word_rows):,} kanji-word links…"
    )
    conn.executemany(
        "INSERT INTO entries (id, kanji_json, kana_json, senses_json) VALUES (?, ?, ?, ?)",
        entry_rows,
    )
    conn.executemany(
        "INSERT INTO forms (form, entry_id, is_kana, is_common) VALUES (?, ?, ?, ?)",
        form_rows,
    )
    conn.executemany(
        "INSERT INTO kanji_words (char, entry_id, is_common) VALUES (?, ?, ?)",
        kanji_word_rows,
    )
    conn.execute("CREATE INDEX idx_forms_form ON forms(form)")
    conn.execute("CREATE INDEX idx_kanji_words_char ON kanji_words(char)")

    if examples_path:
        print(f"loading examples from {examples_path}…")
        example_rows = []
        link_rows = []
        next_id = 1
        for ja, en, headwords in parse_examples(examples_path):
            if not ja or not en:
                continue
            example_rows.append((next_id, ja, en))
            for hw in headwords:
                link_rows.append((hw, next_id))
            next_id += 1
        print(f"writing {len(example_rows):,} examples / {len(link_rows):,} links…")
        conn.executemany(
            "INSERT INTO examples (id, ja, en) VALUES (?, ?, ?)", example_rows
        )
        conn.executemany(
            "INSERT INTO word_examples (headword, example_id) VALUES (?, ?)", link_rows
        )
        conn.execute(
            "CREATE INDEX idx_word_examples_headword ON word_examples(headword)"
        )

    if kanjidic_path:
        print(f"loading kanjidic from {kanjidic_path}…")
        kanji_rows = []
        for char, on, kun, meanings, jlpt in parse_kanjidic(kanjidic_path):
            kanji_rows.append((
                char,
                json.dumps(on, ensure_ascii=False),
                json.dumps(kun, ensure_ascii=False),
                json.dumps(meanings, ensure_ascii=False),
                jlpt,
            ))
        print(f"writing {len(kanji_rows):,} kanji records…")
        conn.executemany(
            "INSERT OR REPLACE INTO kanji (char, on_json, kun_json, meanings_json, jlpt) "
            "VALUES (?, ?, ?, ?, ?)",
            kanji_rows,
        )

    if jlpt_path:
        print(f"loading JLPT word list from {jlpt_path}…")
        jlpt_rows = list(parse_jlpt_words(jlpt_path))
        print(f"writing {len(jlpt_rows):,} word-level rows…")
        conn.executemany(
            "INSERT INTO word_jlpt (form, level) VALUES (?, ?)", jlpt_rows
        )
        conn.execute("CREATE INDEX idx_word_jlpt_form ON word_jlpt(form)")
        conn.execute("CREATE INDEX idx_word_jlpt_level ON word_jlpt(level)")

    conn.commit()
    conn.isolation_level = None
    conn.execute("VACUUM")
    conn.close()

    size_mb = os.path.getsize(sqlite_path) / (1024 * 1024)
    print(f"done. {sqlite_path}  ({size_mb:.1f} MB)")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("jmdict_json", help="jmdict-simplified JSON input")
    parser.add_argument("output_sqlite", help="SQLite output path")
    parser.add_argument("--examples", help="Tanaka Corpus examples.utf")
    parser.add_argument("--kanjidic", help="Kanjidic2 JSON (on/kun/meanings/jlpt per kanji)")
    parser.add_argument("--jlpt", help="JLPT word list JSON (word/kana/level)")
    args = parser.parse_args()

    build(
        args.jmdict_json,
        args.output_sqlite,
        args.examples,
        args.kanjidic,
        args.jlpt,
    )
