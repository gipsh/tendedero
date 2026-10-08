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
