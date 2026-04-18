import Cocoa
import SwiftUI

// MARK: - NoteTabPanel

final class NoteTabPanel: NSPanel {

    let noteID: UUID
    private var currentY: CGFloat = 0

    private let hostScreen: NSScreen
    var currentEdge: Edge
    private let TW: CGFloat
    private let defaultW: CGFloat   // 原始預設寬度
    private let defaultH: CGFloat   // 原始預設高度（縮回去時用這個）
    private var expandedW: CGFloat
    private var expandedH: CGFloat

    /// 供 NoteTabManager 排版使用的高度（永遠是預設高度，縮回去就是原始大小）
    var currentPanelHeight: CGFloat { defaultH }

    private var isExpanded    = false
    private var collapseTimer: Timer?
    private var trackingArea:  NSTrackingArea?

    init(note: Note, screen: NSScreen, edge: Edge, appState: AppState,
         W: CGFloat, H: CGFloat, TW: CGFloat, noteStore: NoteStore) {
        self.noteID      = note.id
        self.hostScreen  = screen
        self.currentEdge = edge
        self.TW = TW
        self.defaultW = W
        self.defaultH = H
        // 讀取上次儲存的尺寸，確保不小於目前預設值（舊版存的較小尺寸會自動升級）
        let savedW = UserDefaults.standard.double(forKey: "noteW_\(note.id.uuidString)")
        let savedH = UserDefaults.standard.double(forKey: "noteH_\(note.id.uuidString)")
        self.expandedW = savedW > 0 ? max(CGFloat(savedW), W) : W
        self.expandedH = savedH > 0 ? max(CGFloat(savedH), H) : H

        super.init(contentRect: .zero,
                   styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView, .resizable],
                   backing: .buffered, defer: false)
        delegate = self
        configure()

