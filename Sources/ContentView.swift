import SwiftUI
import AppKit

// MARK: - NoteEditorState

final class NoteEditorState: ObservableObject {
    weak var textView: NSTextView?
    @Published var isBold   = false
    @Published var isItalic = false
    @Published var fontSize: CGFloat = 12

    // Keyboard shortcut callbacks — set by NoteTabView
    var onNextColor:      (() -> Void)?
    var onPrevColor:      (() -> Void)?
    var onDeleteNote:     (() -> Void)?
    var onNextTextColor:  (() -> Void)?
    var onPrevTextColor:  (() -> Void)?
    var textColorIndex = 0

    func updateFromSelection() {
        guard let tv = textView else { return }
        if let font = tv.typingAttributes[.font] as? NSFont {
            let t = NSFontManager.shared.traits(of: font)
            isBold   = t.contains(.boldFontMask)
            isItalic = t.contains(.italicFontMask)
            fontSize = font.pointSize
        }
    }

    @Published var isStrikethrough = false

    func toggleBold()   { applyTrait(.boldFontMask,   active: isBold);   isBold.toggle() }
    func toggleItalic() { applyTrait(.italicFontMask, active: isItalic); isItalic.toggle() }
    func toggleStrikethrough() {
        guard let tv = textView, let ts = tv.textStorage else { return }
        let range = tv.selectedRange()
        let newVal: Int = isStrikethrough ? 0 : NSUnderlineStyle.single.rawValue
        if range.length > 0 {
            ts.beginEditing()
            ts.addAttribute(.strikethroughStyle, value: newVal, range: range)
            ts.endEditing()
        } else {
            var a = tv.typingAttributes
            a[.strikethroughStyle] = newVal
            tv.typingAttributes = a
        }
        isStrikethrough.toggle()
    }
    func setFont(_ name: String) {
        guard let tv = textView, let ts = tv.textStorage else { return }
        let range = tv.selectedRange()
        if range.length > 0 {
            ts.beginEditing()
            ts.enumerateAttribute(.font, in: range) { v, r, _ in
                let old = v as? NSFont ?? .systemFont(ofSize: 12)
                let new = NSFont(name: name, size: old.pointSize) ?? .systemFont(ofSize: old.pointSize)
                ts.addAttribute(.font, value: new, range: r)
            }
            ts.endEditing()
        } else {
            var a = tv.typingAttributes
            let old = a[.font] as? NSFont ?? .systemFont(ofSize: 12)
            a[.font] = NSFont(name: name, size: old.pointSize) ?? .systemFont(ofSize: old.pointSize)
            tv.typingAttributes = a
        }
    }

    private func applyTrait(_ trait: NSFontTraitMask, active: Bool) {
        guard let tv = textView, let ts = tv.textStorage else { return }
        let range = tv.selectedRange()
        let xform: (NSFont) -> NSFont = {
            active ? NSFontManager.shared.convert($0, toNotHaveTrait: trait)
                   : NSFontManager.shared.convert($0, toHaveTrait:    trait)
        }
        if range.length > 0 {
            ts.beginEditing()
            ts.enumerateAttribute(.font, in: range) { v, r, _ in
                ts.addAttribute(.font, value: xform(v as? NSFont ?? .systemFont(ofSize: 12)), range: r)
            }
            ts.endEditing()
        } else {
            var a = tv.typingAttributes
            a[.font] = xform(a[.font] as? NSFont ?? .systemFont(ofSize: 12))
            tv.typingAttributes = a
        }
    }

    func setFontSize(_ size: CGFloat) {
        guard let tv = textView, let ts = tv.textStorage else { return }
        let range = tv.selectedRange()
        if range.length > 0 {
            ts.beginEditing()
            ts.enumerateAttribute(.font, in: range) { v, r, _ in
                let f = v as? NSFont ?? .systemFont(ofSize: 12)
                ts.addAttribute(.font,
                    value: NSFont(descriptor: f.fontDescriptor, size: size) ?? .systemFont(ofSize: size),
                    range: r)
            }
            ts.endEditing()
        } else {
            var a = tv.typingAttributes
            let f = a[.font] as? NSFont ?? .systemFont(ofSize: 12)
            a[.font] = NSFont(descriptor: f.fontDescriptor, size: size) ?? .systemFont(ofSize: size)
            tv.typingAttributes = a
        }
        fontSize = size
    }

