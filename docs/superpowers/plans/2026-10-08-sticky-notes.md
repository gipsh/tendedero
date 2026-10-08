# Sticky Notes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user hang sticky notes with to-do tasks on the same line as screenshots, edit them in place, and take them down (which deletes them) when done.

**Architecture:** `Pegged` becomes a two-variant item (photo or note) and `Line` persists both through a small JSON `LineStore` (migrating the old paths-only key). A note is edited in place with an `NSTextView`; `LinePanel` becomes key only while a note is being edited, so the line keeps its non-activating behaviour the rest of the time. Notes are created from a second global shortcut, a "+" on the line, and a menu bar item.

**Tech Stack:** Swift 5.9 tools (builds with the installed Swift 6.4 toolchain), AppKit + SwiftUI, Carbon hot keys, XCTest, macOS 14+.

**Spec:** `docs/superpowers/specs/2026-10-08-sticky-notes-design.md`

## Global Constraints

- macOS 14 Sonoma or later; `swift-tools-version:5.9`; no new dependencies; no network access.
- New shortcut is ⌃⌥N (`controlKey | optionKey` + `kVK_ANSI_N`); ⌃⌥T keeps working.
- A note is a square paper of 130 pt, pastel colour (yellow, pink, green, blue) chosen at random on creation, text limited to 120 characters, no colour picker.
- Return commits, Shift-Return inserts a newline, Esc commits and keeps the text. A note that is empty on commit takes itself down.
- Notes never fall on their own. The capacity limit (`Line.maxItems`, 3 to 12 by screen width) counts photos and notes together; only photos are evicted, oldest first. A line full of notes refuses new photos and new notes.
- Taking a note down and deleting it are the same gesture (cross, or right click "Take down"). Dragging a note does nothing.
- Persistence: new `UserDefaults` key `"line.v2"` holding a JSON list in rope order of `{"type":"photo","path":…}` / `{"type":"note","text":…,"color":…}`. The old `"pegged"` key is read once if the new key is absent.
- Every user-visible string goes through `L("…")` and must exist in `en`, `es` and `zh-Hans` `Localizable.strings` (`swift scripts/check-strings.swift` must pass). English text is the key.
- Code style: match the surrounding Swift (short `///` doc comments explaining why, no trailing noise).
- Commit messages end with the line `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.

## Review Focus

Failure modes the spec implies that no feature step exercises on its own. Each has a test in the task that owns the code.

1. **Corrupted or unknown saved data** loads as an empty line and never crashes the launch (Task 1, `testCorruptDataLoadsEmpty`).
2. **More saved notes than fit the screen**: all of them come back, none is silently dropped on launch (Task 3, `testRestoreKeepsEveryNoteEvenOverCapacity`).
3. **Text at the length limit with multi-scalar characters** (emoji families): the limit counts characters, so a character is never cut in half (Task 3, `testNoteTextLimitCountsCharacters`).
4. **Whitespace-only note on commit** is removed, while real text with surrounding spaces is stored untouched (Task 3, `testWhitespaceOnlyNoteIsRemovedButSpacesAreKept`).
5. **"Take everything down"** takes notes down too, as the spec says (`clear` works for both kinds), and a note dropped while being edited clears the editing state (Task 3, `testClearTakesNotesDownToo`, `testDroppingTheEditedNoteEndsEditing`). This is the one place a single click deletes every task: flagged to the user at handoff.

---

## File Structure

| File | Responsibility |
|:--|:--|
| `Package.swift` (modify) | Adds the `TendederoTests` test target. |
| `Sources/Tendedero/Note.swift` (create) | `Note.maxLength`, `NoteColor`. No UI. |
| `Sources/Tendedero/LineStore.swift` (create) | `StoredEntry` (Codable) and `LineStore` (load, save, legacy migration). Pure, testable. |
| `Sources/Tendedero/Line.swift` (modify) | `Pegged` gets `kind`; `Line` takes a `UserDefaults`, uses `LineStore`, gains the note API and the capacity rule. |
| `Sources/Tendedero/NoteCard.swift` (create) | `NoteStyle`, `NoteColor.paper`, the `NoteCard` SwiftUI paper. |
| `Sources/Tendedero/NoteTextView.swift` (create) | `NSTextView` wrapper that owns Return / Shift-Return / Esc. |
| `Sources/Tendedero/TapArea.swift` (create) | `NSView` that catches first-mouse clicks, the corner cross and the right click menu. Used by notes and the "+" button. |
| `Sources/Tendedero/PeggedView.swift` (modify) | Renders a note next to a photo, sharing clothespin, swing and fall. |
| `Sources/Tendedero/LineView.swift` (modify) | `Layout.noteSize`, the "+" button. |
| `Sources/Tendedero/LinePanel.swift` (modify) | `allowsKey` flag. |
| `Sources/Tendedero/HotKey.swift` (modify) | Several shortcuts at once. |
| `Sources/Tendedero/AppDelegate.swift` (modify) | New shortcut, editing wiring, click-outside commit, fall image for notes, menu item. |
| `Sources/Tendedero/Resources/*/Localizable.strings` (modify) | Three new strings. |
| `README.md`, `docs/i18n/README.es.md`, `docs/i18n/README.zh-Hans.md` (modify) | Shortcut row and a short notes section. |
| `Tests/TendederoTests/LineStoreTests.swift`, `LineTests.swift` (create) | Logic tests. |

Build and test commands (run from the repository root `/Users/hernangips/workspace/tendedero`): `swift build 2>&1 | tail -20` and `swift test 2>&1 | tail -30`.

---

### Task 1: Test target and `LineStore`

**Files:**
- Modify: `Package.swift`
- Create: `Sources/Tendedero/Note.swift`, `Sources/Tendedero/LineStore.swift`
- Test: `Tests/TendederoTests/LineStoreTests.swift`

**Interfaces:**
- Produces:
  - `enum Note { static let maxLength: Int }` (120)
  - `enum NoteColor: String, Codable, CaseIterable { case yellow, pink, green, blue; static func random() -> NoteColor }`
  - `enum StoredEntry: Codable, Equatable { case photo(path: String); case note(text: String, color: NoteColor) }`
  - `struct LineStore { static let key = "line.v2"; static let legacyKey = "pegged"; init(defaults: UserDefaults); func load() -> [StoredEntry]; func save(_ entries: [StoredEntry]) }`

- [ ] **Step 1: Work on a branch**

```bash
git switch -c sticky-notes
```

- [ ] **Step 2: Add the test target**

Replace `Package.swift` with:

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Tendedero",
    platforms: [.macOS(.v14)],
    targets: [
        // Resources holds the translations. scripts/build-app.sh copies them
        // into the app, so SwiftPM leaves them alone.
        .executableTarget(name: "Tendedero", path: "Sources/Tendedero", exclude: ["Resources"]),
        .testTarget(name: "TendederoTests", dependencies: ["Tendedero"], path: "Tests/TendederoTests"),
    ]
)
```

- [ ] **Step 3: Write the failing tests**

Create `Tests/TendederoTests/LineStoreTests.swift`:

```swift
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
```

- [ ] **Step 4: Run the tests to verify they fail**

Run: `swift test 2>&1 | tail -30`
Expected: FAIL to compile with `cannot find 'LineStore' in scope`. (If instead the failure is a linker or `@testable import` problem with the executable target, stop and report it: the fallback is to move the pure files into a library target, which needs a design decision.)

- [ ] **Step 5: Implement `Note.swift`**

Create `Sources/Tendedero/Note.swift`:

```swift
import Foundation

enum Note {
    /// A note is a reminder, not a document.
    static let maxLength = 120
}

enum NoteColor: String, Codable, CaseIterable {
    case yellow, pink, green, blue

    static func random() -> NoteColor {
        allCases.randomElement() ?? .yellow
    }
}
```

- [ ] **Step 6: Implement `LineStore.swift`**

Create `Sources/Tendedero/LineStore.swift`:

```swift
import Foundation

/// What is saved of one thing hanging on the line.
enum StoredEntry: Codable, Equatable {
    case photo(path: String)
    case note(text: String, color: NoteColor)

    private enum CodingKeys: String, CodingKey { case type, path, text, color }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "photo":
            self = .photo(path: try c.decode(String.self, forKey: .path))
        case "note":
            self = .note(text: try c.decode(String.self, forKey: .text),
                         color: (try? c.decode(NoteColor.self, forKey: .color)) ?? .yellow)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown entry type")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .photo(let path):
            try c.encode("photo", forKey: .type)
            try c.encode(path, forKey: .path)
        case .note(let text, let color):
            try c.encode("note", forKey: .type)
            try c.encode(text, forKey: .text)
            try c.encode(color, forKey: .color)
        }
    }
}

/// The saved line, in rope order. Before notes existed only the paths of the
/// photos were saved, under `legacyKey`: they are read when nothing has been
/// saved under the new key yet.
struct LineStore {
    static let key = "line.v2"
    static let legacyKey = "pegged"

    let defaults: UserDefaults

    func load() -> [StoredEntry] {
        if let data = defaults.data(forKey: Self.key) {
            return (try? JSONDecoder().decode([StoredEntry].self, from: data)) ?? []
        }
        return (defaults.stringArray(forKey: Self.legacyKey) ?? []).map { .photo(path: $0) }
    }

    func save(_ entries: [StoredEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `swift test 2>&1 | tail -30`
Expected: `Executed 7 tests, with 0 failures`.

- [ ] **Step 8: Commit**

```bash
git add Package.swift Sources/Tendedero/Note.swift Sources/Tendedero/LineStore.swift Tests
git commit -m "$(cat <<'EOF'
Add a test target and LineStore for photos and notes

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: `Pegged` kinds and `Line` on `LineStore` (photos behave as before)

**Files:**
- Modify: `Sources/Tendedero/Line.swift` (whole file), `Sources/Tendedero/PeggedView.swift:41-60`, `Sources/Tendedero/AppDelegate.swift` (`fly`, `fall`, `cardFrame`)
- Test: `Tests/TendederoTests/LineTests.swift`

**Interfaces:**
- Consumes: `LineStore`, `StoredEntry`, `NoteColor` from Task 1.
- Produces:
  - `Pegged.Kind { case photo(url: URL, thumb: NSImage); case note(text: String, color: NoteColor) }`
  - `Pegged.init(url:thumb:)`, `Pegged.init(text:color:)`
  - `Pegged` accessors: `url: URL?`, `thumb: NSImage?`, `isNote: Bool`, `noteText: String`, `noteColor: NoteColor`, `stored: StoredEntry`
  - `Line.init(defaults: UserDefaults = .standard)`
  - `Line.hang` now makes room through `makeRoom()` (only photos fall; a line full of notes refuses)

- [ ] **Step 1: Write the failing tests**

Create `Tests/TendederoTests/LineTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test 2>&1 | tail -30`
Expected: FAIL to compile (`Line` has no `init(defaults:)`, `Pegged` has no `isNote`).

- [ ] **Step 3: Replace `Sources/Tendedero/Line.swift`**

Write the whole file as follows. Everything outside the marked changes is the existing code, kept as is.

```swift
import AppKit
import Combine
import os

let log = Logger(subsystem: "app.tendedero.Tendedero", category: "line")

/// One thing hanging on the line: a screenshot or a sticky note.
struct Pegged: Identifiable, Equatable {
    enum Kind {
        case photo(url: URL, thumb: NSImage)
        case note(text: String, color: NoteColor)
    }

    let id = UUID()
    var kind: Kind
    /// Everything hangs a little crooked, like on a real line.
    let tilt = Double.random(in: -2.5...2.5)
    var falling = false
    /// Still flying in from where it was captured; the card waits hidden.
    var flying = false

    init(url: URL, thumb: NSImage) { kind = .photo(url: url, thumb: thumb) }
    init(text: String, color: NoteColor) { kind = .note(text: text, color: color) }

    var url: URL? { if case .photo(let url, _) = kind { return url }; return nil }
    var thumb: NSImage? { if case .photo(_, let thumb) = kind { return thumb }; return nil }
    var isNote: Bool { if case .note = kind { return true }; return false }
    var noteText: String { if case .note(let text, _) = kind { return text }; return "" }
    var noteColor: NoteColor { if case .note(_, let color) = kind { return color }; return .yellow }

    var stored: StoredEntry {
        switch kind {
        case .photo(let url, _): return .photo(path: url.path)
        case .note(let text, let color): return .note(text: text, color: color)
        }
    }

    static func == (a: Pegged, b: Pegged) -> Bool {
        guard a.id == b.id, a.falling == b.falling, a.flying == b.flying else { return false }
        switch (a.kind, b.kind) {
        case (.photo(_, let t1), .photo(_, let t2)): return t1 === t2
        case (.note(let x1, let c1), .note(let x2, let c2)): return x1 == x2 && c1 == c2
        default: return false
        }
    }
}

/// The line itself: what hangs on it and what you can do with each item.
/// The photo files never move. The line is only a view onto them.
@MainActor
final class Line: ObservableObject {
    @Published private(set) var items: [Pegged] = []
    @Published private(set) var gust = 0
    @Published var copiedID: UUID?
    @Published var draggingID: UUID?
    @Published var pressedID: UUID?
    /// Whether the line has slid down into view.
    @Published var revealed = false

    /// Card frames in window coordinates, reported by the views. The panel
    /// uses them to only catch clicks over photos and let the rest through.
    var hitRects: [UUID: CGRect] = [:]

    var maxItems = 8


    var soundOn: Bool {
        get { !UserDefaults.standard.bool(forKey: "soundOff") }
        set { UserDefaults.standard.set(!newValue, forKey: "soundOff") }
    }

    var liveCount: Int { items.filter { !$0.falling }.count }

    private let store: LineStore
    /// While the saved line is being read back, nothing is written.
    private var restoring = false

    init(defaults: UserDefaults = .standard) {
        store = LineStore(defaults: defaults)
        restore()
        scheduleGust()
    }

    // MARK: Hanging and dropping

    @discardableResult
    func hang(_ url: URL, quietly: Bool = false, flying: Bool = false) -> UUID? {
        guard !items.contains(where: { $0.url == url && !$0.falling }),
              let thumb = makeThumbnail(url),
              makeRoom() else { return nil }
        var item = Pegged(url: url, thumb: thumb)
        item.flying = flying
        items.append(item)
        save()
        if !quietly { play("Tink", volume: 0.35) }
        return item.id
    }

    /// A full line lets the oldest photo fall off the far end. Notes never
    /// fall on their own, so a line full of notes has no room.
    private func makeRoom() -> Bool {
        while liveCount >= maxItems {
            guard let oldest = items.first(where: { !$0.falling && !$0.isNote }) else { return false }
            drop(oldest.id, quietly: true)
        }
        return true
    }

    /// The capture has reached the line: the real card takes over.
    func land(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].flying = false
    }

    /// Called just before an item starts falling, so the fall can be drawn
    /// over the whole screen.
    var onFall: ((Pegged) -> Void)?

    func drop(_ id: UUID, quietly: Bool = false) {
        guard let i = items.firstIndex(where: { $0.id == id }), !items[i].falling else { return }
        onFall?(items[i])
        items[i].falling = true
        hitRects[id] = nil
        save()
        if !quietly { play("Pop", volume: 0.25) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.items.removeAll { $0.id == id }
        }
    }

    func clear() {
        let live = items.filter { !$0.falling }
        for (n, item) in live.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06 * Double(n)) { [weak self] in
                self?.drop(item.id, quietly: n > 0)
            }
        }
    }

    /// Photos whose file was deleted or moved away fall off by themselves.
    func prune() {
        for item in items where !item.falling {
            guard let url = item.url, !FileManager.default.fileExists(atPath: url.path) else { continue }
            drop(item.id, quietly: true)
        }
    }

    // MARK: Actions on one photo

    func copy(_ id: UUID) {
        guard let url = items.first(where: { $0.id == id })?.url else { return }
        let entry = NSPasteboardItem()
        if let png = pngData(url) { entry.setData(png, forType: .png) }
        entry.setString(url.absoluteString, forType: .fileURL)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([entry])

        copiedID = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            if self?.copiedID == id { self?.copiedID = nil }
        }
    }

    func open(_ id: UUID) {
        guard let url = items.first(where: { $0.id == id })?.url else { return }
        NSWorkspace.shared.open(url)
    }

    /// Moves the file to the Trash and takes the photo off the line. When a
    /// drag ends on the Dock's Trash, macOS only reports it: deleting the file
    /// is the source app's job, as Finder does.
    func trash(_ id: UUID) {
        guard let url = items.first(where: { $0.id == id })?.url else { return }
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            log.notice("Trashed \(url.lastPathComponent, privacy: .public)")
            if soundOn { Line.trashSound?.play() }
            drop(id, quietly: true)
        } catch {
            log.error("Could not trash \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            NSSound.beep()
        }
    }

    private static let trashSound = NSSound(
        contentsOfFile: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/dock/drag to trash.aif",
        byReference: true)

    /// Whether the file lives in Tendedero's own folder. Those are discarded
    /// to the Trash, or the folder would fill up with forgotten screenshots.
    /// Files anywhere else, like the Desktop, stay where they are. A note has
    /// no file, so it never does.
    func isInInbox(_ id: UUID) -> Bool {
        guard let url = items.first(where: { $0.id == id })?.url else { return false }
        return url.standardizedFileURL.path.hasPrefix(Inbox.folder.standardizedFileURL.path + "/")
    }

    /// The corner cross and "Take down" both end up here.
    func discard(_ id: UUID) {
        if isInInbox(id) { trash(id) } else { drop(id) }
    }

    /// Inbox mode: keep a screenshot by moving it to the Desktop.
    func saveToDesktop(_ id: UUID) {
        guard let url = items.first(where: { $0.id == id })?.url else { return }
        let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        let target = uniqueURL(in: desktop, for: url.lastPathComponent)
        do {
            try FileManager.default.moveItem(at: url, to: target)
            drop(id, quietly: true)
        } catch {
            log.error("Could not save to Desktop: \(error.localizedDescription, privacy: .public)")
            NSSound.beep()
        }
    }

    private func uniqueURL(in folder: URL, for name: String) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = folder.appendingPathComponent(name)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return candidate
    }

    /// Long press: open the photo in the system Markup editor.
    func markup(_ id: UUID) {
        guard let url = items.first(where: { $0.id == id })?.url else { return }
        Markup.shared.edit(url)
    }

    /// After editing, the photo on the line shows the new version.
    func reloadThumbnail(for url: URL) {
        guard let i = items.firstIndex(where: { $0.url == url && !$0.falling }),
              let thumb = makeThumbnail(url) else { return }
        items[i].kind = .photo(url: url, thumb: thumb)
    }

    func reveal(_ id: UUID) {
        guard let url = items.first(where: { $0.id == id })?.url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: Breeze

    /// Every so often a little wind moves the line. It is the detail that
    /// makes it feel like an object and not a widget.
    private func scheduleGust() {
        DispatchQueue.main.asyncAfter(deadline: .now() + .random(in: 7...16)) { [weak self] in
            guard let self else { return }
            if !self.items.isEmpty && self.draggingID == nil { self.gust += 1 }
            self.scheduleGust()
        }
    }

    // MARK: Persistence

    private func save() {
        guard !restoring else { return }
        store.save(items.filter { !$0.falling }.map(\.stored))
    }

    private func restore() {
        restoring = true
        for entry in store.load() {
            switch entry {
            case .photo(let path):
                if FileManager.default.fileExists(atPath: path) {
                    hang(URL(fileURLWithPath: path), quietly: true)
                }
            case .note(let text, let color):
                // Notes come back whatever the capacity: none is ever lost.
                items.append(Pegged(text: text, color: color))
            }
        }
        restoring = false
        save()
    }

    // MARK: Helpers

    private func play(_ name: String, volume: Float) {
        guard soundOn, let sound = NSSound(named: name)?.copy() as? NSSound else { return }
        sound.volume = volume
        sound.play()
    }

    private func pngData(_ url: URL) -> Data? {
        if url.pathExtension.lowercased() == "png" { return try? Data(contentsOf: url) }
        guard let tiff = NSImage(contentsOf: url)?.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

func makeThumbnail(_ url: URL, maxPixels: Int = 480) -> NSImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixels,
    ]
    guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
}
```

- [ ] **Step 4: Fix the callers so the app compiles**

In `Sources/Tendedero/PeggedView.swift`:

- Replace `private var photoSize: CGSize { Self.photoSize(for: item.thumb.size) }` with `private var photoSize: CGSize { Self.photoSize(for: item.thumb?.size ?? .zero) }`.
- Replace `Image(nsImage: item.thumb)` with `Image(nsImage: item.thumb ?? NSImage())`.

In `Sources/Tendedero/AppDelegate.swift`:

- In `fly(_:from:)`, replace the first `guard` and the thumbnail line with:

```swift
        guard isPresent, isRevealed, let screen = panel.screen,
              let to = cardFrame(for: id),
              let item = line.items.first(where: { $0.id == id }),
              let url = item.url else {
            line.land(id)
            return
        }
        let pixels = Int(max(from.width, from.height) * screen.backingScaleFactor)
        guard let image = makeThumbnail(url, maxPixels: min(3000, max(400, pixels)))?
            .cgImage(forProposedRect: nil, context: nil, hints: nil) else {
```

  (the body of that second `guard`, `line.land(id); return }`, stays as it is).
- In `fall(_:)`, replace `let image = item.thumb.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }` with `let image = item.thumb?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }`.
- In `cardFrame(for:)`, replace `PeggedView.cardSize(for: line.items[index].thumb.size)` with `PeggedView.cardSize(for: line.items[index].thumb?.size ?? .zero)`.

`GrabArea.swift` needs no change: `view.url = item.url` and `view.dragImage = item.thumb` are both optionals already.

- [ ] **Step 5: Build and run the tests**

Run: `swift build 2>&1 | tail -20 && swift test 2>&1 | tail -30`
Expected: build succeeds; `Executed 11 tests, with 0 failures`.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
Let the line hold photos or notes and save them as JSON

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Note behaviour in `Line`

**Files:**
- Modify: `Sources/Tendedero/Line.swift`
- Test: `Tests/TendederoTests/LineTests.swift`

**Interfaces:**
- Consumes: everything from Task 2; `Note.maxLength`.
- Produces on `Line`:
  - `@Published private(set) var editingID: UUID?`
  - `func addNote(text: String = "", color: NoteColor = .random(), quietly: Bool = false) -> UUID?` (nil when the line is full of notes; commits any note being edited first; the new note is left in editing)
  - `func beginEditing(_ id: UUID)` (notes only; commits the previous one)
  - `func setNoteText(_ id: UUID, _ text: String)` (truncates to `Note.maxLength` characters, saves)
  - `func endEditing()` (commits; a whitespace-only note takes itself down)
  - `drop` clears `editingID` when the dropped item is the one being edited
  - `var onNewNote: (() -> Void)?` and `func requestNewNote()` (used by the "+" button in Task 5)

- [ ] **Step 1: Write the failing tests**

Append these inside `LineTests` (before the closing brace):

```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test 2>&1 | tail -30`
Expected: FAIL to compile (`addNote`, `editingID`, `setNoteText`… do not exist).

- [ ] **Step 3: Add the note API to `Line`**

In `Sources/Tendedero/Line.swift`:

1. Below `@Published var revealed = false` add:

```swift
    /// The note being written, if any. Only one at a time.
    @Published private(set) var editingID: UUID?
```

2. In `drop`, right after the `guard`, add the line that ends editing of the dropped item:

```swift
        guard let i = items.firstIndex(where: { $0.id == id }), !items[i].falling else { return }
        if editingID == id { editingID = nil }
        onFall?(items[i])
```

3. Add this section after the `// MARK: Hanging and dropping` section (before `// MARK: Actions on one photo`):

```swift
    // MARK: Notes

    /// Called when someone asks for a new note from the line itself.
    var onNewNote: (() -> Void)?

    func requestNewNote() { onNewNote?() }

    /// Hangs an empty note and leaves it ready to write. Nil when the line is
    /// full of notes: they never fall on their own to make room.
    @discardableResult
    func addNote(text: String = "", color: NoteColor = .random(), quietly: Bool = false) -> UUID? {
        endEditing()
        guard makeRoom() else { return nil }
        let item = Pegged(text: String(text.prefix(Note.maxLength)), color: color)
        items.append(item)
        editingID = item.id
        save()
        if !quietly { play("Tink", volume: 0.35) }
        return item.id
    }

    func beginEditing(_ id: UUID) {
        guard editingID != id,
              items.contains(where: { $0.id == id && $0.isNote && !$0.falling }) else { return }
        endEditing()
        editingID = id
    }

    func setNoteText(_ id: UUID, _ text: String) {
        guard let i = items.firstIndex(where: { $0.id == id && $0.isNote && !$0.falling }) else { return }
        items[i].kind = .note(text: String(text.prefix(Note.maxLength)), color: items[i].noteColor)
        save()
    }

    /// Commits the note being written. One left empty takes itself down.
    func endEditing() {
        guard let id = editingID else { return }
        editingID = nil
        if let item = items.first(where: { $0.id == id }),
           item.noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            drop(id, quietly: true)
        }
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test 2>&1 | tail -30`
Expected: `Executed 23 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
Add notes to the line model: create, edit, commit and capacity

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Shortcut, note card and in-place editing

This task puts notes on screen and makes typing work. It carries the risk named in the spec: whether a non-activating `NSPanel` with a dynamic `canBecomeKey` reliably receives the keyboard. The code is written so that step 11 answers that.

**Files:**
- Modify: `Sources/Tendedero/HotKey.swift`, `LinePanel.swift`, `LineView.swift` (Layout), `PeggedView.swift`, `AppDelegate.swift`
- Create: `Sources/Tendedero/NoteCard.swift`, `NoteTextView.swift`, `TapArea.swift`

**Interfaces:**
- Consumes: `Line` note API from Task 3; `GrabView.crossHitSize`, `ClosureMenuItem`, `HitRectsKey`, `glassFrame` already in the codebase.
- Produces:
  - `HotKey(keyCode:modifiers:action:)` unchanged signature, now several instances can coexist.
  - `LinePanel.allowsKey: Bool`
  - `Layout.noteSize: CGFloat` (130)
  - `NoteStyle.ink: NSColor`, `NoteStyle.nsFont: NSFont`; `NoteColor.paper: Color`
  - `NoteCard(text:color:editing:onText:onCommit:)`
  - `NoteTextView(text:onText:onCommit:)`
  - `TapArea(onTap:onCross:menuProvider:)`
  - `AppDelegate.newNote()` (private)

- [ ] **Step 1: Let several shortcuts coexist**

Replace `Sources/Tendedero/HotKey.swift` with:

```swift
import Carbon

/// A global shortcut through the Carbon hot key API. Unlike a global key
/// monitor, it needs no Accessibility permission. Several can coexist: one
/// event handler serves them all and looks the action up by id.
final class HotKey {
    private var ref: EventHotKeyRef?
    private let id: UInt32
    private static var actions: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var handlerInstalled = false

    init(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        id = HotKey.nextID
        HotKey.nextID += 1
        HotKey.actions[id] = action
        HotKey.installHandlerOnce()
        let hotKeyID = EventHotKeyID(signature: OSType(0x5445_4E44), id: id) // "TEND"
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &ref)
    }

    private static func installHandlerOnce() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var pressed = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            DispatchQueue.main.async { HotKey.actions[pressed.id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        HotKey.actions[id] = nil
    }
}
```

- [ ] **Step 2: Let the panel become key on demand**

In `Sources/Tendedero/LinePanel.swift`, replace

```swift
    override var canBecomeKey: Bool { false }
```

with

```swift
    /// The line never takes focus, except while a note is being written:
    /// then it must be key to receive the keyboard.
    var allowsKey = false

    override var canBecomeKey: Bool { allowsKey }
```

- [ ] **Step 3: The note size**

In `Sources/Tendedero/LineView.swift`, inside `enum Layout`, below `static let cardWidth: CGFloat = 150` add:

```swift
    static let noteSize: CGFloat = 130
```

- [ ] **Step 4: The note paper**

Create `Sources/Tendedero/NoteCard.swift`:

```swift
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
```

- [ ] **Step 5: The text view**

Create `Sources/Tendedero/NoteTextView.swift`:

```swift
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
```

- [ ] **Step 6: The click catcher**

Create `Sources/Tendedero/TapArea.swift`:

```swift
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
```

- [ ] **Step 7: Draw a note on the line**

In `Sources/Tendedero/PeggedView.swift`:

1. In `body`, replace the line `card` (the second child of the `VStack`) with `content`.

2. Rename `private var card: some View {` to `private var photoCard: some View {`.

3. In `photoCard`, replace the cross overlay

```swift
            .overlay(alignment: .topLeading) {
                // Drawn here, clicked through GrabView, which sits on top.
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 20, height: 20)
                    .glassFrame(circle: true)
                    .padding(3)
                    .opacity(hovering && !dragging ? 1 : 0)
                    .scaleEffect(hovering ? 1 : 0.6)
                    .allowsHitTesting(false)
            }
```

with

```swift
            .overlay(alignment: .topLeading) {
                // Drawn here, clicked through GrabView, which sits on top.
                crossBadge(visible: hovering && !dragging)
            }
```

4. Add these members right before `private func arrive()`:

```swift
    private var editing: Bool { line.editingID == item.id }

    @ViewBuilder
    private var content: some View {
        if item.isNote { noteCard } else { photoCard }
    }

    private func crossBadge(visible: Bool) -> some View {
        Image(systemName: "xmark")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.primary)
            .frame(width: 20, height: 20)
            .glassFrame(circle: true)
            .padding(3)
            .opacity(visible ? 1 : 0)
            .scaleEffect(hovering ? 1 : 0.6)
            .allowsHitTesting(false)
    }

    /// A sticky note: same clothespin, swing and fall as a photo. Click to
    /// write on it; the cross and "Take down" both remove it.
    private var noteCard: some View {
        let id = item.id
        let line = line
        return NoteCard(text: item.noteText, color: item.noteColor, editing: editing,
                        onText: { line.setNoteText(id, $0) }, onCommit: { line.endEditing() })
            .shadow(color: .black.opacity(hovering ? 0.26 : 0.18), radius: hovering ? 14 : 10, y: hovering ? 8 : 5)
            .scaleEffect(hovering && !editing ? 1.035 : 1, anchor: .top)
            .overlay(alignment: .topLeading) {
                crossBadge(visible: hovering && !editing)
            }
            .overlay {
                if !editing {
                    TapArea(onTap: { line.beginEditing(id) },
                            onCross: { line.discard(id) },
                            menuProvider: {
                                let menu = NSMenu()
                                menu.addItem(ClosureMenuItem(L("Edit")) { line.beginEditing(id) })
                                menu.addItem(.separator())
                                menu.addItem(ClosureMenuItem(L("Take down")) { line.discard(id) })
                                return menu
                            })
                }
            }
            .animation(.easeOut(duration: 0.18), value: hovering)
            .onHover { hovering = $0 }
            .background(
                GeometryReader { g in
                    Color.clear.preference(key: HitRectsKey.self,
                                           value: item.falling ? [:] : [id: g.frame(in: .global)])
                }
            )
    }
```

- [ ] **Step 8: Wire editing into `AppDelegate`**

In `Sources/Tendedero/AppDelegate.swift`:

1. Next to `private var hotKey: HotKey?` add `private var noteHotKey: HotKey?`.

2. In `applicationDidFinishLaunching`, right after the `hotKey = HotKey(...) { ... }` block add:

```swift
        noteHotKey = HotKey(keyCode: kVK_ANSI_N, modifiers: controlKey | optionKey) { [weak self] in
            self?.newNote()
        }
```

3. In the same function, below `watchMenuBarClicks()` add `watchEditingClicks()`, and below the `line.$items ... .store(in: &cancellables)` chain add:

```swift
        line.$editingID
            .receive(on: RunLoop.main)
            .sink { [weak self] id in self?.editingChanged(id) }
            .store(in: &cancellables)

        // Losing the keyboard to another app ends the note.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.line.endEditing() }
        }
```

4. Add a `// MARK: Notes` section after the `// MARK: Showing and hiding` section's `toggle()` method (any place inside the class works; keep it before `startMouseTracking`):

```swift
    // MARK: Notes

    /// A new note, written in place. Nothing happens when a full screen app
    /// hides the line or the line is full of notes.
    private func newNote() {
        if let screen = LinePanel.screenUnderPointer(), FullScreen.isActive(on: screen) {
            NSSound.beep()
            return
        }
        if line.addNote() == nil { NSSound.beep() }
    }

    /// Writing needs the keyboard, so the panel can be key only while a note
    /// is being edited, and the line stays down meanwhile.
    private func editingChanged(_ id: UUID?) {
        if id != nil {
            keepOpen = true
            wanted = true
            if !isRevealed {
                panel.placeOnScreen()
                updateCapacity()
            }
            refresh()
            reveal(pinned: true)
            panel.allowsKey = true
            panel.makeKeyAndOrderFront(nil)
        } else if panel.allowsKey {
            panel.allowsKey = false
            panel.makeFirstResponder(nil)
            // Ordering the panel out hands the keyboard back to the app you
            // were in; ordering it front again keeps the line on screen.
            panel.orderOut(nil)
            if isPresent { panel.orderFrontRegardless() }
            keepOpen = false
            itemsChanged()
        }
    }

    /// A click anywhere outside the note being written commits it.
    private func watchEditingClicks() {
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.line.endEditing() }
        }) {
            clickMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, let id = self.line.editingID else { return }
                let p = self.panel.convertPoint(fromScreen: NSEvent.mouseLocation)
                let flipped = CGPoint(x: p.x, y: self.panel.frame.height - p.y)
                if !(self.line.hitRects[id]?.contains(flipped) ?? false) { self.line.endEditing() }
            }
            return event
        }) {
            clickMonitors.append(local)
        }
    }
```

5. In `tick()`, add the editing note to the "busy" conditions:

```swift
        let busy = pinned || GrabView.isDragging || line.pressedID != nil || line.editingID != nil || now < peekUntil
```

6. In `setRevealed(_:)`, end editing whenever the line goes away:

```swift
        if !on {
            line.endEditing()
            pinned = false
            peekUntil = .distantPast
            panel.ignoresMouseEvents = true
        }
```

- [ ] **Step 9: Add the temporary English fallback strings**

`L("…")` falls back to the English key when a string is missing in a bare build, so nothing breaks at runtime. The real translations come in Task 6 (`check-strings` is expected to fail until then).

- [ ] **Step 10: Build and run the tests**

Run: `swift build 2>&1 | tail -20 && swift test 2>&1 | tail -30`
Expected: build succeeds; `Executed 23 tests, with 0 failures`.

- [ ] **Step 11: Verify by hand that typing works (the spec's main risk)**

This needs a person at the Mac. Quit the installed Tendedero first (it owns the same shortcuts), then:

```bash
swift build && .build/debug/Tendedero
```

Check, in this order:

1. ⌃⌥N brings the line down with an empty note showing "Write a task" and a caret; typing "buy milk" shows the text on the note.
2. Return keeps the note and the line stays down until the pointer has visited it and left.
3. Click the note, type more, press Esc: the text is kept.
4. ⌃⌥N then Esc with nothing typed: the empty note disappears.
5. Shift-Return inserts a new line; Return commits.
6. While writing, click another app's window: the note commits, and that app keeps working.
7. After committing, the app you were in gets the keyboard back (type something in it).

If 1 fails (nothing can be typed): stop and report to the user, do not improvise. The agreed fallback is a small separate window for typing (plan B of the design).
If only 7 fails (focus does not return), report it too; the likely fix is to remember `NSWorkspace.shared.frontmostApplication` when editing starts and `activate()` it when editing ends *only* if it is still frontmost.

Stop the test run with `pkill -x Tendedero`.

- [ ] **Step 12: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
Write notes in place with a second shortcut

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Falling notes, the "+" button and the menu item

**Files:**
- Modify: `Sources/Tendedero/AppDelegate.swift`, `Sources/Tendedero/LineView.swift`

**Interfaces:**
- Consumes: `Line.requestNewNote()` / `Line.onNewNote` (Task 3), `TapArea` and `NoteCard` (Task 4), `AppDelegate.newNote()` (Task 4).
- Produces: nothing used later.

- [ ] **Step 1: Make a taken down note fall over the screen**

In `Sources/Tendedero/AppDelegate.swift`:

1. Replace `fall(_:)` with:

```swift
    /// A discarded card falls over the whole screen, from where it hangs.
    private func fall(_ item: Pegged) {
        guard isPresent, isRevealed, !item.flying, let screen = panel.screen,
              let card = cardFrame(for: item.id),
              let image = fallImage(for: item, scale: screen.backingScaleFactor) else { return }
        CaptureFlight.fall(image: image, card: card, tilt: CGFloat(item.tilt), on: screen)
    }

    /// What falls: the photo, or the paper drawn once as an image.
    private func fallImage(for item: Pegged, scale: CGFloat) -> CGImage? {
        if let thumb = item.thumb {
            return thumb.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        let renderer = ImageRenderer(content: NoteCard(text: item.noteText, color: item.noteColor))
        renderer.scale = scale
        return renderer.cgImage
    }
```

2. In `cardFrame(for:)`, replace the `let size = PeggedView.cardSize(...)` line with:

```swift
        let item = line.items[index]
        let size = item.isNote
            ? CGSize(width: Layout.noteSize, height: Layout.noteSize)
            : PeggedView.cardSize(for: item.thumb?.size ?? .zero)
```

  Also fix its first line so it does not index twice: it already uses `line.items.firstIndex(where:)` to get `index`; keep that.

- [ ] **Step 2: Add the "+" button**

In `Sources/Tendedero/LineView.swift`:

1. In `LineView.body`, inside the `ZStack`, after the `ForEach { ... }` block add:

```swift
                AddNoteButton(line: line)
                    .position(x: width - 34, y: Layout.ropeY(x: width - 34, width: width) + 30)
```

2. Add this view below `Hint`:

```swift
/// The "+" at the right end of the line: hangs a new note.
private struct AddNoteButton: View {
    static let hitID = UUID()
    let line: Line

    var body: some View {
        Image(systemName: "plus")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.primary)
            .frame(width: 28, height: 28)
            .glassFrame(circle: true)
            .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
            .overlay(TapArea(onTap: { line.requestNewNote() }))
            .background(
                GeometryReader { g in
                    Color.clear.preference(key: HitRectsKey.self, value: [Self.hitID: g.frame(in: .global)])
                }
            )
    }
}
```

- [ ] **Step 3: Connect the button and add the menu item**

In `Sources/Tendedero/AppDelegate.swift`:

1. Next to `line.onFall = { ... }` add:

```swift
        line.onNewNote = { [weak self] in self?.newNote() }
```

2. In `menuNeedsUpdate`, right after `menu.addItem(toggleItem)` add:

```swift
        let noteItem = ClosureMenuItem(L("New note")) { [weak self] in
            self?.newNote()
        }
        noteItem.keyEquivalent = "n"
        noteItem.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(noteItem)
```

- [ ] **Step 4: Build and run the tests**

Run: `swift build 2>&1 | tail -20 && swift test 2>&1 | tail -30`
Expected: build succeeds; `Executed 23 tests, with 0 failures`.

- [ ] **Step 5: Verify by hand**

With the installed Tendedero quit, run `swift build && .build/debug/Tendedero` and check:

1. Pressing ⌃⌥T shows the line with a round "+" at its right end; clicking it hangs a new note ready to write (the very first click works, even right after switching apps).
2. The menu bar icon's menu has "New note" and it hangs a note.
3. Hover a note: the corner cross appears; clicking it makes the note fall across the screen like a photo does (the paper, not a blank).
4. Right click a note: "Edit" and "Take down" both work.
5. Fill the line with notes (screen-width dependent): the next ⌃⌥N, "+" or capture does nothing and beeps / does not hang.

Stop with `pkill -x Tendedero`.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
Add the plus button, the menu item and a falling note

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Translations, READMEs and final verification

**Files:**
- Modify: `Sources/Tendedero/Resources/en.lproj/Localizable.strings`, `es.lproj/…`, `zh-Hans.lproj/…`, `README.md`, `docs/i18n/README.es.md`, `docs/i18n/README.zh-Hans.md`

**Interfaces:** none.

- [ ] **Step 1: Run the string check to see what is missing**

Run: `swift scripts/check-strings.swift`
Expected: FAIL listing `missing "New note"`, `missing "Edit"`, `missing "Write a task"` for each language.

- [ ] **Step 2: Add the strings**

Open each `Localizable.strings` and add the entries under the matching section comments (`/* AppDelegate */`, `/* PeggedView */`, and a new `/* NoteCard */` section at the end), keeping the file's existing style.

`en.lproj/Localizable.strings` (key equals value, like the other entries there):

```
"New note" = "New note";
"Edit" = "Edit";
"Write a task" = "Write a task";
```

`es.lproj/Localizable.strings`:

```
"New note" = "Nueva nota";
"Edit" = "Editar";
"Write a task" = "Escribe una tarea";
```

`zh-Hans.lproj/Localizable.strings`:

```
"New note" = "新建便签";
"Edit" = "编辑";
"Write a task" = "写下一项任务";
```

- [ ] **Step 3: Run the string check**

Run: `swift scripts/check-strings.swift`
Expected: `… strings, all present in en, es, zh-Hans`.

- [ ] **Step 4: Update the READMEs**

In each README, add a row after the `⌃⌥T` row of the gestures table, and a short section just before the "Your Desktop. Finally clear." section (`## Tu Escritorio, por fin despejado.` in Spanish, `## 桌面，终于清爽了` in Chinese), matching the neighbours' tone and the line breaks they use.

