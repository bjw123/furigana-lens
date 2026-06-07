import SwiftUI

// MARK: - Word chips

struct WordChipFlow: View {
    let tokens: [JapaneseToken]
    /// Predicate so JLPT-implied known words are flagged without prebuilding
    /// a giant Set in the caller.
    var knownPredicate: (String) -> Bool = { _ in false }
    var inDeckExpressions: Set<String> = []
    var strugglingKanji: Set<Character> = []
    /// Single tap: toggle inline reading. Second arg = new revealed state.
    var onTap: ((JapaneseToken, Bool) -> Void)? = nil
    /// Double tap: open the full word detail sheet.
    let onLongPress: (JapaneseToken) -> Void

    @State private var revealedTokenIds: Set<UUID> = []

    fileprivate enum ChipState {
        case fresh
        case inDeck
        case known
        /// In a deck *and* considered known (explicit mark or JLPT-implied).
        /// Surfaces as a yellow chip — "you have a card for a word you
        /// should already know".
        case strugglingKnown

        var tint: Color {
            switch self {
            case .fresh: return Palette.mist
            case .inDeck: return Palette.indigo
            case .known: return Palette.bamboo
            case .strugglingKnown: return Palette.gold
            }
        }

        var icon: String? {
            switch self {
            case .fresh: return nil
            case .inDeck: return "bookmark.fill"
            case .known: return "checkmark.seal.fill"
            case .strugglingKnown: return "exclamationmark.triangle.fill"
            }
        }

        var emphasized: Bool {
            switch self {
            case .fresh: return false
            case .inDeck, .known, .strugglingKnown: return true
            }
        }
    }

    private func state(for token: JapaneseToken) -> ChipState {
        let known = knownPredicate(token.surface)
        let inDeck = inDeckExpressions.contains(token.surface)
        if known && inDeck { return .strugglingKnown }
        if known { return .known }
        if inDeck { return .inDeck }
        return .fresh
    }

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(tokens) { token in
                WordChip(
                    token: token,
                    chip: state(for: token),
                    revealed: revealedTokenIds.contains(token.id),
                    isStruggling: token.surface.contains(where: { strugglingKanji.contains($0) }),
                    onSingleTap: { toggle(token) },
                    onDoubleTap: { onLongPress(token) }
                )
            }
        }
    }

    private func toggle(_ token: JapaneseToken) {
        let nowRevealed: Bool
        if revealedTokenIds.contains(token.id) {
            revealedTokenIds.remove(token.id)
            nowRevealed = false
        } else {
            revealedTokenIds.insert(token.id)
            nowRevealed = true
        }
        onTap?(token, nowRevealed)
    }
}

private struct WordChip: View {
    let token: JapaneseToken
    let chip: WordChipFlow.ChipState
    let revealed: Bool
    var isStruggling: Bool = false
    let onSingleTap: () -> Void
    let onDoubleTap: () -> Void

    var body: some View {
        let showReading = revealed && token.hasKanji
            && !token.reading.isEmpty && token.reading != token.surface

        VStack(spacing: 1) {
            if showReading {
                Text(token.reading)
                    .font(.system(.caption2, design: .rounded).weight(.medium))
                    .foregroundStyle(Palette.indigo.opacity(0.85))
            }
            HStack(spacing: 5) {
                Text(token.surface)
                    .font(.system(.title3, design: .serif))
                    .foregroundStyle(isStruggling ? Palette.vermillion : Palette.sumi)
                if let icon = chip.icon {
                    Image(systemName: icon)
                        .font(.caption2)
                        .foregroundStyle(chip.tint)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            Capsule(style: .continuous)
                .fill(chip.tint.opacity(chip.emphasized ? 0.18 : 0.10))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(chip.tint.opacity(chip.emphasized ? 0.55 : 0.30), lineWidth: 0.75)
        )
        .contentShape(Capsule())
        .onTapGesture(count: 2) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onDoubleTap()
        }
        .onTapGesture(count: 1) {
            onSingleTap()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint("Double-tap for word details")
        .accessibilityAddTraits(.isButton)
    }

    /// Composite label for VoiceOver — reads the word, its reading when
    /// revealed, and its known / in-deck status so the listener gets the
    /// same information sighted users do at a glance.
    private var accessibilityDescription: String {
        var parts: [String] = [token.surface]
        if !token.reading.isEmpty, token.reading != token.surface {
            parts.append("reading \(token.reading)")
        }
        switch chip {
        case .fresh: break
        case .inDeck: parts.append("in your deck")
        case .known: parts.append("marked as known")
        case .strugglingKnown: parts.append("known word, but in your deck")
        }
        return parts.joined(separator: ", ")
    }
}

/// Simple wrapping layout for word chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}
