import SwiftUI

extension SentenceSpeechCheckView {

    // MARK: - Continuous auto-advance

    func candidates(for chunk: Chunk) -> [String] {
        let dictEntries = DictionaryService.shared.lookup(chunk.surface, limit: 3)
        return JapaneseMatching.candidates(
            forExpression: chunk.surface,
            tokenReading: chunk.reading,
            jmdictEntries: dictEntries
        )
    }

    /// Drives the auto-advance loop. Folds the live transcript, slices off
    /// the prefix already consumed by past chunks, and if the suffix contains
    /// any candidate for the current chunk, marks it correct and advances.
    /// Loops because a single transcript update can resolve multiple chunks
    /// at once when the user reads quickly.
    func processTranscript(_ raw: String) {
        guard speech.isListening || !raw.isEmpty else { return }
        guard !sessionComplete else { return }
        let normalised = JapaneseMatching.normalize(raw)

        // If the recogniser truncated the transcript (rare — happens when a
        // cycle restarts and the new partial is shorter than the prefix), pull
        // `consumedPrefix` back so we don't get stuck.
        if !consumedPrefix.isEmpty, !normalised.hasPrefix(consumedPrefix) {
            consumedPrefix = ""
            chunkConsumedBaseline = 0
        }

        var progressed = true
        while progressed, currentIndex < chunks.count {
            progressed = false
            let chunk = chunks[currentIndex]
            let suffix = String(normalised.dropFirst(consumedPrefix.count))
            guard !suffix.isEmpty else { break }

            let cands = candidates(for: chunk)
            guard !cands.isEmpty else {
                // Nothing to match against (empty reading + empty surface) —
                // skip the chunk so the user isn't blocked.
                advanceCurrentChunk(matched: false, transcriptForResult: nil)
                progressed = true
                continue
            }

            // Short-reading guard: only applied AFTER the user has already
            // consumed at least one chunk. For short kana readings (1-2 mora),
            // require enough new suffix growth since this chunk became active
            // so a stray particle at the end of the previous chunk doesn't
            // pre-match the next one. For the FIRST chunk (consumedPrefix
            // empty), no guard — the suffix IS the entire transcript and we
            // want auto-advance to fire immediately on the very first match.
            // We also restrict the "short" heuristic to kana-only candidates,
            // because a kanji surface like 人間 happens to be 2 characters
            // but represents 4 mora of speech — guarding it would be wrong.
            if !consumedPrefix.isEmpty {
                let kanaShortest = cands
                    .filter { cand in
                        cand.unicodeScalars.allSatisfy { (0x3040...0x309F).contains($0.value) }
                    }
                    .map(\.count)
                    .min() ?? Int.max
                let suffixGrowthSinceActive = consumedPrefix.count - chunkConsumedBaseline
                if kanaShortest <= 2, suffixGrowthSinceActive < max(kanaShortest - 1, 0) {
                    // Don't try to match this chunk yet — wait for more audio.
                    break
                }
            }

            // Look for the earliest position in `suffix` that contains any
            // candidate as a contiguous substring. Picking the earliest hit
            // keeps the consumed prefix tight against the spoken span.
            var bestEnd: Int?
            for cand in cands {
                if let range = suffix.range(of: cand) {
                    let endOffset = suffix.distance(from: suffix.startIndex, to: range.upperBound)
                    if bestEnd == nil || endOffset < bestEnd! {
                        bestEnd = endOffset
                    }
                }
            }

            // Strict substring failed — try fuzzy matching anchored at the
            // start of `suffix`. Catches running-together cases like
            // "ストレスでしょ" → "ストレッスでしょ" where a candidate doesn't
            // appear as a clean substring but is within edit distance.
            if bestEnd == nil {
                for cand in cands {
                    guard let range = JapaneseMatching.fuzzyMatchEnd(in: suffix, against: cand) else { continue }
                    let endOffset = suffix.distance(from: suffix.startIndex, to: range.upperBound)
                    if bestEnd == nil || endOffset < bestEnd! {
                        bestEnd = endOffset
                    }
                }
            }
            guard let endOffset = bestEnd else { break }

            // Snap consumedPrefix forward through the matched span.
            let newPrefixCount = consumedPrefix.count + endOffset
            consumedPrefix = String(normalised.prefix(newPrefixCount))
            advanceCurrentChunk(matched: true, transcriptForResult: chunk.surface)
            progressed = true
        }

        if shouldFinishAfterAdvance() {
            finishSession()
        }
    }

