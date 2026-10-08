import AppKit
import XCTest
@testable import Tendedero

final class NoteUITests: XCTestCase {
    @MainActor
    func testCommandAInsideANoteSelectsAllText() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let view = NoteNSTextView(frame: window.contentView!.bounds)
        window.contentView!.addSubview(view)
        window.makeFirstResponder(view)
        view.string = "buy milk"
        // The app has no main menu, so the editing shortcuts must work without one.
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "a",
            charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0))

        XCTAssertTrue(view.performKeyEquivalent(with: event))
        XCTAssertEqual(view.selectedRange(), NSRange(location: 0, length: 8))
    }

    func testCardsStayOnScreenWhenThereAreMoreThanFit() {
        let width: CGFloat = 1470
        let xs = (0..<10).map { Layout.x(index: $0, count: 10, width: width) }
        XCTAssertGreaterThanOrEqual(xs.first!, 125, "keeps the leftmost card and its cross on screen")
        XCTAssertLessThanOrEqual(xs.last!, width - 125, "keeps clear of the + button")
    }

    func testTheLayoutIsUnchangedWhenEverythingFits() {
        let width: CGFloat = 1470
        let gap = Layout.x(index: 1, count: 5, width: width) - Layout.x(index: 0, count: 5, width: width)
        XCTAssertEqual(gap, Layout.spacing)
    }
}