    func clearFormatting() {
        guard let tv = textView, let ts = tv.textStorage else { return }
        let range = tv.selectedRange()
        let plain: [NSAttributedString.Key: Any] = [
            .font:               NSFont.systemFont(ofSize: 12),
            .foregroundColor:    NSColor(white: 0.1, alpha: 1),
            .strikethroughStyle: NSNumber(value: 0)
        ]
        if range.length > 0 {
            ts.beginEditing()
            for (key, value) in plain { ts.addAttribute(key, value: value, range: range) }
            ts.endEditing()
        } else {
            tv.typingAttributes = plain
        }
        isBold          = false
        isItalic        = false
        isStrikethrough = false
        fontSize        = 12
        textColorIndex  = 0
    }

    func setTextColor(_ color: NSColor) {
        guard let tv = textView, let ts = tv.textStorage else { return }
        let range = tv.selectedRange()
        if range.length > 0 {
            ts.beginEditing()
            ts.addAttribute(.foregroundColor, value: color, range: range)
            ts.endEditing()
        } else {
            var a = tv.typingAttributes
            a[.foregroundColor] = color
            tv.typingAttributes = a
        }
    }
}

// MARK: - RichNSTextView (custom subclass for keyboard shortcuts)

private final class RichNSTextView: NSTextView {
    weak var editorState: NoteEditorState?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key   = event.charactersIgnoringModifiers ?? ""

        switch (flags, key) {
        case ([.command], "b"):                      // ⌘B  Bold
            editorState?.toggleBold(); return true
        case ([.command], "i"):                      // ⌘I  Italic
            editorState?.toggleItalic(); return true
        case ([.command, .shift], "x"):              // ⌘⇧X Strikethrough
            editorState?.toggleStrikethrough(); return true
        case ([.command], "="), ([.command, .shift], "="):  // ⌘=  Font size +
            if let s = editorState { s.setFontSize(min(36, s.fontSize + 2)) }; return true
        case ([.command], "-"):                      // ⌘-  Font size −
            if let s = editorState { s.setFontSize(max(8,  s.fontSize - 2)) }; return true
        case ([.command], "]"):                      // ⌘]    Next note color
            editorState?.onNextColor?(); return true
        case ([.command], "["):                      // ⌘[    Prev note color
            editorState?.onPrevColor?(); return true
        case ([.command, .shift], "}"):              // ⌘⇧]  Next text color
            editorState?.onNextTextColor?(); return true
        case ([.command, .shift], "{"):              // ⌘⇧[  Prev text color
            editorState?.onPrevTextColor?(); return true
        case ([.command, .option], "c"):             // ⌘⌥C  Clear formatting
            editorState?.clearFormatting(); return true
        case ([.command], "\u{7F}"):                 // ⌘⌫   Delete note
            editorState?.onDeleteNote?(); return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }
}

// MARK: - RichTextEditor

struct RichTextEditor: NSViewRepresentable {
    @Binding var rtfData: Data
    let editorState: NoteEditorState

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        // Build text stack manually so we can use RichNSTextView
        let storage   = NSTextStorage()
        let layout    = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 0,
                                                     height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)

        let tv = RichNSTextView(frame: .zero, textContainer: container)
        tv.editorState             = editorState
        tv.delegate                = context.coordinator
        tv.isEditable              = true
        tv.isRichText              = true
        tv.allowsUndo              = true
        tv.backgroundColor         = .clear
        tv.drawsBackground         = false
        tv.textContainerInset      = NSSize(width: 10, height: 8)
        tv.typingAttributes        = [.font: NSFont.systemFont(ofSize: 12),
                                       .foregroundColor: NSColor(white: 0.1, alpha: 1)]
        tv.isVerticallyResizable   = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask        = [.width]
        tv.minSize                 = NSSize(width: 0, height: 0)
        tv.maxSize                 = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                             height: CGFloat.greatestFiniteMagnitude)
        if !rtfData.isEmpty,
           let s = try? NSAttributedString(data: rtfData,
               options: [.documentType: NSAttributedString.DocumentType.rtf],
               documentAttributes: nil) {
            tv.textStorage?.setAttributedString(s)
        }

        let sv = NSScrollView()
        sv.documentView       = tv
        sv.drawsBackground    = false
        sv.backgroundColor    = .clear
        sv.hasVerticalScroller = true
        sv.autohidesScrollers  = true

        DispatchQueue.main.async { context.coordinator.parent.editorState.textView = tv }
        return sv
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {}

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditor
        init(_ p: RichTextEditor) { parent = p }
        func textDidChange(_ n: Notification) {
            guard let tv = n.object as? NSTextView, let ts = tv.textStorage else { return }
            if let data = try? ts.data(from: NSRange(location: 0, length: ts.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
                parent.rtfData = data
            }
        }
        func textViewDidChangeSelection(_ n: Notification) { parent.editorState.updateFromSelection() }
    }
}

