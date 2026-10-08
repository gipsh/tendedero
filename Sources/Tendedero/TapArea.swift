import AppKit
import SwiftUI

/// A transparent click target. The line never activates, so every click on
/// it is a first click: SwiftUI buttons would ignore it, this view does not.
/// It also handles the corner cross and the right click menu, the way
/// GrabArea does for photos.
struct TapArea: NSViewRepresentable {
    var onTap: () -> Void
    var onCross: (() -> Void)? = nil
    var menuProvider: (() -> NSMenu)? = nil

    func makeNSView(context: Context) -> TapView {
        let view = TapView()
        configure(view)
        return view
    }

    func updateNSView(_ view: TapView, context: Context) {
        configure(view)
    }

    private func configure(_ view: TapView) {
        view.onTap = onTap
        view.onCross = onCross
        view.menuProvider = menuProvider
    }
}

final class TapView: NSView {
    var onTap: () -> Void = {}
    var onCross: (() -> Void)?
    var menuProvider: (() -> NSMenu)?
    private var pressed = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func isInCross(_ event: NSEvent) -> Bool {
        guard onCross != nil else { return false }
        let p = convert(event.locationInWindow, from: nil)
        let size = GrabView.crossHitSize
        let corner = NSRect(x: 0, y: isFlipped ? 0 : bounds.height - size, width: size, height: size)
        return corner.contains(p)
    }

    override func mouseDown(with event: NSEvent) {
        if isInCross(event) {
            pressed = false
            onCross?()
            return
        }
        pressed = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { pressed = false }
        guard pressed, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onTap()
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = menuProvider?() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}
