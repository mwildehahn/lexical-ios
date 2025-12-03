# Lexical Demo Apps

This directory contains demo applications showcasing Lexical on different platforms.

## Demo Apps

### LexicalDemoMac (macOS AppKit)

A native macOS application using AppKit and `LexicalAppKit.LexicalView`.

**Features:**
- Rich text editing with formatting toolbar
- Bold, italic, underline formatting
- Bullet and numbered lists
- Undo/redo support

**Run:**
```bash
swift run LexicalDemoMac
```

### LexicalDemoSwiftUI (SwiftUI)

A cross-platform SwiftUI application that works on macOS and iOS.

**Features:**
- SwiftUI wrapper around Lexical editor
- Same formatting features as AppKit demo
- Cross-platform compatible

**Run (macOS):**
```bash
swift run LexicalDemoSwiftUI
```

## Building

Both demo apps are included as executable targets in the main Package.swift.

```bash
# Build all
swift build

# Build specific demo
swift build --target LexicalDemoMac
swift build --target LexicalDemoSwiftUI
```

## Opening in Xcode

1. Open the lexical-ios package in Xcode:
   ```bash
   open Package.swift
   ```

2. Select the demo target from the scheme dropdown:
   - `LexicalDemoMac` for the AppKit demo
   - `LexicalDemoSwiftUI` for the SwiftUI demo

3. Run with Cmd+R

## Structure

```
Examples/
├── README.md                    # This file
├── LexicalDemo/                 # macOS AppKit demo
│   ├── Mac/
│   │   ├── AppDelegate.swift    # App entry point
│   │   └── ViewController.swift # Main view controller
│   ├── Assets.xcassets/         # App icons
│   ├── Info.plist               # App metadata
│   └── LexicalDemo.entitlements # Sandbox entitlements
└── LexicalDemo.SwiftUI/         # SwiftUI demo
    ├── LexicalDemoApp.swift     # SwiftUI app entry point
    ├── ContentView.swift        # Main content view
    ├── Assets.xcassets/         # App icons
    ├── Info.plist               # App metadata
    └── LexicalDemo.SwiftUI.entitlements
```
