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
}
