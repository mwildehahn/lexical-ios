# macOS Testing Guide for Lexical

This guide provides instructions for creating a minimal macOS test app to verify Lexical's macOS functionality.

## Quick Start: Create a macOS Test App

### Option 1: SwiftUI App (Recommended)

1. **Create New macOS App in Xcode**
   - File → New → Project
   - macOS → App
   - Name: "LexicalMacOSTest"
   - Interface: SwiftUI
   - Language: Swift
   - Minimum Deployment: macOS 14.0

2. **Add Lexical Package Dependency**
   - File → Add Package Dependencies
   - Enter local path: `/path/to/lexical-ios`
   - Or use Git URL if published
   - Select: Lexical

3. **Create ContentView with LexicalView Wrapper**

```swift
import SwiftUI
import Lexical

struct ContentView: View {
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("Lexical macOS Test")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            // Editor
            LexicalViewWrapper()
                .frame(minWidth: 600, minHeight: 400)
        }
    }
}

struct LexicalViewWrapper: NSViewRepresentable {
    func makeNSView(context: Context) -> LexicalView {
        // Create theme
        let theme = Theme()

        // Create editor config
        let editorConfig = EditorConfig(theme: theme, plugins: [])

        // Create feature flags
        let featureFlags = FeatureFlags()

        // Create placeholder
        let placeholder = LexicalPlaceholderText(
            text: "Start typing...",
            font: NSFont.systemFont(ofSize: 14),
            color: NSColor.placeholderTextColor
        )

        // Create LexicalView
        let lexicalView = LexicalView(
            editorConfig: editorConfig,
            featureFlags: featureFlags,
            placeholderText: placeholder
        )

        // Set initial content
        do {
            try lexicalView.editor.update {
                guard let root = getRoot() else { return }
                let paragraph = ParagraphNode()
                let text = TextNode(text: "Welcome to Lexical on macOS!")
                try paragraph.append([text])
                try root.append([paragraph])
            }
        } catch {
            print("Error setting initial content: \(error)")
        }

        return lexicalView
    }

    func updateNSView(_ nsView: LexicalView, context: Context) {
        // No updates needed
    }
}
```

### Option 2: Pure AppKit App

1. **Create New macOS App in Xcode**
   - macOS → App
   - Interface: AppKit (Storyboard)
   - Minimum Deployment: macOS 14.0

2. **In AppDelegate or WindowController:**

```swift
import Cocoa
import Lexical

class ViewController: NSViewController {
    var lexicalView: LexicalView!

    override func viewDidLoad() {
        super.viewDidLoad()

        // Create editor config
        let theme = Theme()
        let editorConfig = EditorConfig(theme: theme, plugins: [])
        let featureFlags = FeatureFlags()

        let placeholder = LexicalPlaceholderText(
            text: "Start typing...",
            font: NSFont.systemFont(ofSize: 14),
            color: NSColor.placeholderTextColor
        )

        // Create LexicalView
        lexicalView = LexicalView(
            editorConfig: editorConfig,
            featureFlags: featureFlags,
            placeholderText: placeholder
        )

        // Add to view hierarchy
        view.addSubview(lexicalView)
        lexicalView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            lexicalView.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            lexicalView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            lexicalView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            lexicalView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20)
        ])

        // Set initial content
        do {
            try lexicalView.editor.update {
                guard let root = getRoot() else { return }
                let paragraph = ParagraphNode()
                let text = TextNode(text: "Welcome to Lexical on macOS!")
                try paragraph.append([text])
                try root.append([paragraph])
            }
        } catch {
            print("Error: \(error)")
        }
    }
}
```

## What to Test

### Basic Functionality
- ✅ **Typing**: Type regular text
- ✅ **Selection**: Click and drag to select text
- ✅ **Delete**: Backspace and Forward Delete keys
- ✅ **Copy/Paste**: Cmd+C, Cmd+X, Cmd+V
- ✅ **Undo/Redo**: Should work via system (Edit menu)

### Formatting (if RichTextPlugin added)
- ✅ **Bold**: Cmd+B
- ✅ **Italic**: Cmd+I
- ✅ **Underline**: Cmd+U

### Advanced Features
- ✅ **IME Input**: Test with Japanese/Chinese keyboard
- ✅ **Multi-line**: Press Return/Enter
- ✅ **Line Break**: Shift+Return
- ✅ **Placeholder**: Shows when empty

### Plugins to Test (add to editorConfig)

```swift
import LexicalListPlugin
import LexicalLinkPlugin

let plugins: [Plugin] = [
    ListPlugin(),
    LinkPlugin()
]
```

## Common Issues and Solutions

### Issue: LexicalView not found
**Solution**: Make sure you've added the Lexical package dependency and imported `Lexical`

### Issue: Placeholder doesn't show
**Solution**: Call `lexicalView.showPlaceholderText()` after setup

### Issue: Can't type
**Solution**: Make sure the LexicalView has proper first responder setup:
```swift
_ = lexicalView.textViewBecomeFirstResponder()
```

### Issue: Keyboard shortcuts not working
**Solution**: Ensure the app has proper menu items or the view is handling keyDown events

## Adding More Plugins

### Lists
```swift
import LexicalListPlugin

let plugins: [Plugin] = [
    ListPlugin()
]

// After setup, add list:
try lexicalView.editor.update {
    // Use ListPlugin commands
}
```

### Links
```swift
import LexicalLinkPlugin

let plugins: [Plugin] = [
    LinkPlugin()
]
```

### Images
```swift
import LexicalInlineImagePlugin

let plugins: [Plugin] = [
    InlineImagePlugin()
]
```

## Performance Testing

Monitor these metrics:
- Typing latency (should feel instant)
- Selection performance (no lag on drag)
- Large document handling (1000+ lines)
- Memory usage during editing

## Debugging Tips

Enable verbose logging:
```swift
let featureFlags = FeatureFlags(verboseLogging: true)
```

Check console output for:
- `🔥` prefixed debug messages
- Error messages from TextView
- Selection change notifications

## Next Steps After Testing

1. ✅ Verify basic functionality works
2. Add more plugins and test
3. Test with real-world content
4. Profile performance
5. Add unit tests for macOS-specific code

## Reporting Issues

If you find issues:
1. Check console logs
2. Verify with minimal reproduction case
3. Test same code on iOS (does it work there?)
4. Report with exact steps to reproduce
