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
    /// The note being written, if any. Only one at a time.
    @Published private(set) var editingID: UUID?

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
        if editingID == id { editingID = nil }
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

    // MARK: Notes

    /// Called when someone asks for a new note from the line itself.
    var onNewNote: (() -> Void)?

    func requestNewNote() { onNewNote?() }

    /// Hangs an empty note and leaves it ready to write. Nil when the line is
    /// full of notes: they never fall on their own to make room.
    @discardableResult
    func addNote(text: String = "", color: NoteColor = .random(), quietly: Bool = false) -> UUID? {
        // An empty note is still open: that is the one to write on.
        if let open = editingID, isBlank(open) { return open }
        guard makeRoom() else {
            endEditing()
            return nil
        }
        let item = Pegged(text: String(text.prefix(Note.maxLength)), color: color)
        items.append(item)
        switchEditing(to: item.id)
        save()
        if !quietly { play("Tink", volume: 0.35) }
        return item.id
    }

    func beginEditing(_ id: UUID) {
        guard editingID != id,
              items.contains(where: { $0.id == id && $0.isNote && !$0.falling }) else { return }
        switchEditing(to: id)
    }

    /// Moves the keyboard from one note to another. The id goes straight from
    /// one to the other, never through nil: a late "editing ended" would end
    /// the note that was just started.
    private func switchEditing(to id: UUID) {
        let previous = editingID
        editingID = id
        if let previous { commit(previous) }
    }

    private func isBlank(_ id: UUID) -> Bool {
        guard let item = items.first(where: { $0.id == id }) else { return false }
        return item.noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// A note left empty takes itself down.
    private func commit(_ id: UUID) {
        if isBlank(id) { drop(id, quietly: true) }
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
        commit(id)
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
