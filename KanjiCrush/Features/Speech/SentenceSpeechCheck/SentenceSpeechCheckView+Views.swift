import SwiftUI

extension SentenceSpeechCheckView {

    // MARK: - Prompt with active-chunk highlight

    @ViewBuilder
    var promptView: some View {
        VStack(spacing: 8) {
            highlightedSentence
                .frame(maxWidth: .infinity)
                .padding(.horizontal)
            if !sessionComplete && !isEditing, let chunk = activeChunk {
                VStack(spacing: 2) {
                    Text("Read this part")
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(Palette.mist)
                        .textCase(.uppercase)
                        .tracking(0.6)
                    Text(chunk.surface)
                        .font(.system(.title2, design: .serif))
                        .foregroundStyle(Palette.sumi)
                    if !chunk.reading.isEmpty && chunk.reading != chunk.surface && showFuriganaState {
                        Text(chunk.reading)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Palette.indigo.opacity(0.85))
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity)
                .background(Palette.sakura.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Palette.sakura.opacity(0.45), lineWidth: 0.75)
                )
                .padding(.horizontal)
            }
        }
    }

    /// Sentence rendered as a wrapping flow of chunk-sized capsules. The
    /// active chunk is highlighted, completed chunks are dimmed with a
    /// pass/fail tint, and pending chunks are faded.
    var highlightedSentence: some View {
        FlowLayout(spacing: 4) {
            ForEach(Array(chunks.enumerated()), id: \.element.id) { idx, chunk in
                chunkPill(chunk: chunk, index: idx)
            }
        }
    }

    @ViewBuilder
    func chunkPill(chunk: Chunk, index: Int) -> some View {
        let state = chunkPillState(for: index)
        let outOfScope = isOutOfScope(index)
        VStack(spacing: 0) {
            if showFuriganaState && chunk.hasKanji && !chunk.reading.isEmpty && chunk.reading != chunk.surface {
                Text(chunk.reading)
                    .font(.system(size: 10, design: .rounded).weight(.medium))
                    .foregroundStyle(outOfScope ? Palette.mist.opacity(0.4) : state.readingColor)
            }
            Text(chunk.surface)
                .font(.system(.title3, design: .serif))
                .foregroundStyle(outOfScope ? Palette.sumi.opacity(0.25) : state.surfaceColor)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(outOfScope ? Color.clear : state.background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(outOfScope ? Color.clear : state.border, lineWidth: state.borderWidth)
        )
        .opacity(outOfScope ? 0.4 : state.opacity)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture {
            handleChunkTap(index: index)
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Read up to \(chunk.surface)")
    }

    /// Index past which chunks are styled as out-of-scope (greyed out, no
    /// pill). When `targetIndex` is nil the user is reading the whole
    /// sentence — nothing is out of scope.
    func isOutOfScope(_ index: Int) -> Bool {
        guard let target = targetIndex else { return false }
        return index > target
    }

    /// Tap on a chunk → set it as the new endpoint. Tapping the SAME chunk
    /// twice clears the endpoint (back to "read the whole sentence"). Tapping
    /// a chunk EARLIER than the current index is a no-op (you can't un-read
    /// chunks you already finished).
    func handleChunkTap(index: Int) {
        guard index >= currentIndex else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if targetIndex == index {
            targetIndex = nil
        } else {
            targetIndex = index
        }
    }

    fileprivate struct ChunkPillState {
        let background: Color
        let border: Color
        let borderWidth: CGFloat
        let surfaceColor: Color
        let readingColor: Color
        let opacity: Double
    }

    fileprivate func chunkPillState(for index: Int) -> ChunkPillState {
        // Look up any prior result for this chunk id.
        let result = chunkResult(at: index)
        if let result {
            if result.matched {
                return ChunkPillState(
                    background: Palette.bamboo.opacity(0.15),
                    border: Palette.bamboo.opacity(0.45),
                    borderWidth: 0.75,
                    surfaceColor: Palette.bamboo,
                    readingColor: Palette.bamboo.opacity(0.85),
                    opacity: 0.95
                )
            } else if result.skipped {
                // Softer treatment than vermillion — skipping isn't failing.
                return ChunkPillState(
                    background: Palette.mist.opacity(0.15),
                    border: Palette.mist.opacity(0.40),
                    borderWidth: 0.75,
                    surfaceColor: Palette.sumi.opacity(0.55),
                    readingColor: Palette.mist,
                    opacity: 0.85
                )
            } else {
                return ChunkPillState(
                    background: Palette.vermillion.opacity(0.18),
                    border: Palette.vermillion.opacity(0.55),
                    borderWidth: 0.75,
                    surfaceColor: Palette.vermillion,
                    readingColor: Palette.vermillion.opacity(0.85),
                    opacity: 0.95
                )
            }
        }
        if index == currentIndex && !sessionComplete && !isEditing {
            return ChunkPillState(
                background: Palette.sakura.opacity(0.22),
                border: Palette.sakura.opacity(0.65),
                borderWidth: 1.0,
                surfaceColor: Palette.sumi,
                readingColor: Palette.indigo.opacity(0.85),
                opacity: 1.0
            )
        }
        // Post-session pending chunks (never heard, never explicitly wrong)
        // get a softly tinted gold to call them out without the harsh
        // vermillion of a real failure.
        if sessionComplete {
            return ChunkPillState(
                background: Palette.gold.opacity(0.12),
                border: Palette.gold.opacity(0.45),
                borderWidth: 0.75,
                surfaceColor: Palette.sumi.opacity(0.7),
                readingColor: Palette.indigo.opacity(0.7),
                opacity: 0.9
            )
        }
        return ChunkPillState(
            background: .clear,
            border: .clear,
            borderWidth: 0,
            surfaceColor: Palette.sumi.opacity(0.55),
            readingColor: Palette.indigo.opacity(0.55),
            opacity: 0.85
        )
    }

    // MARK: - Controls row

    var controlsRow: some View {
        HStack {
            Toggle("Show furigana", isOn: $showFuriganaState)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Palette.mist)
                .tint(Palette.indigo)
                .fixedSize()
            Spacer()
            if !sessionComplete && !isEditing {
                Text("\(min(currentIndex + 1, max(chunks.count, 1))) / \(max(chunks.count, 1))")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(Palette.mist)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Palette.washi))
                    .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 0.5))
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Active chunk runner

    @ViewBuilder
    var chunkRunner: some View {
        if activeChunk != nil {
            VStack(spacing: 14) {
                micRow
                transcriptField
                Text(speech.isListening
                     ? "Read the sentence at your own pace — each part lights up green as it's heard."
                     : "Tap the mic and read the sentence aloud. The session ends when every part matches.")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Palette.mist)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                chunkFeedbackView
                manualOverrideRow
                    .padding(.horizontal)
                finishEarlyButton
                    .padding(.horizontal)
            }
        } else {
            // No chunks to read — e.g. user removed them all in edit mode.
            VStack(spacing: 10) {
                Text("Nothing to read")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Palette.sumi)
                Text("Tap Edit to add some words back.")
                    .font(.caption)
                    .foregroundStyle(Palette.mist)
            }
            .padding()
        }
    }

    var micRow: some View {
        HStack(spacing: 10) {
            Button {
                Task { await toggleListening() }
            } label: {
                Image(systemName: speech.isListening ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(speech.isListening ? Palette.vermillion : Palette.indigo)
            }
            .disabled(!speech.isAvailable && !speech.isListening)
            if speech.isListening {
                Text("Listening…")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(Palette.vermillion)
            }
        }
    }

    @ViewBuilder
    var transcriptField: some View {
        // While the recogniser is live the transcript is a read-only mirror so
        // a stray keystroke can't desync the live transcript-watching logic.
        // When the mic is off, the user can still hand-edit if they want to
        // visually inspect what was captured.
        if speech.isListening {
            Text(input.isEmpty ? "Listening…" : input)
                .font(.system(.title3, design: .rounded))
                .foregroundStyle(input.isEmpty ? Palette.mist : Palette.sumi)
                .frame(maxWidth: .infinity, minHeight: 28)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Palette.cream, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(strokeColor, lineWidth: 1)
                )
                .padding(.horizontal)
        } else {
            TextField("What you said", text: $input)
                .focused($inputFocused)
                .submitLabel(.done)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(.title3, design: .rounded))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Palette.cream, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(strokeColor, lineWidth: 1)
                )
                .padding(.horizontal)
        }
    }

    var strokeColor: Color {
        switch chunkFeedback {
        case .correct: return Palette.bamboo.opacity(0.85)
        case .wrong: return Palette.vermillion.opacity(0.85)
        case nil: return Palette.hairline
        }
    }

    @ViewBuilder
    var chunkFeedbackView: some View {
        switch chunkFeedback {
        case .correct:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                Text("Nice — moving on")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
            }
            .foregroundStyle(Palette.bamboo)
        case .wrong(let expected, let heard):
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("Not quite")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                }
                .foregroundStyle(Palette.vermillion)
                Text("Expected: \(expected)")
                    .font(.caption)
                    .foregroundStyle(Palette.sumi.opacity(0.85))
                if !heard.isEmpty {
                    Text("Heard: \(heard)")
                        .font(.caption2)
                        .foregroundStyle(Palette.mist)
                }
            }
            .padding(.horizontal)
        case nil:
            EmptyView()
        }
    }

    /// Two-button row offered when the mic is live: "I read this" (validates
    /// the transcript and only advances if the chunk actually appears) and
    /// "Skip" (advances without marking correct — for when the recogniser is
    /// fighting the user on a particular word and they just want to move on).
    @ViewBuilder
    var manualOverrideRow: some View {
        if let chunk = activeChunk {
            HStack(spacing: 8) {
                if speech.isListening {
                    Button {
                        manuallyAdvance(chunk: chunk)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "hand.tap.fill")
                                .font(.caption2)
                            Text("I read \"\(chunk.surface)\"")
                                .font(.system(.caption, design: .rounded).weight(.semibold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Palette.indigo.opacity(0.12)))
                        .foregroundStyle(Palette.indigo)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("I read \(chunk.surface)")
                }

                Button {
                    skipCurrentChunk()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "forward.fill")
                            .font(.caption2)
                        Text("Skip")
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Palette.mist.opacity(0.18)))
                    .foregroundStyle(Palette.mist)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Skip this chunk")
            }
        }
    }

    /// While listening, give the user a way to end the session early without
    /// dropping back to the mic toggle. Pending (un-heard) chunks land in the
    /// summary's save-list alongside any explicit misses.
    @ViewBuilder
    var finishEarlyButton: some View {
        if speech.isListening {
            Button { finishSessionEarly() } label: {
                Text("Finish session").frame(maxWidth: .infinity)
            }
            .buttonStyle(WashiButtonStyle())
        }
    }
}
