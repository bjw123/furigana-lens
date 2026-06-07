import SwiftUI
import SwiftData

struct CardEditView: View {
    @Bindable var card: Flashcard

    var body: some View {
        ZStack {
            WashiBackground()
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Expression")
                        VStack(spacing: 0) {
                            row(label: "Word", text: $card.expression)
                            Divider().padding(.leading, 16).overlay(Palette.hairline)
                            row(label: "Reading", text: $card.reading)
                                .onChange(of: card.reading) { _, newValue in
                                    ReadingOverrideStore.shared.setReading(newValue, for: card.expression)
                                }
                        }
                        .background(Palette.washi, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Palette.hairline, lineWidth: 0.75)
                        )
                    }
                    .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Meaning")
                        TextField("Meaning", text: Binding(
                            get: { card.meaning ?? "" },
                            set: { card.meaning = $0.isEmpty ? nil : $0 }
                        ), axis: .vertical)
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(Palette.sumi)
                            .padding(12)
                            .background(Palette.washi, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Palette.hairline, lineWidth: 0.75)
                            )
                    }
                    .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Hint")
                        TextField("Hint", text: Binding(
                            get: { card.hint ?? "" },
                            set: { card.hint = $0.isEmpty ? nil : $0 }
                        ), axis: .vertical)
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(Palette.sumi)
                            .padding(12)
                            .background(Palette.washi, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Palette.hairline, lineWidth: 0.75)
                            )
                    }
                    .padding(.horizontal)

                    if let sentence = card.contextSentence {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Context")
                            Text(sentence)
                                .font(.system(.callout, design: .serif))
                                .foregroundStyle(Palette.sumi.opacity(0.85))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .washiCard()
                        .padding(.horizontal)
                    }

                    TagEditor(tags: $card.tags)
                        .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Review")
                        VStack(spacing: 10) {
                            HStack {
                                Text("Type")
                                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                                    .foregroundStyle(Palette.mist)
                                Spacer()
                                Picker("Type", selection: $card.cardType) {
                                    ForEach(CardType.allCases) { type in
                                        Text(type.label).tag(type)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(Palette.indigo)
                            }
                            HStack {
                                Text("Due")
                                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                                    .foregroundStyle(Palette.mist)
                                Spacer()
                                Text(card.dueDate.formatted(date: .abbreviated, time: .omitted))
                                    .font(.system(.subheadline, design: .rounded))
                                    .foregroundStyle(Palette.sumi)
                            }
                            HStack {
                                Text("Interval")
                                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                                    .foregroundStyle(Palette.mist)
                                Spacer()
                                Text("\(Int(card.interval))d")
                                    .font(.system(.subheadline, design: .rounded))
                                    .foregroundStyle(Palette.sumi)
                            }
                        }
                        .padding(14)
                        .background(Palette.washi, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Palette.hairline, lineWidth: 0.75)
                        )
                    }
                    .padding(.horizontal)

                    Spacer(minLength: 24)
                }
                .padding(.vertical, 12)
            }
        }
        .navigationTitle("Edit card")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundStyle(Palette.mist)
                .frame(width: 80, alignment: .leading)
            TextField(label, text: text)
                .multilineTextAlignment(.trailing)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Palette.sumi)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
