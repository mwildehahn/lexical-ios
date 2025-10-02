# Getting Started with Lexical on macOS

This guide shows you how to integrate Lexical into your macOS application using AppKit.

## Requirements

- macOS 14.0 or later
- Xcode 15.0 or later
- Swift 5.9 or later

## Installation

### Swift Package Manager

Add Lexical to your macOS app by adding it as a Swift Package dependency:

1. In Xcode, select **File → Add Package Dependencies...**
2. Enter the repository URL: `https://github.com/facebook/lexical-ios`
3. Select the version or branch you want to use
4. Click **Add Package**

Or add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/facebook/lexical-ios", from: "0.1.0")
]
```

## Basic Usage

### Creating a LexicalView

The main component for macOS is `LexicalView`, an `NSView` subclass that provides a rich text editor:

```swift
import Cocoa
import Lexical

class ViewController: NSViewController {
  private var lexicalView: LexicalView!

  override func viewDidLoad() {
    super.viewDidLoad()

    // Create editor configuration
    let theme = Theme()
    let config = EditorConfig(theme: theme, plugins: [])
    let featureFlags = FeatureFlags()

    // Initialize LexicalView
    lexicalView = LexicalView(editorConfig: config, featureFlags: featureFlags)
    lexicalView.translatesAutoresizingMaskIntoConstraints = false

    // Add to view hierarchy
    view.addSubview(lexicalView)

    // Set up constraints
    NSLayoutConstraint.activate([
      lexicalView.topAnchor.constraint(equalTo: view.topAnchor),
      lexicalView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      lexicalView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      lexicalView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
    ])
  }
}
```

### Accessing the Editor

To programmatically work with the editor content, access the `Editor` instance:

```swift
// Get the editor from LexicalView
guard let editor = lexicalView.editor else { return }

// Perform updates
try? editor.update {
  guard let root = getRoot() else { return }

  let paragraph = createParagraphNode()
  let text = createTextNode(text: "Hello, macOS!")
  try paragraph.append([text])
  try root.append([paragraph])
}

// Read content
try? editor.read {
  let text = getRoot()?.getTextContent() ?? ""
  print("Editor content: \(text)")
}
```

## Using Plugins

Lexical has a modular plugin architecture. Here's how to add plugins to your macOS app:

### List Plugin

```swift
import Lexical
import LexicalListPlugin

let theme = Theme()
let plugins: [Plugin] = [
  ListPlugin()
]

let config = EditorConfig(theme: theme, plugins: plugins)
let lexicalView = LexicalView(editorConfig: config, featureFlags: FeatureFlags())
```

### Link Plugin

```swift
import Lexical
import LexicalLinkPlugin

let plugins: [Plugin] = [
  LinkPlugin()
]

let config = EditorConfig(theme: theme, plugins: plugins)
```

### HTML Plugin

Export and import HTML content:

```swift
import Lexical
import LexicalHTML

// Export to HTML
try? editor.read {
  let html = try HTMLGenerator.generateHtmlFromNodes(editor: editor, selection: nil)
  print("HTML: \(html)")
}

// Import from HTML
let htmlString = "<p>Hello, <strong>world</strong>!</p>"
try? editor.update {
  try HTMLParser.parseHTMLString(htmlString, editor: editor)
}
```

## Platform Differences

### What Works on macOS

- ✅ Core editor functionality (text editing, selection, undo/redo)
- ✅ All node types (TextNode, ParagraphNode, HeadingNode, QuoteNode, etc.)
- ✅ Plugins (List, Link, History)
- ✅ HTML and Markdown export/import
- ✅ Themes and styling
- ✅ Editor state management

### Current Limitations

- ❌ **DecoratorNodes**: Not yet supported on macOS (requires NSView implementation)
  - InlineImagePlugin is iOS-only
  - Custom decorator nodes need NSView-based implementation

## Example: Complete Window Controller

```swift
import Cocoa
import Lexical
import LexicalListPlugin
import LexicalLinkPlugin

class EditorWindowController: NSWindowController {

  private var lexicalView: LexicalView!

  convenience init() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.center()
    window.title = "Lexical Editor"

    self.init(window: window)
    setupEditor()
  }

  private func setupEditor() {
    guard let contentView = window?.contentView else { return }

    // Configure editor
    let theme = Theme()
    let plugins: [Plugin] = [
      ListPlugin(),
      LinkPlugin()
    ]
    let config = EditorConfig(theme: theme, plugins: plugins)

    // Create LexicalView
    lexicalView = LexicalView(editorConfig: config, featureFlags: FeatureFlags())
    lexicalView.translatesAutoresizingMaskIntoConstraints = false

    contentView.addSubview(lexicalView)

    NSLayoutConstraint.activate([
      lexicalView.topAnchor.constraint(equalTo: contentView.topAnchor),
      lexicalView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      lexicalView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      lexicalView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
    ])
  }
}
```

## Next Steps

- Check out the [macOS Playground app](../TestApp/LexicalMacOSTest) for a complete example
- See [PLATFORM_DIFFERENCES.md](PLATFORM_DIFFERENCES.md) for detailed platform-specific information
- For SwiftUI integration, see [SWIFTUI_GETTING_STARTED.md](SWIFTUI_GETTING_STARTED.md)
- Explore the [full API documentation](https://facebook.github.io/lexical-ios/documentation/lexical/)
