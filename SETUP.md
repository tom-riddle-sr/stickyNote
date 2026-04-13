# StickyNote — Xcode Setup Guide

## 1. Create the Xcode Project

1. Open Xcode → **File > New > Project**
2. Choose **macOS → App**
3. Set:
   - Product Name: `StickyNote`
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Uncheck "Include Tests"
4. Save anywhere (you'll replace the source files next)

## 2. Add the Source Files

Delete Xcode's generated `ContentView.swift` and `StickyNoteApp.swift`.

Drag all four files from `Sources/` into your Xcode project:
- `StickyNoteApp.swift`
- `AppDelegate.swift`
- `StickyNotePanel.swift`
- `ContentView.swift`

Make sure **"Copy items if needed"** is checked.

## 3. Set Deployment Target

In the project settings → **General → Minimum Deployments**:
- Set macOS to **13.0** (required for `scrollContentBackground`)

## 4. Hide the Dock Icon (LSUIElement)

Open `Info.plist` (or your target's **Info** tab in Xcode) and add:

| Key                          | Type    | Value |
|------------------------------|---------|-------|
| `Application is agent (UIElement)` | Boolean | YES   |

In raw XML (`Info.plist`):
```xml
<key>LSUIElement</key>
<true/>
```

## 5. Build & Run

Press **⌘R**. The app will:
- Appear as a menu bar icon (note icon) — **no Dock icon**.
- Show a 10 px yellow tab on the right edge of your main screen.
- **Hover** over the tab → slides open (260 px).
- **Mouse away** → collapses back after ~0.35 s.
- Click the **menu bar icon** to pick a different screen or edge.
- Notes are **auto-saved** via `AppStorage` (UserDefaults).

## Architecture Overview

```
StickyNoteApp      @main entry; hosts NSApplicationDelegateAdaptor
AppDelegate        NSStatusItem menu + panel lifecycle
StickyNotePanel    NSPanel subclass; hover detection + spring animation
ContentView        SwiftUI TextEditor inside a shaped, colored container
AppState           ObservableObject shared between panel and view
```

## Customisation Tips

| What                  | Where                               |
|-----------------------|-------------------------------------|
| Panel width           | `expandedWidth` in `StickyNotePanel` |
| Panel height          | `panelHeight` in `StickyNotePanel`   |
| Tab width             | `tabWidth` in `StickyNotePanel`      |
| Collapse delay        | `collapseDelay` in `StickyNotePanel` |
| Note background color | `bgColor` in `ContentView`           |
| Corner radius         | `radius` passed to `InteriorRoundedShape` |
