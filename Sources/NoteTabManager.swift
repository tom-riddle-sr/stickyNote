import Cocoa
import Combine

final class NoteTabManager {

    // Layout constants
    let W:  CGFloat = 320   // expanded width（需容納工具列約 275px card 內容）
    let H:  CGFloat = 160   // note tab height
    let TW: CGFloat = 42    // tab strip width — 42px visible on edge
    let SP: CGFloat = 6     // gap between tabs
    let AH: CGFloat = 44    // add-button height（New Note 按鈕）

    private var currentScreen: NSScreen
    private var currentEdge:   Edge
    private let noteStore: NoteStore
    private let appState:  AppState

    private var noteTabs:  [UUID: NoteTabPanel] = [:]
    private var addPanel:  AddNotePanel?
    private var bag = Set<AnyCancellable>()

    private(set) var isHidden = false

    /// Persisted Y position of the add-button (nil = auto-center)
    private var persistedAddY: CGFloat? {
        didSet {
            if let v = persistedAddY { UserDefaults.standard.set(Double(v), forKey: "addPanelY") }
        }
    }

    init(screen: NSScreen, edge: Edge, noteStore: NoteStore, appState: AppState) {
        currentScreen = screen
        currentEdge   = edge
        self.noteStore = noteStore
        self.appState  = appState
        // Restore persisted Y
        let saved = UserDefaults.standard.double(forKey: "addPanelY")
        if saved != 0 { persistedAddY = CGFloat(saved) }
        build()

        noteStore.$notes
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] notes in self?.sync(notes: notes) }
            .store(in: &bag)
    }

    // MARK: - Build

    private func build() {
        for note in noteStore.notes { createTab(for: note) }
        addPanel = AddNotePanel(screen: currentScreen, edge: currentEdge,
                                appState: appState, W: W, AH: AH, TW: TW,
                                onAdd: { [weak self] in self?.noteStore.addNote() })
        addPanel?.onDrag = { [weak self] deltaY, mouseX in
            self?.handleDrag(deltaY: deltaY, mouseX: mouseX)
        }
        addPanel?.makeKeyAndOrderFront(nil)
        reposition(animated: false)
    }

    private func createTab(for note: Note) {
        let p = NoteTabPanel(note: note, screen: currentScreen, edge: currentEdge,
                             appState: appState, W: W, H: H, TW: TW, noteStore: noteStore)
        p.makeKeyAndOrderFront(nil)
        noteTabs[note.id] = p
    }

    // MARK: - Sync

    private func sync(notes: [Note]) {
        let newIDs = Set(notes.map { $0.id })
        for (id, panel) in noteTabs where !newIDs.contains(id) {
            panel.orderOut(nil); noteTabs.removeValue(forKey: id)
        }
        let existing = Set(noteTabs.keys)
        for note in notes where !existing.contains(note.id) { createTab(for: note) }
        reposition(animated: true)
    }

    // MARK: - Drag handler

    private func handleDrag(deltaY: CGFloat, mouseX: CGFloat) {
        let vf     = currentScreen.visibleFrame
        let margin: CGFloat = 10

        // Move add button vertically
        let currentAddY = persistedAddY ?? (vf.minY + margin)
        persistedAddY = max(vf.minY + margin,
                            min(currentAddY + deltaY, vf.maxY - margin - AH))

        // Switch edge when mouse crosses screen midpoint
        let mid = currentScreen.frame.midX
        let newEdge: Edge = mouseX > mid ? .right : .left
        if newEdge != currentEdge {
            currentEdge   = newEdge
            appState.edge = newEdge
            for panel in noteTabs.values { panel.setEdge(newEdge) }
            addPanel?.setEdge(newEdge)
        }

        reposition(animated: false)
    }

    // MARK: - Layout

    private func reposition(animated: Bool) {
        let notes  = noteStore.notes
        let n      = notes.count
        let vf     = currentScreen.visibleFrame
        let margin: CGFloat = 10

        // Add button: use persisted Y or default (bottom of screen)
        let addY = max(vf.minY + margin,
                       min(persistedAddY ?? (vf.minY + margin), vf.maxY - margin - AH))
        addPanel?.updateY(addY, animated: animated)

        guard n > 0 else { return }

        // Notes stack upward from just above the add button
        let baseY     = addY + AH + SP
        let ph        = noteTabs.values.first?.currentPanelHeight ?? H
        let available = vf.maxY - margin - baseY - ph
        let naturalStep = ph + SP
        let step = n > 1 ? min(naturalStep, max(32, available / CGFloat(n - 1))) : naturalStep

        for (i, note) in notes.enumerated() {
            let posFromBottom = n - 1 - i
            noteTabs[note.id]?.updateY(baseY + CGFloat(posFromBottom) * step, animated: animated)
        }
    }

    // MARK: - Hide / Show all

    func toggleVisibility() {
        isHidden.toggle()
        if isHidden {
            for p in noteTabs.values { p.orderOut(nil) }
            addPanel?.orderOut(nil)
        } else {
            addPanel?.makeKeyAndOrderFront(nil)
            for p in noteTabs.values { p.makeKeyAndOrderFront(nil) }
            reposition(animated: false)
        }
    }

    // MARK: - Attach to new screen/edge

    func attach(to screen: NSScreen, edge: Edge) {
        currentScreen  = screen; currentEdge = edge; appState.edge = edge
        persistedAddY  = nil
        UserDefaults.standard.removeObject(forKey: "addPanelY")
        for p in noteTabs.values { p.orderOut(nil) }
        noteTabs.removeAll()
        addPanel?.orderOut(nil); addPanel = nil
        build()
    }
}
