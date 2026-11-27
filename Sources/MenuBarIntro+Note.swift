import SwiftUI

/// What the popover under the menu bar icon shows: a heading, then the note.
struct MenuBarIntroNote: View {
    let title: String
    let note: MenuBarIntro.Note

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            switch note {
            case let .shortcut(spec):
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        if let key = spec.doubleTapKey {
                            Text("Tap")
                            Keycap(symbol: key.glyph, label: key.label)
                            Text("twice")
                        } else {
                            Text("Press")
                            Keycap(symbol: nil, label: spec.glyphs)
                        }
                    }
                    Text("to see your recent screenshots.")
                }
                .foregroundStyle(.secondary)
            case let .text(text):
                Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            case let .list(lead, items):
                VStack(alignment: .leading, spacing: 3) {
                    Text(lead)
                    ForEach(items, id: \.self) { item in
                        Text("• \(item)").fixedSize(horizontal: false, vertical: true)
                    }
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 250, alignment: .leading)
    }
}

/// A key as it looks on the keyboard, inline in a sentence: its symbol beside its name.
private struct Keycap: View {
    let symbol: String?
    let label: String

    var body: some View {
        HStack(spacing: 3) {
            if let symbol { Text(symbol) }
            Text(label)
        }
        .font(.callout.weight(.medium))
        .foregroundStyle(.primary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.22), lineWidth: 0.5))
        // The key's lower edge, as on a keycap.
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.18)).offset(y: 1))
    }
}
