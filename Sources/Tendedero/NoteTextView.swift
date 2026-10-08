import AppKit
import SwiftUI

/// The text of a note while it is being written. A plain NSTextView because
/// the keys need exact control: Return commits, Shift-Return starts a new
/// line and Esc commits too.
struct NoteTextView: NSViewRepresentable {
    let text: String
    let onText: (String) -> Void
    let onCommit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NoteNSTextView {
        let view = NoteNSTextView()
        view.delegate = context.coordinator
        view.drawsBackground = false
        view.isRichText = false
        view.allowsUndo = true
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.font = NoteStyle.nsFont
        view.textColor = NoteStyle.ink
        view.insertionPointColor = NoteStyle.ink
        view.string = text
        context.coordinator.update(onText: onText, onCommit: onCommit)
        return view
    }

    func updateNSView(_ view: NoteNSTextView, context: Context) {
        context.coordinator.update(onText: onText, onCommit: onCommit)
        if view.string != text { view.string = text }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private var onText: (String) -> Void = { _ in }
        private var onCommit: () -> Void = {}

        func update(onText: @escaping (String) -> Void, onCommit: @escaping () -> Void) {
            self.onText = onText
            self.onCommit = onCommit
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            if view.string.count > Note.maxLength {
                view.string = String(view.string.prefix(Note.maxLength))
            }
            onText(view.string)
        }

        func textView(_ view: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                if NSEvent.modifierFlags.contains(.shift) {
                    view.insertText("\n", replacementRange: view.selectedRange())
                } else {
                    onCommit()
                }
                return true
            case #selector(NSResponder.insertLineBreak(_:)):
                view.insertText("\n", replacementRange: view.selectedRange())
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                onCommit()
                return true
            default:
                return false
            }
        }
    }
}

final class NoteNSTextView: NSTextView {
    override var acceptsFirstResponder: Bool { true }

    /// Takes the keyboard as soon as it is on screen, so you can type at once.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self)
        }
    }
}