        let view = NoteTabView(noteStore: noteStore, appState: appState,
                               noteID: note.id,
                               onDelete: { [weak self] in
                                   noteStore.deleteNote(note.id)
                                   _ = self
                               },
                               onResetSize: { [weak self] in
                                   self?.resetToDefaultSize()
                               })
        install(view)
    }

    private func configure() {
        isFloatingPanel         = true
        level                   = .floating
        collectionBehavior      = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovable               = false
        isMovableByWindowBackground = false
        backgroundColor         = .clear
        isOpaque                = false
        hasShadow               = false
        hidesOnDeactivate       = false
        acceptsMouseMovedEvents = true
    }

    private func install<V: View>(_ view: V) {
        let hv = NSHostingView(rootView: view)
        hv.sizingOptions = []
        hv.wantsLayer = true
        hv.layer?.backgroundColor = .clear
        contentView = hv
        // 最小寬度要能容納 toolbar 內容（約 180px card + strip）
        minSize        = NSSize(width: TW + 180, height: 80)
        contentMinSize = NSSize(width: TW + 180, height: 80)
    }

    private func saveSize() {
        UserDefaults.standard.set(Double(expandedW), forKey: "noteW_\(noteID.uuidString)")
        UserDefaults.standard.set(Double(expandedH), forKey: "noteH_\(noteID.uuidString)")
    }

    func resetToDefaultSize() {
        guard isExpanded else { return }
        expandedW = defaultW
        expandedH = defaultH
        UserDefaults.standard.removeObject(forKey: "noteW_\(noteID.uuidString)")
        UserDefaults.standard.removeObject(forKey: "noteH_\(noteID.uuidString)")
        animate(to: expandedFrame(), curve: .easeInEaseOut)
    }

    // MARK: Positioning

    func updateY(_ y: CGFloat, animated: Bool) {
        currentY = y
        isExpanded = false
        let frame = collapsedFrame()
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.animator().setFrame(frame, display: true)
            }
        } else {
            setFrame(frame, display: true)
        }
        refreshTracking()
    }

    func setEdge(_ edge: Edge) {
        currentEdge = edge
        isExpanded  = false
    }

    // Collapsed: 只顯示 TW 寬的 strip，高度回到原始預設大小
    private func collapsedFrame() -> NSRect {
        let x = currentEdge == .right ? hostScreen.frame.maxX - TW : hostScreen.frame.minX
        return NSRect(x: x, y: currentY, width: TW, height: defaultH)
    }

    // Expanded: 使用使用者調整後儲存的寬高
    private func expandedFrame() -> NSRect {
        let x = currentEdge == .right ? hostScreen.frame.maxX - expandedW : hostScreen.frame.minX
        return NSRect(x: x, y: currentY, width: expandedW, height: expandedH)
    }

    // MARK: Hover

    private func refreshTracking() {
        if let old = trackingArea { contentView?.removeTrackingArea(old) }
        guard let cv = contentView else { return }
        let ta = NSTrackingArea(rect: cv.bounds,
                                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                owner: self, userInfo: nil)
        cv.addTrackingArea(ta); trackingArea = ta
    }

    override func mouseEntered(with event: NSEvent) {
        collapseTimer?.invalidate(); collapseTimer = nil
        guard !isExpanded else { return }
        isExpanded = true
        animate(to: expandedFrame(), curve: .easeOut) { [weak self] in
            self?.refreshTracking()
        }
    }

    override func mouseExited(with event: NSEvent) {
        if expandedFrame().contains(NSEvent.mouseLocation) { return }

        collapseTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
            guard let s = self, s.isExpanded else { return }
            if s.expandedFrame().contains(NSEvent.mouseLocation) { return }
            s.isExpanded = false
            s.animate(to: s.collapsedFrame(), curve: .easeIn) { [weak s] in
                s?.refreshTracking()
            }
        }
    }

    private func animate(to frame: NSRect, curve: CAMediaTimingFunctionName,
                         completion: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.24
            ctx.timingFunction = CAMediaTimingFunction(name: curve)
            animator().setFrame(frame, display: true)
        }, completionHandler: completion)
    }

    override var canBecomeKey:  Bool { true  }
    override var canBecomeMain: Bool { false }
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, !isKeyWindow { makeKey() }
        super.sendEvent(event)
    }
}

// MARK: - NSWindowDelegate（記住調整後的尺寸）

extension NoteTabPanel: NSWindowDelegate {
    func windowDidEndLiveResize(_ notification: Notification) {
        guard isExpanded else { return }
        expandedW = frame.width
        expandedH = frame.height
        currentY  = frame.minY  // 從上方拖拉時 Y 會改變

        // 靠牆那側永遠貼著螢幕邊緣（使用者物理上拉不到，但 snap 一下確保正確）
        let correctX: CGFloat = currentEdge == .right
            ? hostScreen.frame.maxX - expandedW
            : hostScreen.frame.minX
        if abs(frame.origin.x - correctX) > 0.5 {
            setFrame(NSRect(x: correctX, y: currentY, width: expandedW, height: expandedH),
                     display: true)
        }
        saveSize()
    }
}

// MARK: - AddNotePanel

final class AddNotePanel: NSPanel {

    private var currentY: CGFloat = 0
    private let hostScreen: NSScreen
    var currentEdge: Edge
    private let W, AH, TW: CGFloat
    private var isExpanded    = false
    private var collapseTimer: Timer?
    private var trackingArea:  NSTrackingArea?

    var onDrag: ((CGFloat, CGFloat) -> Void)?

    private var dragAnchorY: CGFloat = 0
    private var wasDragging = false
    private let dragThreshold: CGFloat = 4

