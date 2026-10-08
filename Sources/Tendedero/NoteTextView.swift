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

    /// The app is an accessory with no main menu, and NSTextView only gets
    /// its editing shortcuts from the Edit menu: handle them here.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard event.type == .keyDown, flags.contains(.command),
              flags.subtracting([.command, .shift]).isEmpty,
              let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        switch (key, flags.contains(.shift)) {
        case ("a", false): selectAll(nil)
        case ("c", false): copy(nil)
        case ("x", false): cut(nil)
        case ("v", false): paste(nil)
        case ("z", false): undoManager?.undo()
        case ("z", true): undoManager?.redo()
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

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