    /// True when the user has either reached the natural end of the sentence
    /// (`currentIndex >= chunks.count`) OR has matched their tap-chosen
    /// endpoint (`currentIndex > targetIndex`).
    func shouldFinishAfterAdvance() -> Bool {
        if currentIndex >= chunks.count { return true }
        if let target = targetIndex, currentIndex > target { return true }
        return false
    }

    /// Marks the active chunk's outcome and bumps the index. Does NOT touch
    /// `consumedPrefix` — the caller handles that.
    func advanceCurrentChunk(matched: Bool, transcriptForResult: String?, skipped: Bool = false) {
        guard currentIndex < chunks.count else { return }
        let chunk = chunks[currentIndex]
        results.removeAll { $0.id == chunk.id }
        results.append(ChunkResult(
            id: chunk.id,
            surface: chunk.surface,
            expectedReading: chunk.reading,
            matched: matched,
            skipped: skipped,
            transcript: transcriptForResult ?? ""
        ))
        if matched {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            chunkFeedback = .correct
        }
        currentIndex += 1
        chunkConsumedBaseline = consumedPrefix.count
    }

    /// User-initiated skip. The chunk doesn't count as correct, but it doesn't
    /// count as a hard failure either — it lands in the summary as a
    /// "skipped" entry the user can still save as a flashcard. Used when the
    /// speech recognizer is fighting them on a particular word.
    func skipCurrentChunk() {
        guard currentIndex < chunks.count else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        chunkFeedback = nil
        advanceCurrentChunk(matched: false, transcriptForResult: nil, skipped: true)
        if shouldFinishAfterAdvance() {
            finishSession()
        }
    }

    /// Manual "I read this" override — checks the current live transcript
    /// against the chunk's candidate readings before advancing. If the user
    /// hasn't actually said the chunk yet, marks it WRONG and shows what was
    /// heard vs. what was expected, so the button can't be abused to skip
    /// past a chunk by saying the wrong word.
    func manuallyAdvance(chunk: Chunk) {
        guard let idx = chunks.firstIndex(where: { $0.id == chunk.id }), idx == currentIndex else { return }

        let normalised = JapaneseMatching.normalize(speech.transcript)
        let suffix = String(normalised.dropFirst(consumedPrefix.count))
        let cands = candidates(for: chunk)

        // Match logic mirrors the auto-advance pass — any candidate appearing
        // in the un-consumed suffix counts. Empty transcript (user pressed the
        // button without saying anything) is treated as wrong.
        var matchedEnd: Int?
        for cand in cands where !cand.isEmpty {
            if let range = suffix.range(of: cand) {
                let endOffset = suffix.distance(from: suffix.startIndex, to: range.upperBound)
                if matchedEnd == nil || endOffset < matchedEnd! {
                    matchedEnd = endOffset
                }
            }
        }

        if let endOffset = matchedEnd {
            // Snap consumedPrefix forward through the matched span so further
            // auto-advance from the same transcript update keeps working.
            let newPrefixCount = consumedPrefix.count + endOffset
            consumedPrefix = String(normalised.prefix(newPrefixCount))
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            advanceCurrentChunk(matched: true, transcriptForResult: chunk.surface)
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            chunkFeedback = .wrong(
                expected: chunk.reading,
                heard: speech.transcript.isEmpty ? "(nothing yet)" : speech.transcript
            )
            // Record the failure as a chunk result but DON'T advance — the
            // user gets a try-again chance.
            results.removeAll { $0.id == chunk.id }
            results.append(ChunkResult(
                id: chunk.id,
                surface: chunk.surface,
                expectedReading: chunk.reading,
                matched: false,
                skipped: false,
                transcript: speech.transcript
            ))
            return
        }
        if shouldFinishAfterAdvance() {
            finishSession()
        }
    }