    init(screen: NSScreen, edge: Edge, appState: AppState, W: CGFloat, AH: CGFloat, TW: CGFloat,
         onAdd: @escaping () -> Void) {
        self.hostScreen  = screen
        self.currentEdge = edge
        self.W = W; self.AH = AH; self.TW = TW
        super.init(contentRect: .zero,
                   styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isFloatingPanel         = true
        level                   = .floating
        collectionBehavior      = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovable               = false
        isMovableByWindowBackground = false
        backgroundColor         = .clear
        isOpaque                = false
        hasShadow               = false
        hidesOnDeactivate       = false
        acceptsMouseMovedEvents = true

        let view = AddNoteView(appState: appState, onAdd: onAdd)
        let hv = NSHostingView(rootView: view)
        hv.sizingOptions = []
        hv.wantsLayer = true
        hv.layer?.backgroundColor = .clear
        contentView = hv
        minSize        = NSSize(width: TW, height: AH)
        contentMinSize = NSSize(width: TW, height: AH)
    }

    func updateY(_ y: CGFloat, animated: Bool) {
        currentY = y
        isExpanded = false
        let frame = collapsedFrame()
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                animator().setFrame(frame, display: true)
            }
        } else {
            setFrame(frame, display: true)
        }
        refreshTracking()
    }

    func setEdge(_ edge: Edge) {
        currentEdge = edge
        isExpanded  = false
    }

    private func collapsedFrame() -> NSRect {
        let x = currentEdge == .right ? hostScreen.frame.maxX - TW : hostScreen.frame.minX
        return NSRect(x: x, y: currentY, width: TW, height: AH)
    }

    private func expandedFrame() -> NSRect {
        let x = currentEdge == .right ? hostScreen.frame.maxX - W : hostScreen.frame.minX
        return NSRect(x: x, y: currentY, width: W, height: AH)
    }

    private func refreshTracking() {
        if let old = trackingArea { contentView?.removeTrackingArea(old) }
        guard let cv = contentView else { return }
        let ta = NSTrackingArea(rect: cv.bounds,
                                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                owner: self, userInfo: nil)
        cv.addTrackingArea(ta); trackingArea = ta
    }

    override func mouseEntered(with event: NSEvent) {
        guard !wasDragging else { return }
        collapseTimer?.invalidate(); collapseTimer = nil
        guard !isExpanded else { return }
        isExpanded = true
        animate(to: expandedFrame(), curve: .easeOut) { [weak self] in self?.refreshTracking() }
    }

    override func mouseExited(with event: NSEvent) {
        let mp = NSEvent.mouseLocation
        if expandedFrame().contains(mp) { return }

        collapseTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            guard let s = self, s.isExpanded else { return }
            if s.expandedFrame().contains(NSEvent.mouseLocation) { return }
            s.isExpanded = false
            s.animate(to: s.collapsedFrame(), curve: .easeIn) { [weak s] in s?.refreshTracking() }
        }
    }

    // MARK: - Drag to reposition

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            dragAnchorY = NSEvent.mouseLocation.y
            wasDragging = false
            super.sendEvent(event)

        case .leftMouseDragged:
            let mouseY = NSEvent.mouseLocation.y
            let moved  = abs(mouseY - dragAnchorY)
            if moved > dragThreshold {
                if !wasDragging {
                    wasDragging = true
                    collapseTimer?.invalidate()
                    if isExpanded {
                        isExpanded = false
                        animate(to: collapsedFrame(), curve: .easeIn)
                    }
                }
                onDrag?(mouseY - dragAnchorY, NSEvent.mouseLocation.x)
                dragAnchorY = mouseY
            }

        case .leftMouseUp:
            if wasDragging {
                wasDragging = false
                return
            }
            super.sendEvent(event)

        default:
            super.sendEvent(event)
        }
    }

    private func animate(to frame: NSRect, curve: CAMediaTimingFunctionName,
                         completion: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.24
            ctx.timingFunction = CAMediaTimingFunction(name: curve)
            animator().setFrame(frame, display: true)
        }, completionHandler: completion)
    }

    override var canBecomeKey:  Bool { false }
    override var canBecomeMain: Bool { false }
}
