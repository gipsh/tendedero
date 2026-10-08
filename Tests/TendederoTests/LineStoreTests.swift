import XCTest
@testable import Tendedero

final class LineStoreTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let name = "tendedero-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    func testRoundTripKeepsOrderAndKinds() {
        let store = LineStore(defaults: makeDefaults())
        let entries: [StoredEntry] = [
            .photo(path: "/tmp/a.png"),
            .note(text: "buy milk", color: .pink),
            .photo(path: "/tmp/b.png"),
        ]
        store.save(entries)
        XCTAssertEqual(store.load(), entries)
    }

    func testJSONShapeMatchesTheSpec() throws {
        let defaults = makeDefaults()
        LineStore(defaults: defaults).save([.note(text: "x", color: .blue), .photo(path: "/p.png")])
        let json = try XCTUnwrap(String(data: try XCTUnwrap(defaults.data(forKey: LineStore.key)), encoding: .utf8))
        XCTAssertTrue(json.contains("\"type\":\"note\""))
        XCTAssertTrue(json.contains("\"type\":\"photo\""))
    }

    func testLegacyPathsAreMigratedWhenTheNewKeyIsAbsent() {
        let defaults = makeDefaults()
        defaults.set(["/tmp/a.png", "/tmp/b.png"], forKey: LineStore.legacyKey)
        XCTAssertEqual(LineStore(defaults: defaults).load(),
                       [.photo(path: "/tmp/a.png"), .photo(path: "/tmp/b.png")])
    }

    func testNewKeyWinsOverLegacy() {
        let defaults = makeDefaults()
        defaults.set(["/tmp/old.png"], forKey: LineStore.legacyKey)
        let store = LineStore(defaults: defaults)
        store.save([.note(text: "n", color: .green)])
        XCTAssertEqual(store.load(), [.note(text: "n", color: .green)])
    }

    func testAnEmptySavedLineIsNotTreatedAsMissing() {
        let defaults = makeDefaults()
        defaults.set(["/tmp/old.png"], forKey: LineStore.legacyKey)
        let store = LineStore(defaults: defaults)
        store.save([])
        XCTAssertEqual(store.load(), [])
    }

    func testCorruptDataLoadsEmpty() {
        let defaults = makeDefaults()
        defaults.set(Data([1, 2, 3]), forKey: LineStore.key)
        XCTAssertEqual(LineStore(defaults: defaults).load(), [])
    }

    func testAnUnknownColorFallsBackToYellow() throws {
        let defaults = makeDefaults()
        let json = #"[{"type":"note","text":"hi","color":"purple"}]"#
        defaults.set(Data(json.utf8), forKey: LineStore.key)
        XCTAssertEqual(LineStore(defaults: defaults).load(), [.note(text: "hi", color: .yellow)])
    }
}
