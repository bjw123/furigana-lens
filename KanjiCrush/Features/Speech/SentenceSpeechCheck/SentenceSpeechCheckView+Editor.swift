import SwiftUI

extension SentenceSpeechCheckView {

    // MARK: - Edit mode

    var editChunksPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Group, split or remove chunks")
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Palette.mist)
                .textCase(.uppercase)
                .tracking(0.6)
                .padding(.horizontal, 16)

            VStack(spacing: 8) {
                ForEach(Array(chunks.enumerated()), id: \.element.id) { idx, chunk in
                    editRow(chunk: chunk, index: idx)
                }
                if chunks.isEmpty {
                    Text("All chunks removed — tap Reset to restore.")
                        .font(.caption)
                        .foregroundStyle(Palette.mist)
                        .padding(.horizontal, 16)
                }
            }
            .padding(.horizontal, 8)

            HStack {
                Button {
                    chunks = Self.buildChunks(for: sentence)
                    resetSession()
                } label: {
                    Label("Reset chunks", systemImage: "arrow.counterclockwise")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Palette.indigo.opacity(0.12)))
                        .foregroundStyle(Palette.indigo)
                }
                .buttonStyle(.plain)
                Spacer()
                Button {
                    resetSession()
                    isEditing = false
                } label: {
                    Text("Start reading")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Palette.sumi))
                        .foregroundStyle(Palette.cream)
                }
                .buttonStyle(.plain)
                .disabled(chunks.isEmpty)
                .opacity(chunks.isEmpty ? 0.5 : 1.0)
            }
            .padding(.horizontal, 16)
        }
    }

    func editRow(chunk: Chunk, index: Int) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(chunk.surface)
                    .font(.system(.title3, design: .serif))
                    .foregroundStyle(Palette.sumi)
                if !chunk.reading.isEmpty && chunk.reading != chunk.surface {
                    Text(chunk.reading)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Palette.indigo.opacity(0.85))
                }
            }
            Spacer()
            // Merge with next: glues this chunk into the next one so the user
            // reads them as a single unit. Disabled on the last row.
            Button {
                mergeChunk(at: index)
            } label: {
                Image(systemName: "arrow.down.to.line.compact")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Palette.indigo.opacity(0.12)))
                    .foregroundStyle(Palette.indigo)
            }
            .buttonStyle(.plain)
            .disabled(index >= chunks.count - 1)
            .opacity(index >= chunks.count - 1 ? 0.35 : 1.0)
            .accessibilityLabel("Merge with next chunk")

            // Split back: break this chunk into its underlying segments. Only
            // useful if it currently spans more than one segment.
            Button {
                splitChunk(at: index)
            } label: {
                Image(systemName: "scissors")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Palette.gold.opacity(0.15)))
                    .foregroundStyle(Palette.gold)
            }
            .buttonStyle(.plain)
            .disabled(chunk.segmentIndices.count <= 1)
            .opacity(chunk.segmentIndices.count <= 1 ? 0.35 : 1.0)
            .accessibilityLabel("Split chunk")

            Button(role: .destructive) {
                removeChunk(at: index)
            } label: {
                Image(systemName: "trash.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Palette.vermillion.opacity(0.15)))
                    .foregroundStyle(Palette.vermillion)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove chunk")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Palette.washi, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 0.5)
        )
    }

    // MARK: - Edit operations

    func mergeChunk(at index: Int) {
        guard index >= 0, index < chunks.count - 1 else { return }
        let first = chunks[index]
        let second = chunks[index + 1]
        let merged = Chunk(
            id: UUID(),
            surface: first.surface + second.surface,
            reading: JapaneseMatching.normalize(first.reading + second.reading),
            segmentIndices: first.segmentIndices + second.segmentIndices
        )
        chunks.replaceSubrange(index...(index + 1), with: [merged])
        resetSession()
    }

    func splitChunk(at index: Int) {
        guard index >= 0, index < chunks.count else { return }
        let chunk = chunks[index]
        guard chunk.segmentIndices.count > 1 else { return }
        let segments = JapaneseAnalysisService.shared.segments(sentence)
        let replacements: [Chunk] = chunk.segmentIndices.map { segIdx in
            let surface = segIdx < segments.count ? segments[segIdx].surface : ""
            let reading = segIdx < segments.count ? segments[segIdx].reading : ""
            return Chunk(
                id: UUID(),
                surface: surface,
                reading: JapaneseMatching.normalize(reading),
                segmentIndices: [segIdx]
            )
        }.filter { !$0.surface.isEmpty }
        chunks.replaceSubrange(index...index, with: replacements)
        resetSession()
    }

    func removeChunk(at index: Int) {
        guard index >= 0, index < chunks.count else { return }
        chunks.remove(at: index)
        resetSession()
    }
}
