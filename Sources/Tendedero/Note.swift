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
