import SwiftUI

/// Editable chip-list of tags. Tap × on a chip to remove; tap "+ Add tag" to
/// open an alert with a text field. Lowercase + trim on insert so tags dedupe.
struct TagEditor: View {
    @Binding var tags: [String]
    @State private var showingAdd = false
    @State private var pending = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Tags", trailing: tags.isEmpty ? nil : "\(tags.count)")
            FlowLayout(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    tagChip(tag)
                }
                Button {
                    pending = ""
                    showingAdd = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.caption2.weight(.semibold))
                        Text("Add tag")
                            .font(.system(.caption, design: .rounded).weight(.medium))
                    }
                    .foregroundStyle(Palette.indigo)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Palette.indigo.opacity(0.10)))
                    .overlay(Capsule().strokeBorder(Palette.indigo.opacity(0.4), lineWidth: 0.75))
                }
                .buttonStyle(.plain)
            }
            if tags.isEmpty {
                Text("Tag this card for quick search (e.g. verbs, particles, JLPT-tricky).")
                    .font(.caption)
                    .foregroundStyle(Palette.mist)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .washiCard()
        .alert("New tag", isPresented: $showingAdd) {
            TextField("Tag name", text: $pending)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button("Add") { addPending() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Examples: verbs, particles, manga, JLPT-tricky")
        }
    }

    private func tagChip(_ tag: String) -> some View {
        HStack(spacing: 4) {
            Text(tag)
                .font(.system(.caption, design: .rounded).weight(.medium))
            Button {
                tags.removeAll { $0 == tag }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove tag \(tag)")
        }
        .foregroundStyle(Palette.sakura)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Palette.sakura.opacity(0.14)))
        .overlay(Capsule().strokeBorder(Palette.sakura.opacity(0.4), lineWidth: 0.5))
    }

    private func addPending() {
        let normalized = pending
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty, !tags.contains(normalized) else { return }
        tags.append(normalized)
    }
}
