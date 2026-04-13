import SwiftUI
import AppKit

// MARK: - NoteEditorState

final class NoteEditorState: ObservableObject {
    weak var textView: NSTextView?
    @Published var isBold   = false
    @Published var isItalic = false
    @Published var fontSize: CGFloat = 12

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

// MARK: - RichTextEditor

struct RichTextEditor: NSViewRepresentable {
    @Binding var rtfData: Data
    let editorState: NoteEditorState

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let sv = NSTextView.scrollableTextView()
        guard let tv = sv.documentView as? NSTextView else { return sv }
        tv.delegate           = context.coordinator
        tv.isEditable         = true
        tv.isRichText         = true
        tv.allowsUndo         = true
        tv.backgroundColor    = .clear
        tv.drawsBackground    = false
        tv.textContainerInset = NSSize(width: 10, height: 8)
        tv.typingAttributes   = [.font: NSFont.systemFont(ofSize: 12),
                                  .foregroundColor: NSColor(white: 0.1, alpha: 1)]
        if !rtfData.isEmpty,
           let s = try? NSAttributedString(data: rtfData,
               options: [.documentType: NSAttributedString.DocumentType.rtf],
               documentAttributes: nil) {
            tv.textStorage?.setAttributedString(s)
        }
        sv.drawsBackground    = false
        sv.backgroundColor    = .clear
        sv.hasVerticalScroller = true
        sv.autohidesScrollers = true
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
        .clipShape(InteriorRoundedShape(edge: edge, radius: 12))
        .shadow(color: tabColor.opacity(0.5), radius: 14,
                x: edge == .right ? -6 : 6, y: 0)
        .onAppear {
            rtfData = noteStore.notes.first(where: { $0.id == noteID })?.rtfData ?? Data()
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
        .shadow(color: tabColor.opacity(0.55),
                radius: 8, x: edge == .right ? -4 : 4, y: 0)
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
            .padding(edge == .right ? .leading : .trailing, 12)
        }
    }

    // MARK: Toolbar  (fits inside 218px card width)
    // Layout: ● | B I S̶  Aa  − 12 +  🎨  ···  ×
    private var toolbar: some View {
        HStack(spacing: 3) {
            // Note colour dot
            Circle().fill(tabColor)
                .frame(width: 8, height: 8)
                .shadow(color: tabColor, radius: 3)
                .padding(.leading, 8)

            dividerLine

            // Bold / Italic / Strikethrough
            FmtBtn(label: "B", font: .system(size: 10, weight: .bold),
                   on: editorState.isBold, tint: tabColor) { editorState.toggleBold() }
            FmtBtn(label: "I", font: .system(size: 10).italic(),
                   on: editorState.isItalic, tint: tabColor) { editorState.toggleItalic() }
            StrikeBtn(on: editorState.isStrikethrough, tint: tabColor) {
                editorState.toggleStrikethrough()
            }

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

            dividerLine

            // Font size
            HStack(spacing: 1) {
                sizeBtn(Image(systemName: "minus"), -2)
                Text("\(Int(editorState.fontSize))")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(Color(white: 0.12))
                    .frame(width: 16)
                sizeBtn(Image(systemName: "plus"), +2)
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

            Spacer(minLength: 0)

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
            .help("恢復初始大小")

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
            .padding(.trailing, 14)
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
        }.buttonStyle(.plain)
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
        .clipShape(InteriorRoundedShape(edge: edge, radius: 8))
        .shadow(color: addColor.opacity(0.45), radius: 8, x: edge == .right ? -4 : 4, y: 0)
    }

    private var addStrip: some View {
        ZStack {
            addColor
            // Drag handle — three dots
            VStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { _ in
                    Capsule()
                        .fill(Color.white.opacity(0.65))
                        .frame(width: 16, height: 3)
                }
            }
        }
        .frame(width: 42)
        .shadow(color: addColor.opacity(0.5), radius: 6, x: edge == .right ? -3 : 3, y: 0)
        .help("Drag to reposition all notes")
    }

    private var addCard: some View {
        Button(action: onAdd) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(white: 0.25))
                Text("New Note")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(white: 0.3))
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(maxHeight: .infinity)
            .background(
                ZStack {
                    addColor
                    Color.white.opacity(hovered ? 0.0 : 0.25)
                }
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
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
