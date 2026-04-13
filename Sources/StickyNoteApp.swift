import SwiftUI
import Combine

// MARK: - Pastel Rainbow Fantasy Palette (user-specified hex colours)
let notePalette: [(tab: Color, card: Color)] = [
    (Color(hex:"ffadad"), Color(hex:"ffd6d6")),  // Powder Blush
    (Color(hex:"ffd6a5"), Color(hex:"ffeade")),  // Apricot Cream
    (Color(hex:"fdffb6"), Color(hex:"feffda")),  // Lemon Chiffon
    (Color(hex:"caffbf"), Color(hex:"e4ffdf")),  // Tea Green
    (Color(hex:"9bf6ff"), Color(hex:"cdfaff")),  // Soft Cyan
    (Color(hex:"a0c4ff"), Color(hex:"cfe1ff")),  // Baby Blue Ice
    (Color(hex:"bdb2ff"), Color(hex:"ded8ff")),  // Periwinkle
    (Color(hex:"ffc6ff"), Color(hex:"ffe2ff")),  // Mauve
]

// MARK: - Note  (stores RTF attributed text)

struct Note: Identifiable, Codable {
    var id:         UUID
    var rtfData:    Data      // NSAttributedString serialised as RTF
    var colorIndex: Int

    init(id: UUID = UUID(), rtfData: Data = Data(), colorIndex: Int = 0) {
        self.id = id; self.rtfData = rtfData; self.colorIndex = colorIndex
    }
}

// MARK: - NoteStore

final class NoteStore: ObservableObject {
    @Published var notes: [Note] = []
    private let key = "notes_v4"
    private var bag = Set<AnyCancellable>()

    init() {
        load()
        if notes.isEmpty { notes = [Note(colorIndex: 0)] }
        $notes.dropFirst()
            .debounce(for: .seconds(0.6), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.save() }
            .store(in: &bag)
    }

    func addNote() {
        notes.append(Note(colorIndex: notes.count % notePalette.count))
    }

    func deleteNote(_ id: UUID) {
        notes.removeAll { $0.id == id }
        if notes.isEmpty { notes = [Note(colorIndex: 0)] }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(notes) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    private func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([Note].self, from: data) {
            notes = decoded
        }
    }
}

// MARK: - Edge & AppState

enum Edge: String, CaseIterable {
    case left = "left", right = "right"
    var displayName: String { rawValue.capitalized }
}

final class AppState: ObservableObject {
    @Published var edge: Edge = .right
}

// MARK: - Helpers

extension Color {
    init(r: Double, g: Double, b: Double) {
        self.init(red: r / 255, green: g / 255, blue: b / 255)
    }
    init(hex: String) {
        let v = UInt64(hex, radix: 16) ?? 0
        self.init(r: Double((v >> 16) & 0xFF), g: Double((v >> 8) & 0xFF), b: Double(v & 0xFF))
    }
}
extension NSColor {
    convenience init(r: CGFloat, g: CGFloat, b: CGFloat) {
        self.init(calibratedRed: r/255, green: g/255, blue: b/255, alpha: 1)
    }
}

// MARK: - Entry Point

@main
struct StickyNoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene { Settings { EmptyView() } }
}