`README.md`:

```
| <kbd>⌃</kbd>&thinsp;<kbd>⌥</kbd>&thinsp;<kbd>N</kbd> | Hang a new note. |
```

```
## Notes, too.

Hang a sticky note next to your screenshots for what you still have to do.
Press <kbd>⌃</kbd>&thinsp;<kbd>⌥</kbd>&thinsp;<kbd>N</kbd> or the + on the line, write it, press Return.
When it's done, take it down with the cross.

<br>
<br>
```

`docs/i18n/README.es.md`:

```
| <kbd>⌃</kbd>&thinsp;<kbd>⌥</kbd>&thinsp;<kbd>N</kbd> | Cuelga una nota nueva. |
```

```
## También notas.

Cuelga una nota junto a tus capturas con lo que te falta hacer.
Pulsa <kbd>⌃</kbd>&thinsp;<kbd>⌥</kbd>&thinsp;<kbd>N</kbd> o el + de la cuerda, escríbela y pulsa Intro.
Cuando esté hecha, descuélgala con la cruz.

<br>
<br>
```

`docs/i18n/README.zh-Hans.md`:

```
| <kbd>⌃</kbd>&thinsp;<kbd>⌥</kbd>&thinsp;<kbd>N</kbd> | 挂上一张新便签。 |
```

