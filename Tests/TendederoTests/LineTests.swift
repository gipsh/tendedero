import AppKit
import XCTest
@testable import Tendedero

final class LineTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let name = "tendedero-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    /// A real, tiny PNG: `hang` makes a thumbnail from the file.
    private func makePhoto(_ name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tendedero-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let url = dir.appendingPathComponent(name)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
        return url
    }

    /// The live items in rope order, as "photo:name" or "note:text".
    @MainActor
    private func summary(_ line: Line) -> [String] {
        line.items.filter { !$0.falling }.map {
            $0.isNote ? "note:\($0.noteText)" : "photo:\($0.url!.lastPathComponent)"
        }
    }

    @MainActor
    func testRestoresPhotosInOrder() throws {
        let defaults = makeDefaults()
        let a = try makePhoto("a.png"), b = try makePhoto("b.png")
        let first = Line(defaults: defaults)
        first.hang(a, quietly: true)
        first.hang(b, quietly: true)

        XCTAssertEqual(summary(Line(defaults: defaults)), ["photo:a.png", "photo:b.png"])
    }

    @MainActor
    func testMigratesLegacyPaths() throws {
        let defaults = makeDefaults()
        let a = try makePhoto("a.png"), b = try makePhoto("b.png")
        defaults.set([a.path, b.path], forKey: LineStore.legacyKey)

        let line = Line(defaults: defaults)

        XCTAssertEqual(summary(line), ["photo:a.png", "photo:b.png"])
        XCTAssertNotNil(defaults.data(forKey: LineStore.key), "the line is saved in the new format right away")
    }

    @MainActor
    func testSkipsPhotosWhoseFileIsGone() throws {
        let defaults = makeDefaults()
        let a = try makePhoto("a.png")
        defaults.set(["/nonexistent/gone.png", a.path], forKey: LineStore.legacyKey)

        XCTAssertEqual(summary(Line(defaults: defaults)), ["photo:a.png"])
    }

    @MainActor
    func testAFullLineLetsTheOldestPhotoFall() throws {
        let line = Line(defaults: makeDefaults())
        line.maxItems = 2
        let a = try makePhoto("a.png"), b = try makePhoto("b.png"), c = try makePhoto("c.png")
        line.hang(a, quietly: true)
        line.hang(b, quietly: true)
        line.hang(c, quietly: true)

        XCTAssertEqual(summary(line), ["photo:b.png", "photo:c.png"])
        XCTAssertEqual(line.items.first { $0.url == a }?.falling, true)
    }

    // MARK: Notes

    @MainActor
    func testRestoresPhotosAndNotesInOrder() throws {
        let defaults = makeDefaults()
        let a = try makePhoto("a.png"), b = try makePhoto("b.png")
        let first = Line(defaults: defaults)
        first.hang(a, quietly: true)
        let n = try XCTUnwrap(first.addNote(quietly: true))
        first.setNoteText(n, "buy milk")
        first.endEditing()
        first.hang(b, quietly: true)

        XCTAssertEqual(summary(Line(defaults: defaults)), ["photo:a.png", "note:buy milk", "photo:b.png"])
    }

    @MainActor
    func testRestoreKeepsEveryNoteEvenOverCapacity() {
        let defaults = makeDefaults()
        LineStore(defaults: defaults).save((0..<10).map { StoredEntry.note(text: "n\($0)", color: .pink) })

        let line = Line(defaults: defaults)

        XCTAssertEqual(line.liveCount, 10)
    }

    @MainActor
    func testAFullLineDropsPhotosAndNeverNotes() throws {
        let line = Line(defaults: makeDefaults())
        line.maxItems = 3
        line.hang(try makePhoto("p1.png"), quietly: true)
        line.hang(try makePhoto("p2.png"), quietly: true)
        line.addNote(text: "todo", quietly: true)
        line.hang(try makePhoto("p3.png"), quietly: true)

        XCTAssertEqual(summary(line), ["photo:p2.png", "note:todo", "photo:p3.png"])
    }

    @MainActor
    func testALineFullOfNotesRefusesMoreNotesAndPhotos() throws {
        let line = Line(defaults: makeDefaults())
        line.maxItems = 2
        line.addNote(text: "a", quietly: true)
        line.addNote(text: "b", quietly: true)

        XCTAssertNil(line.addNote(text: "c", quietly: true))
        XCTAssertNil(line.hang(try makePhoto("p.png"), quietly: true))
        XCTAssertEqual(summary(line), ["note:a", "note:b"])
    }

    @MainActor
    func testAnEmptyNoteTakesItselfDownOnCommit() throws {
        let defaults = makeDefaults()
        let line = Line(defaults: defaults)
        let n = try XCTUnwrap(line.addNote(quietly: true))
        XCTAssertEqual(line.editingID, n)

        line.endEditing()

        XCTAssertNil(line.editingID)
        XCTAssertEqual(line.liveCount, 0)
        XCTAssertEqual(Line(defaults: defaults).liveCount, 0, "it is not saved either")
    }

    @MainActor
    func testWhitespaceOnlyNoteIsRemovedButSpacesAreKept() throws {
        let line = Line(defaults: makeDefaults())
        let blank = try XCTUnwrap(line.addNote(quietly: true))
        line.setNoteText(blank, "  \n ")
        line.endEditing()
        XCTAssertEqual(line.liveCount, 0)

        let kept = try XCTUnwrap(line.addNote(quietly: true))
        line.setNoteText(kept, "  hi ")
        line.endEditing()
        XCTAssertEqual(summary(line), ["note:  hi "])
    }

    @MainActor
    func testNoteTextLimitCountsCharacters() throws {
        let line = Line(defaults: makeDefaults())
        let n = try XCTUnwrap(line.addNote(quietly: true))

        line.setNoteText(n, String(repeating: "👩‍👩‍👧‍👦", count: 130))

        XCTAssertEqual(line.items.first { $0.id == n }?.noteText.count, Note.maxLength)
    }

    @MainActor
    func testAddingANoteCommitsTheOneBeingEdited() throws {
        let line = Line(defaults: makeDefaults())
        let a = try XCTUnwrap(line.addNote(text: "a", quietly: true))
        let b = try XCTUnwrap(line.addNote(text: "b", quietly: true))

        XCTAssertEqual(line.editingID, b)
        XCTAssertEqual(summary(line), ["note:a", "note:b"])

        line.beginEditing(a)
        XCTAssertEqual(line.editingID, a)
    }

    @MainActor
    func testOnlyNotesCanBeEdited() throws {
        let line = Line(defaults: makeDefaults())
        let p = try XCTUnwrap(line.hang(try makePhoto("p.png"), quietly: true))

        line.beginEditing(p)

        XCTAssertNil(line.editingID)
    }

    @MainActor
    func testDroppingTheEditedNoteEndsEditing() throws {
        let line = Line(defaults: makeDefaults())
        let n = try XCTUnwrap(line.addNote(text: "x", quietly: true))

        line.drop(n, quietly: true)

        XCTAssertNil(line.editingID)
        XCTAssertEqual(line.liveCount, 0)
    }

    @MainActor
    func testPruneLeavesNotesAlone() throws {
        let line = Line(defaults: makeDefaults())
        line.addNote(text: "x", quietly: true)

        line.prune()

        XCTAssertEqual(line.liveCount, 1)
    }

    @MainActor
    func testClearTakesNotesDownToo() throws {
        UserDefaults.standard.set(true, forKey: "soundOff")
        addTeardownBlock { UserDefaults.standard.removeObject(forKey: "soundOff") }
        let line = Line(defaults: makeDefaults())
        line.hang(try makePhoto("p.png"), quietly: true)
        line.addNote(text: "todo", quietly: true)
        line.endEditing()

        line.clear()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))

        XCTAssertEqual(line.liveCount, 0)
    }
}
