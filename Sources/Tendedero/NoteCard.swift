import AppKit
import SwiftUI

enum NoteStyle {
    static let ink = NSColor(white: 0.15, alpha: 1)

    static var nsFont: NSFont {
        let base = NSFont.systemFont(ofSize: 13, weight: .medium)
        return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 13) } ?? base
    }

    static let font = Font.system(size: 13, weight: .medium, design: .rounded)
}

extension NoteColor {
    var paper: Color {
        switch self {
        case .yellow: return Color(red: 1.00, green: 0.93, blue: 0.55)
        case .pink: return Color(red: 1.00, green: 0.80, blue: 0.85)
        case .green: return Color(red: 0.80, green: 0.93, blue: 0.72)
        case .blue: return Color(red: 0.75, green: 0.88, blue: 0.98)
        }
    }
}

/// A sticky note: a square of coloured paper with the task written on it.
/// The shadow, tilt and sway belong to the card that hangs it.
struct NoteCard: View {
    let text: String
    let color: NoteColor
    var editing = false
    var onText: (String) -> Void = { _ in }
    var onCommit: () -> Void = {}

    private let margins = EdgeInsets(top: 22, leading: 12, bottom: 10, trailing: 12)

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4, style: .continuous).fill(color.paper)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
            if editing {
                NoteTextView(text: text, onText: onText, onCommit: onCommit)
                    .padding(margins)
            } else {
                Text(text)
                    .font(NoteStyle.font)
                    .foregroundStyle(Color(nsColor: NoteStyle.ink))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(margins)
            }
            if text.isEmpty {
                Text(L("Write a task"))
                    .font(NoteStyle.font)
                    .foregroundStyle(Color.black.opacity(0.35))
                    .padding(margins)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: Layout.noteSize, height: Layout.noteSize)
    }
}