// MARK: - NoteTabView

struct NoteTabView: View {
    @ObservedObject var noteStore: NoteStore
    @ObservedObject var appState:  AppState
    let noteID:      UUID
    let onDelete:    () -> Void
    let onResetSize: () -> Void

    private var edge: Edge { appState.edge }

    @StateObject private var editorState = NoteEditorState()
    @State       private var rtfData: Data = Data()
    @State       private var showColorPicker = false
    @State       private var showFontPicker  = false
    @State       private var hoverHint       = ""

    // Derive colors live from noteStore so changing color updates immediately
    private var colorIndex: Int {
        noteStore.notes.first(where: { $0.id == noteID })?.colorIndex ?? 0
    }
    private var tabColor:  Color { notePalette[colorIndex % notePalette.count].tab  }
    private var cardColor: Color { notePalette[colorIndex % notePalette.count].card }

    var body: some View {
        HStack(spacing: 0) {
            if edge == .right { card; strip } else { strip; card }
        }
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: tabColor.opacity(0.45), radius: 14, x: 0, y: 2)
        .onAppear {
            rtfData = noteStore.notes.first(where: { $0.id == noteID })?.rtfData ?? Data()
            editorState.onNextColor = {
                if let i = noteStore.notes.firstIndex(where: { $0.id == noteID }) {
                    noteStore.notes[i].colorIndex =
                        (noteStore.notes[i].colorIndex + 1) % notePalette.count
                }
            }
            editorState.onPrevColor = {
                if let i = noteStore.notes.firstIndex(where: { $0.id == noteID }) {
                    let c = noteStore.notes[i].colorIndex
                    noteStore.notes[i].colorIndex = (c - 1 + notePalette.count) % notePalette.count
                }
            }
            editorState.onDeleteNote = { onDelete() }
            editorState.onNextTextColor = { [weak editorState] in
                guard let s = editorState else { return }
                s.textColorIndex = (s.textColorIndex + 1) % textColorPresets.count
                s.setTextColor(textColorPresets[s.textColorIndex])
            }
            editorState.onPrevTextColor = { [weak editorState] in
                guard let s = editorState else { return }
                let count = textColorPresets.count
                s.textColorIndex = (s.textColorIndex - 1 + count) % count
                s.setTextColor(textColorPresets[s.textColorIndex])
            }
        }
        .onChange(of: rtfData) { val in
            if let i = noteStore.notes.firstIndex(where: { $0.id == noteID }) {
                noteStore.notes[i].rtfData = val
            }
        }
    }

    // MARK: Tab strip — always visible on screen edge
    private var strip: some View {
        ZStack {
            tabColor
            // grab handle
            Capsule()
                .fill(Color.white.opacity(0.55))
                .frame(width: 5, height: 36)
        }
        .frame(width: 42)
        .shadow(color: tabColor.opacity(0.4), radius: 8, x: 0, y: 2)
    }

    // MARK: Expanded card — solid pastel background
    private var card: some View {
        ZStack {
            // Solid pastel — shows true hex colour
            cardColor
            // Subtle top highlight
            LinearGradient(
                colors: [Color.white.opacity(0.35), Color.clear],
                startPoint: .top, endPoint: .center)

            VStack(spacing: 0) {
                toolbar
                Divider().background(tabColor.opacity(0.35))
                RichTextEditor(rtfData: $rtfData, editorState: editorState)
            }
            .padding(.top, 4)
            .padding(.bottom, 6)
        }
    }

    // MARK: Toolbar  (fits inside 218px card width)
    // Layout: ● | B I S̶  Aa  − 12 +  🎨  ···  ×
    private var toolbar: some View {
        HStack(spacing: 3) {
            // Note colour dot（右牆 note 左側有圓角，需要多一點 leading padding）
            Circle().fill(tabColor)
                .frame(width: 8, height: 8)
                .shadow(color: tabColor, radius: 3)
                .padding(.leading, edge == .right ? 16 : 8)

            dividerLine

            // Bold / Italic / Strikethrough
            FmtBtn(label: "B", font: .system(size: 10, weight: .bold),
                   on: editorState.isBold, tint: tabColor) { editorState.toggleBold() }
                .onHover { hoverHint = $0 ? "Bold  ⌘B" : "" }
            FmtBtn(label: "I", font: .system(size: 10).italic(),
                   on: editorState.isItalic, tint: tabColor) { editorState.toggleItalic() }
                .onHover { hoverHint = $0 ? "Italic  ⌘I" : "" }
            StrikeBtn(on: editorState.isStrikethrough, tint: tabColor) {
                editorState.toggleStrikethrough()
            }
            .onHover { hoverHint = $0 ? "Strikethrough  ⌘⇧X" : "" }

            dividerLine

            // Font picker
            Button { showFontPicker.toggle() } label: {
                Text("Aa")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(tabColor.opacity(0.9))
                    .frame(width: 24, height: 20)
                    .background(tabColor.opacity(0.28))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showFontPicker,
                     arrowEdge: edge == .right ? .leading : .trailing) {
                FontPickerPopover(editorState: editorState)
            }
            .onHover { hoverHint = $0 ? "Font" : "" }

            dividerLine

            // Font size
            HStack(spacing: 1) {
                sizeBtn(Image(systemName: "minus"), -2)
                    .onHover { hoverHint = $0 ? "Smaller  ⌘-" : "" }
                Text("\(Int(editorState.fontSize))")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(Color(white: 0.12))
                    .frame(width: 16)
                sizeBtn(Image(systemName: "plus"), +2)
                    .onHover { hoverHint = $0 ? "Bigger  ⌘=" : "" }
            }

            dividerLine

            // Colour picker (text colours + note colour)
            Button { showColorPicker.toggle() } label: {
                Image(systemName: "paintpalette.fill")
                    .font(.system(size: 10))
                    .foregroundColor(tabColor.opacity(0.9))
                    .frame(width: 24, height: 20)
                    .background(tabColor.opacity(0.28))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showColorPicker,
                     arrowEdge: edge == .right ? .leading : .trailing) {
                CombinedColorPicker(editorState: editorState,
                                    noteStore: noteStore, noteID: noteID)
            }
            .onHover { hoverHint = $0 ? "Note ⌘] ⌘[   Text ⌘⇧] ⌘⇧[" : "" }

            // Clear formatting
            Button { editorState.clearFormatting() } label: {
                Image(systemName: "eraser")
                    .font(.system(size: 10))
                    .foregroundColor(Color(white: 0.35))
                    .frame(width: 22, height: 20)
                    .background(Color(white: 0, opacity: 0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .onHover { hoverHint = $0 ? "Clear formatting  ⌘⌥C" : "" }

            // Hint label in the spacer zone
            Text(hoverHint)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(Color(white: 0.4))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .center)
                .animation(.easeInOut(duration: 0.12), value: hoverHint)

            // Reset to default size
            Button(action: onResetSize) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Color(white: 0.35))
                    .frame(width: 18, height: 18)
                    .background(Color(white: 0, opacity: 0.10))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { hoverHint = $0 ? "Reset size" : "" }

            // Delete note
            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Color(white: 0.35))
                    .frame(width: 18, height: 18)
                    .background(Color(white: 0, opacity: 0.10))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { hoverHint = $0 ? "Delete  ⌘⌫" : "" }
            // 左牆 note 右側有圓角，× 需要更多 trailing 空間
            .padding(.trailing, edge == .left ? 18 : 8)
        }
        .frame(height: 30)
    }

    private var dividerLine: some View {
        Rectangle()
            .fill(Color(white: 0.35).opacity(0.5))
            .frame(width: 1, height: 14)
    }

    @ViewBuilder
    private func sizeBtn(_ img: Image, _ delta: CGFloat) -> some View {
        Button { editorState.setFontSize(min(36, max(8, editorState.fontSize + delta))) } label: {
            img.font(.system(size: 8, weight: .bold)).frame(width: 14, height: 20)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Combined Colour Picker Popover

struct CombinedColorPicker: View {
    let editorState: NoteEditorState
    @ObservedObject var noteStore: NoteStore
    let noteID: UUID

    private var currentNoteColor: Int {
        noteStore.notes.first(where: { $0.id == noteID })?.colorIndex ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // Text colours
            VStack(alignment: .leading, spacing: 5) {
                Label("Text Colour", systemImage: "textformat")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(white: 0.4))
                HStack(spacing: 7) {
                    ForEach(textColorPresets.indices, id: \.self) { i in
                        Button { editorState.setTextColor(textColorPresets[i]) } label: {
                            Circle()
                                .fill(Color(nsColor: textColorPresets[i]))
                                .frame(width: 22, height: 22)
                                .overlay(Circle().stroke(Color(white: 0.6), lineWidth: 0.5))
                                .shadow(color: Color(nsColor: textColorPresets[i]).opacity(0.4), radius: 3)
                        }.buttonStyle(.plain)
                    }
                }
            }

            Divider()

            // Note colours
            VStack(alignment: .leading, spacing: 5) {
                Label("Note Colour", systemImage: "note.text")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(white: 0.4))
                HStack(spacing: 7) {
                    ForEach(notePalette.indices, id: \.self) { i in
                        Button {
                            if let idx = noteStore.notes.firstIndex(where: { $0.id == noteID }) {
                                noteStore.notes[idx].colorIndex = i
                            }
                        } label: {
                            Circle()
                                .fill(notePalette[i].tab)
                                .frame(width: 22, height: 22)
                                .overlay(Circle().stroke(
                                    i == currentNoteColor ? Color(white: 0.15) : Color.clear,
                                    lineWidth: 2))
                                .shadow(color: notePalette[i].tab.opacity(0.5), radius: 3)
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
    }
}

// MARK: - Font Picker Popover

private let fontChoices: [(label: String, name: String)] = [
    ("System",    ".AppleSystemUIFont"),
    ("Helvetica", "Helvetica"),
    ("Georgia",   "Georgia"),
    ("Courier",   "Courier New"),
    ("Palatino",  "Palatino-Roman"),
    ("Futura",    "Futura-Medium"),
]

struct FontPickerPopover: View {
    let editorState: NoteEditorState
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Font")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color(white: 0.4))
                .padding(.bottom, 2)
            ForEach(fontChoices, id: \.name) { choice in
                Button {
                    let name = choice.name == ".AppleSystemUIFont"
                        ? NSFont.systemFont(ofSize: 12).fontName
                        : choice.name
                    editorState.setFont(name)
                } label: {
                    Text(choice.label)
                        .font(choice.name == ".AppleSystemUIFont"
                              ? .system(size: 13)
                              : .custom(choice.name, size: 13))
                        .foregroundColor(Color(white: 0.15))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 6)
                        .background(Color(white: 0, opacity: 0.0))
                }
                .buttonStyle(.plain)
                .background(Color(white: 0.95))
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
        }
        .padding(10)
        .frame(width: 140)
    }
}

// MARK: - AddNoteView

struct AddNoteView: View {
    @ObservedObject var appState: AppState
    let onAdd: () -> Void
    @State private var hovered = false
    private let addColor = Color(hex: "caffbf")

    private var edge: Edge { appState.edge }

    var body: some View {
        HStack(spacing: 0) {
            if edge == .right { addCard; addStrip } else { addStrip; addCard }
        }
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: addColor.opacity(0.45), radius: 10, x: 0, y: 2)
    }

    private var addStrip: some View {
        ZStack {
            addColor
            ZStack {
                Circle()
                    .strokeBorder(Color.white.opacity(0.6), lineWidth: 1.5)
                    .frame(width: 26, height: 26)
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .frame(width: 42)
        .shadow(color: addColor.opacity(0.5), radius: 6, x: edge == .right ? -3 : 3, y: 0)
        .help("Drag to reposition all notes")
    }

    private var addCard: some View {
        Button(action: onAdd) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(hovered ? addColor : addColor.opacity(0.25))
                        .frame(width: 26, height: 26)
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(hovered ? Color(white: 0.15) : Color(white: 0.35))
                }
                .animation(.easeInOut(duration: 0.14), value: hovered)

                Text("New Note")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(hovered ? Color(white: 0.1) : Color(white: 0.35))
                    .animation(.easeInOut(duration: 0.14), value: hovered)

                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                Color.white.opacity(hovered ? 0.92 : 0.72)
                    .animation(.easeInOut(duration: 0.14), value: hovered)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .frame(height: 44)
    }
}

// MARK: - Strikethrough Button (custom label since Font has no .strikethrough)

private struct StrikeBtn: View {
    let on:     Bool
    let tint:   Color
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack {
                Text("S")
                    .font(.system(size: 10))
                    .foregroundColor(on ? .white : Color(white: 0.12))
                Rectangle()
                    .fill(on ? Color.white : Color(white: 0.12))
                    .frame(width: 10, height: 1)
            }
            .frame(width: 22, height: 20)
            .background(on ? tint : tint.opacity(0.28))
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }.buttonStyle(.plain)
    }
}

