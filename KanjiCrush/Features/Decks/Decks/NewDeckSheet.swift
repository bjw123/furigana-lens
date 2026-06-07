import SwiftUI
import SwiftData

struct NewDeckSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var name = ""
    @State private var tag = "Game"

    var body: some View {
        NavigationStack {
            ZStack {
                WashiBackground()
                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "New deck")
                        textField(placeholder: "Deck name", text: $name)
                        textField(placeholder: "Tag (Game, Anime, …)", text: $tag)
                    }
                    .washiCard()
                    .padding(.horizontal)
                    Spacer()
                }
                .padding(.vertical, 12)
            }
            .navigationTitle("New deck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let deck = Deck(name: name.trimmingCharacters(in: .whitespaces), mediaTag: tag)
                        modelContext.insert(deck)
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func textField(placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(.system(.body, design: .rounded))
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Palette.cream, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 0.75)
            )
    }
}