```
## 也可以挂便签

在截图旁边挂一张便签，写下还没做完的事。
按 <kbd>⌃</kbd>&thinsp;<kbd>⌥</kbd>&thinsp;<kbd>N</kbd> 或点击绳子上的 +，写好后按回车。
做完了，点一下角上的叉把它摘下来。

<br>
<br>
```

Check each README's spacing around the new section against the one above it (the `<br>` pairs between sections) and keep it consistent.

- [ ] **Step 5: Full verification**

Run: `swift build 2>&1 | tail -5 && swift test 2>&1 | tail -5 && swift scripts/check-strings.swift`
Expected: build succeeds, `Executed 23 tests, with 0 failures`, strings all present.

Then, with the installed Tendedero quit, run `swift build && .build/debug/Tendedero` and have the user walk the spec's checklist:

1. ⌃⌥N brings the line down with a focused empty note.
2. Type, press Return: the note stays and the line keeps open until the pointer leaves.
3. Click the note, edit, press Esc: text is kept.
4. ⌃⌥N, then Esc without typing: the note disappears.
5. Click outside while editing: it commits.
6. The cross and right click "Take down" remove the note.
7. Quit and relaunch: photos and notes come back in the same order.
8. Fill the line: only photos fall, no note is lost.
9. After editing, the app you were in gets the keyboard back.
10. Take a screenshot with notes on the line: it flies to its place and the notes keep theirs.
11. "Take everything down" in the menu removes photos and notes (this is by design; confirm the user is happy with it).

