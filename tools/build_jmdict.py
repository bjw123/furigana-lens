#!/usr/bin/env python3
"""
Convert jmdict-simplified JSON (and optionally Tanaka Corpus examples.utf)
into a SQLite database the iOS app can query.

Usage:
    python3 build_jmdict.py <jmdict-eng.json> <output.sqlite> [examples.utf]

Schema:
    entries(id, kanji_json, kana_json, senses_json)
    forms(form, entry_id, is_kana, is_common)
    INDEX idx_forms_form ON forms(form)

If examples.utf is supplied:
    examples(id, ja, en)
    word_examples(headword, example_id)
    INDEX idx_word_examples_headword ON word_examples(headword)
"""
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


def build(json_path: str, sqlite_path: str, examples_path: str | None) -> None:
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
        """
    )

    entry_rows = []
    form_rows = []

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

        for k in w.get("kanji", []):
            form_rows.append((k["text"], entry_id, 0, 1 if k.get("common") else 0))
        for k in w.get("kana", []):
            form_rows.append((k["text"], entry_id, 1, 1 if k.get("common") else 0))

    print(f"writing {len(entry_rows):,} entries / {len(form_rows):,} forms…")
    conn.executemany(
        "INSERT INTO entries (id, kanji_json, kana_json, senses_json) VALUES (?, ?, ?, ?)",
        entry_rows,
    )
    conn.executemany(
        "INSERT INTO forms (form, entry_id, is_kana, is_common) VALUES (?, ?, ?, ?)",
        form_rows,
    )
    conn.execute("CREATE INDEX idx_forms_form ON forms(form)")

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

    conn.commit()
    conn.isolation_level = None
    conn.execute("VACUUM")
    conn.close()

    size_mb = os.path.getsize(sqlite_path) / (1024 * 1024)
    print(f"done. {sqlite_path}  ({size_mb:.1f} MB)")


if __name__ == "__main__":
    if len(sys.argv) not in (3, 4):
        print(__doc__)
        sys.exit(1)
    json_path = sys.argv[1]
    sqlite_path = sys.argv[2]
    examples_path = sys.argv[3] if len(sys.argv) == 4 else None
    build(json_path, sqlite_path, examples_path)