// MARK: - Toolbar Button

private struct FmtBtn: View {
    let label:  String
    let font:   Font
    let on:     Bool
    let tint:   Color
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label).font(font)
                .foregroundColor(on ? .white : Color(white: 0.12))
                .frame(width: 22, height: 20)
                .background(on ? tint : tint.opacity(0.28))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }.buttonStyle(.plain)
    }
}

// MARK: - Text Colour Presets

private let textColorPresets: [NSColor] = [
    NSColor(white: 0.08, alpha: 1),
    NSColor(white: 1.00, alpha: 1),
    NSColor(r: 200, g: 50,  b: 90),
    NSColor(r: 28,  g: 100, b: 188),
    NSColor(r: 18,  g: 128, b: 108),
    NSColor(r: 105, g: 50,  b: 160),
]

// MARK: - Visual Effect Blur (kept for subtle use)

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.blendingMode = .behindWindow; v.state = .active; v.material = material
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = material }
}

// MARK: - Interior Rounded Shape

struct InteriorRoundedShape: Shape {
    let edge: Edge; let radius: CGFloat
    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.width / 2, rect.height / 2)
        var p = Path()
        switch edge {
        case .right:
            p.move(to:    .init(x: rect.minX + r, y: rect.minY))
            p.addLine(to: .init(x: rect.maxX,     y: rect.minY))
            p.addLine(to: .init(x: rect.maxX,     y: rect.maxY))
            p.addLine(to: .init(x: rect.minX + r, y: rect.maxY))
            p.addArc(center: .init(x: rect.minX + r, y: rect.maxY - r), radius: r,
                     startAngle: .degrees(90),  endAngle: .degrees(180), clockwise: false)
            p.addLine(to: .init(x: rect.minX, y: rect.minY + r))
            p.addArc(center: .init(x: rect.minX + r, y: rect.minY + r), radius: r,
                     startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        case .left:
            p.move(to:    .init(x: rect.minX,     y: rect.minY))
            p.addLine(to: .init(x: rect.maxX - r, y: rect.minY))
            p.addArc(center: .init(x: rect.maxX - r, y: rect.minY + r), radius: r,
                     startAngle: .degrees(270), endAngle: .degrees(0),   clockwise: false)
            p.addLine(to: .init(x: rect.maxX, y: rect.maxY - r))
            p.addArc(center: .init(x: rect.maxX - r, y: rect.maxY - r), radius: r,
                     startAngle: .degrees(0),   endAngle: .degrees(90),  clockwise: false)
            p.addLine(to: .init(x: rect.minX, y: rect.maxY))
        }
        p.closeSubpath(); return p
    }
}