Report each item as passed or failed. Do not claim the feature works from the build and tests alone: items 1 to 9 can only be checked at the Mac.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
Translate the note strings and document notes in the READMEs

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 7: Finish the branch**

Use the superpowers:finishing-a-development-branch skill to decide how to integrate `sticky-notes` into `main`.

---

## Self-review

**Spec coverage.**
- Model and persistence (spec §1): Tasks 1 and 2 (`Pegged.Kind`, `LineStore`, migration, restore without save churn).
- Capacity rules (notes never fall, shared limit, refusals): Task 2 `makeRoom`, Task 3 tests, Task 4 `newNote` beep, Task 5 manual check 5.
- Creation by shortcut, "+" and menu item: Tasks 4 (shortcut) and 5 ("+", menu item).
- Editing in place, key handling, commit rules, click-outside, line stays down, focus returns: Task 4 (steps 2, 5, 8, 11).
- Look (130 pt, 4 pastel colours, ~120 chars, shadow/tilt/sway): Task 4 (`NoteCard`, `PeggedView.noteCard`; tilt and sway come from the shared card).
- Gestures (click, cross, right click; drag does nothing): Task 4 `TapArea` + `noteCard`.
- Strings and READMEs: Task 6. Tests: Tasks 1 to 3. Checklist: Task 6 step 5.
- Out of scope items are not implemented.

**Placeholder scan.** No TBD / TODO. The two conditional notes in Task 4 step 11 are explicit stop-and-report instructions for a risk the spec names, not missing work.

**Type consistency.** `Pegged.Kind`, `StoredEntry`, `LineStore.key/legacyKey`, `Note.maxLength`, `Line.addNote/beginEditing/setNoteText/endEditing/editingID/onNewNote/requestNewNote`, `LinePanel.allowsKey`, `Layout.noteSize`, `NoteCard(text:color:editing:onText:onCommit:)`, `TapArea(onTap:onCross:menuProvider:)` are used with the same names and signatures in every task that mentions them. The test count goes 7 → 11 → 23 and stays 23 afterwards.
