import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var tabManager: NoteTabManager?
    private var statusItem: NSStatusItem?
    let appState  = AppState()
    let noteStore = NoteStore()

    private var savedScreenID: String {
        get { UserDefaults.standard.string(forKey: "selectedScreenID") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "selectedScreenID") }
    }
    private var savedEdge: Edge {
        get { Edge(rawValue: UserDefaults.standard.string(forKey: "selectedEdge") ?? "") ?? .right }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "selectedEdge") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // If saved edge is now an inner edge (faces another screen), auto-migrate
        if let screen = NSScreen.screens.first(where: { screenID(for: $0) == savedScreenID }),
           !isFreeEdge(savedEdge, for: screen),
           let freeEdge = Edge.allCases.first(where: { isFreeEdge($0, for: screen) }) {
            savedEdge = freeEdge
        }
        appState.edge = savedEdge
        setupStatusItem()
        setupTabManager()
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensDidChange),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "note.text",
                                            accessibilityDescription: "StickyNote")
        refreshMenu()
    }

    private func refreshMenu() {
        let menu = NSMenu()

        // Hide / Show toggle — Command+\
        let hidden = tabManager?.isHidden ?? false
        let toggleItem = NSMenuItem(
            title: hidden ? "Show All Notes" : "Hide All Notes",
            action: #selector(toggleHideAll),
            keyEquivalent: "\\")
        toggleItem.keyEquivalentModifierMask = [.command]
        toggleItem.target = self
        menu.addItem(toggleItem)
        menu.addItem(.separator())

        for screen in NSScreen.screens {
            let id   = screenID(for: screen)
            let name = screen.localizedName
            for edge in Edge.allCases {
                // Only show outer edges — skip edges that face an adjacent screen
                guard isFreeEdge(edge, for: screen) else { continue }
                let item = NSMenuItem(title: "\(name) — \(edge.displayName)",
                                      action: #selector(pick(_:)), keyEquivalent: "")
                item.representedObject = ["id": id, "edge": edge.rawValue] as NSDictionary
                item.target = self
                item.state  = (id == savedScreenID && edge == savedEdge) ? .on : .off
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }
        menu.addItem(NSMenuItem(title: "Quit",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    /// Returns true if this edge of the screen does NOT face another screen.
    private func isFreeEdge(_ edge: Edge, for screen: NSScreen) -> Bool {
        let tolerance: CGFloat = 2
        return !NSScreen.screens.contains { other in
            guard other != screen else { return false }
            // Check if the other screen is side-by-side (horizontal adjacency)
            let adjacent = edge == .right
                ? abs(other.frame.minX - screen.frame.maxX) < tolerance
                : abs(other.frame.maxX - screen.frame.minX) < tolerance
            // Also require vertical overlap so stacked screens aren't affected
            let vOverlap = screen.frame.minY < other.frame.maxY
                        && other.frame.minY < screen.frame.maxY
            return adjacent && vOverlap
        }
    }

    @objc private func toggleHideAll() {
        tabManager?.toggleVisibility()
        refreshMenu()
    }

    @objc private func pick(_ sender: NSMenuItem) {
        guard let info    = sender.representedObject as? NSDictionary,
              let id      = info["id"]   as? String,
              let rawEdge = info["edge"] as? String,
              let edge    = Edge(rawValue: rawEdge) else { return }
        savedScreenID = id; savedEdge = edge; appState.edge = edge
        tabManager?.attach(to: resolveScreen(), edge: edge)
        refreshMenu()
    }

    // MARK: - Tab Manager

    private func setupTabManager() {
        tabManager = NoteTabManager(screen: resolveScreen(), edge: savedEdge,
                                    noteStore: noteStore, appState: appState)
    }

    // MARK: - Helpers

    private func screenID(for screen: NSScreen) -> String {
        let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                    as? CGDirectDisplayID ?? 0
        return String(n)
    }

    private func resolveScreen() -> NSScreen {
        if let s = NSScreen.screens.first(where: { screenID(for: $0) == savedScreenID }) { return s }
        let fb = NSScreen.main ?? NSScreen.screens[0]
        savedScreenID = screenID(for: fb)
        return fb
    }

    @objc private func screensDidChange() {
        if !NSScreen.screens.contains(where: { screenID(for: $0) == savedScreenID }) {
            savedScreenID = screenID(for: NSScreen.main ?? NSScreen.screens[0])
        }
        tabManager?.attach(to: resolveScreen(), edge: savedEdge)
        refreshMenu()
    }
}