    /// Wraps up the session normally — recogniser off, summary on. Any chunks
    /// the user didn't reach simply have no `results` entry and the summary
    /// shows them as pending.
    func finishSession() {
        if speech.isListening { speech.stop() }
        sessionComplete = true
        chunkFeedback = nil
    }

    /// User-initiated early end — same as `finishSession` but explicit so the
    /// call-site reads clearly.
    func finishSessionEarly() {
        finishSession()
    }

    func resetSession() {
        results.removeAll()
        currentIndex = 0
        input = ""
        chunkFeedback = nil
        sessionComplete = false
        consumedPrefix = ""
        chunkConsumedBaseline = 0
    }

    // MARK: - Speech

    func toggleListening() async {
        if !authChecked {
            _ = await speech.requestAuthorization()
            authChecked = true
        }
        if speech.isListening {
            // Pressing mic again while live ends the session — same flow as
            // tapping "Finish session". Anything not yet matched lands in
            // the pending bucket in the summary.
            finishSessionEarly()
        } else {
            input = ""
            chunkFeedback = nil
            consumedPrefix = ""
            chunkConsumedBaseline = 0
            // Continuous reading needs the service to keep listening across
            // silence pauses — flip the flag back on (it's the default but
            // KanjiTypedReviewView shares the same type and disables it).
            speech.continuousMode = true
            do { try speech.start() } catch {
                // Service exposes the error on its own publisher; we don't
                // surface inline failures here.
            }
        }
    }

    // MARK: - Chunk building

    /// Build the initial chunk list from the sentence. One chunk per content-
    /// bearing token (kanji-containing or kana run of length ≥ 2); particles,
    /// short kana, punctuation and whitespace glue onto the preceding chunk
    /// so each chunk reads as a natural sub-phrase. If the heuristic produces
    /// no content chunk, fall back to a single chunk for the entire sentence.
    static func buildChunks(for sentence: String) -> [Chunk] {
        let segments = JapaneseAnalysisService.shared.segments(sentence)
        guard !segments.isEmpty else {
            let reading = JapaneseAnalysisService.shared.localReading(for: sentence)
            return [Chunk(
                id: UUID(),
                surface: sentence,
                reading: JapaneseMatching.normalize(reading),
                segmentIndices: []
            )]
        }

        var chunks: [Chunk] = []
        for (idx, seg) in segments.enumerated() {
            let isAnchor = seg.hasKanji || (seg.hasKana && seg.surface.count >= 2)
            if isAnchor || chunks.isEmpty {
                chunks.append(Chunk(
                    id: UUID(),
                    surface: seg.surface,
                    reading: JapaneseMatching.normalize(seg.reading),
                    segmentIndices: [idx]
                ))
            } else {
                // Glue onto the previous chunk.
                var last = chunks.removeLast()
                last.surface += seg.surface
                last.reading = JapaneseMatching.normalize(last.reading + seg.reading)
                last.segmentIndices.append(idx)
                chunks.append(last)
            }
        }

        // Drop any chunks that ended up empty / whitespace-only after gluing
        // AND any chunks whose surface is just punctuation / quote marks
        // (e.g. a leading 「 or trailing 。) — those have nothing to speak
        // and otherwise show up as empty / orphan capsules in the UI.
        chunks = chunks.filter { chunk in
            let trimmed = chunk.surface.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            return trimmed.unicodeScalars.contains { scalar in
                // Hiragana
                (0x3040...0x309F).contains(scalar.value)
                    // Katakana (full + halfwidth)
                    || (0x30A0...0x30FF).contains(scalar.value)
                    || (0xFF66...0xFF9D).contains(scalar.value)
                    // CJK Unified Ideographs + common extensions
                    || (0x4E00...0x9FFF).contains(scalar.value)
                    || (0x3400...0x4DBF).contains(scalar.value)
                    || (0xF900...0xFAFF).contains(scalar.value)
                    || (0x20000...0x2A6DF).contains(scalar.value)
            }
        }

        if chunks.isEmpty {
            let reading = JapaneseAnalysisService.shared.localReading(for: sentence)
            return [Chunk(
                id: UUID(),
                surface: sentence,
                reading: JapaneseMatching.normalize(reading),
                segmentIndices: Array(segments.indices)
            )]
        }
        return chunks
    }
}
