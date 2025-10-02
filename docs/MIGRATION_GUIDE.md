# Lexical Cross-Platform Migration Guide

This guide helps you migrate existing iOS-only Lexical code to take advantage of the new cross-platform (iOS + macOS) support.

## Breaking Changes

**Good news**: There are **zero breaking changes** in this release! All existing iOS code continues to work exactly as before.

- ✅ **100% Backward Compatible**: All existing iOS APIs unchanged
- ✅ **No Code Changes Required**: iOS apps can upgrade without modifications
- ✅ **Drop-in Replacement**: Simply update your Package.swift dependency

## What's New

### Platform Support
- **iOS**: 13.0+ (unchanged)
- **macOS**: 14.0+ (new!)
- **SwiftUI**: Unified API for both platforms

### New Capabilities
1. **macOS AppKit Support**: Full LexicalView implementation for macOS
2. **SwiftUI Wrapper**: Cross-platform `LexicalEditor` component
3. **Cross-Platform Plugins**: All 22+ plugins work on both iOS and macOS

## Migration Paths

### Path 1: iOS-Only App (No Changes Needed)

If you're only building for iOS, you don't need to change anything:

```swift
// Your existing iOS code continues to work exactly as before
import Lexical
import LexicalListPlugin

class ViewController: UIViewController {
  let editorConfig = EditorConfig(theme: Theme(), plugins: [ListPlugin()])
  let lexicalView = LexicalView(editorConfig: editorConfig, featureFlags: FeatureFlags())

  override func viewDidLoad() {
    super.viewDidLoad()
    view.addSubview(lexicalView)
    // ... rest of your code unchanged
  }
}
```

### Path 2: Add macOS Support to Existing App

To add macOS support while keeping your iOS code:

#### 1. Update Package.swift Platforms

```swift
// Before
platforms: [.iOS(.v13)]

// After
platforms: [.iOS(.v13), .macOS(.v14)]
```

#### 2. Use Conditional Compilation

Wrap platform-specific code:

```swift
import Lexical

#if canImport(UIKit)
import UIKit
class MyViewController: UIViewController {
  // iOS-specific code
}
#elseif canImport(AppKit)
import AppKit
class MyViewController: NSViewController {
  // macOS-specific code
}
#endif
```

#### 3. Share Editor Logic

Extract editor setup into shared code:

```swift
// Shared.swift
import Lexical
import LexicalListPlugin
import LexicalLinkPlugin

func createEditorConfig() -> EditorConfig {
  let theme = Theme()
  let plugins: [Plugin] = [
    ListPlugin(),
    LinkPlugin()
  ]
  return EditorConfig(theme: theme, plugins: plugins)
}

// iOS: ViewController.swift
#if canImport(UIKit)
import UIKit

class ViewController: UIViewController {
  let lexicalView = LexicalView(
    editorConfig: createEditorConfig(),
    featureFlags: FeatureFlags()
  )
  // ... iOS-specific UI code
}
#endif

// macOS: WindowController.swift
#if canImport(AppKit)
import AppKit

class WindowController: NSViewController {
  let lexicalView = LexicalView(
    editorConfig: createEditorConfig(),
    featureFlags: FeatureFlags()
  )
  // ... macOS-specific UI code
}
#endif
```

### Path 3: SwiftUI Cross-Platform App

The easiest path for new cross-platform apps:

```swift
import SwiftUI
import Lexical
import LexicalListPlugin

struct ContentView: View {
  @State private var text = ""

  var body: some View {
    LexicalEditor(
      editorConfig: EditorConfig(
        theme: Theme(),
        plugins: [ListPlugin()]
      ),
      text: $text
    )
    #if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    #elseif os(macOS)
    .frame(minWidth: 600, minHeight: 400)
    #endif
  }
}
```

This code compiles and runs on **both iOS and macOS** with zero changes!

## Platform Differences

### DecoratorNode Limitation

**DecoratorNode is currently iOS-only** because it uses `UIView`. macOS support would require an `NSView` equivalent.

**Workaround**: Wrap decorator-dependent code in `#if canImport(UIKit)`:

```swift
#if canImport(UIKit)
import LexicalInlineImagePlugin

let config = EditorConfig(
  theme: Theme(),
  plugins: [InlineImagePlugin()] // InlineImagePlugin uses DecoratorNode
)
#else
// macOS: use other plugins that don't require decorators
let config = EditorConfig(
  theme: Theme(),
  plugins: [ListPlugin(), LinkPlugin()]
)
#endif
```

### Platform-Specific Features

Some APIs are platform-specific:

| Feature | iOS | macOS |
|---------|-----|-------|
| Touch gestures | ✅ | ❌ |
| Mouse events | ❌ | ✅ |
| NSToolbar integration | ❌ | ✅ |
| UIActivityViewController | ✅ | ❌ |
| NSSharingService | ❌ | ✅ |

Use conditional compilation for platform-specific features.

## Testing Cross-Platform Code

### 1. Build for Both Platforms

```bash
# iOS
xcodebuild -project YourApp.xcodeproj \
  -scheme YourApp-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build

# macOS
xcodebuild -project YourApp.xcodeproj \
  -scheme YourApp-macOS \
  -destination 'platform=macOS' \
  build
```

### 2. Run Tests on Both Platforms

```bash
# iOS tests
xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace \
  -scheme Lexical-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test

# macOS tests
swift test
```

### 3. Verify in Playground Apps

The Playground project now has **two targets**:
- `LexicalPlayground` - iOS UIKit demo
- `LexicalPlaygroundMac` - macOS AppKit demo

Build and run both to verify your changes work cross-platform.

## Common Migration Patterns

### Pattern 1: Platform-Agnostic Editor Setup

```swift
import Lexical

// ✅ This works on both platforms
class EditorManager {
  let editor: Editor

  init() {
    let config = EditorConfig(theme: Theme(), plugins: [])
    self.editor = Editor(editorConfig: config, featureFlags: FeatureFlags())
  }

  func setContent(_ text: String) {
    editor.update {
      // ... editor operations work identically on both platforms
    }
  }
}
```

### Pattern 2: Platform-Specific UI, Shared Logic

```swift
// Shared business logic
class DocumentController {
  let editor: Editor

  func exportHTML() throws -> String {
    var result = ""
    try editor.read {
      result = try generateHTMLFromNodes(editor: editor, selection: nil)
    }
    return result
  }
}

// iOS UI
#if canImport(UIKit)
class iOSViewController: UIViewController {
  let controller = DocumentController()

  @IBAction func shareHTML() {
    let html = try! controller.exportHTML()
    let activityVC = UIActivityViewController(
      activityItems: [html],
      applicationActivities: nil
    )
    present(activityVC, animated: true)
  }
}
#endif

// macOS UI
#if canImport(AppKit)
class macOSViewController: NSViewController {
  let controller = DocumentController()

  @IBAction func shareHTML(_ sender: Any) {
    let html = try! controller.exportHTML()
    let picker = NSSharingServicePicker(items: [html])
    picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
  }
}
#endif
```

### Pattern 3: SwiftUI with Platform-Specific Chrome

```swift
import SwiftUI
import Lexical

struct EditorView: View {
  @State private var text = ""

  var body: some View {
    VStack {
      // ✅ Cross-platform editor
      LexicalEditor(
        editorConfig: EditorConfig(theme: Theme(), plugins: []),
        text: $text
      )

      // Platform-specific toolbar
      #if os(iOS)
      HStack {
        Button("Export") { exportIOS() }
        Button("Share") { shareIOS() }
      }
      .padding()
      #elseif os(macOS)
      // macOS uses NSToolbar instead
      EmptyView()
      #endif
    }
    #if os(macOS)
    .toolbar {
      ToolbarItem { Button("Export") { exportMacOS() } }
      ToolbarItem { Button("Share") { shareMacOS() } }
    }
    #endif
  }
}
```

## Plugin Compatibility

All plugins work on both platforms **except InlineImagePlugin** (DecoratorNode limitation):

| Plugin | iOS | macOS | Notes |
|--------|-----|-------|-------|
| ListPlugin | ✅ | ✅ | Full parity |
| LinkPlugin | ✅ | ✅ | Full parity |
| EditorHistoryPlugin | ✅ | ✅ | Full parity |
| LexicalHTML | ✅ | ✅ | Full parity |
| LexicalMarkdown | ✅ | ✅ | Full parity |
| **InlineImagePlugin** | ✅ | ⚠️ | iOS-only (uses DecoratorNode) |
| AutoLinkPlugin | ✅ | ✅ | Full parity |
| CodeHighlightPlugin | ✅ | ✅ | Full parity |
| TablePlugin | ✅ | ✅ | Full parity |
| MentionsPlugin | ✅ | ✅ | Full parity |

## Troubleshooting

### "No such module 'Lexical'" on macOS

**Cause**: Package.swift doesn't include macOS platform.

**Fix**:
```swift
platforms: [.iOS(.v13), .macOS(.v14)]
```

### InlineImagePlugin not available on macOS

**Cause**: InlineImagePlugin uses DecoratorNode which requires `UIView` (iOS-only).

**Fix**: Wrap in conditional compilation:
```swift
#if canImport(UIKit)
let plugins: [Plugin] = [ListPlugin(), InlineImagePlugin()]
#else
let plugins: [Plugin] = [ListPlugin()] // Omit InlineImagePlugin on macOS
#endif
```

### Build errors about UIKit types

**Cause**: iOS-specific code not wrapped in conditional compilation.

**Fix**:
```swift
#if canImport(UIKit)
// iOS-specific code here
#elseif canImport(AppKit)
// macOS equivalent here
#endif
```

## Additional Resources

- **Getting Started (macOS)**: `docs/MACOS_GETTING_STARTED.md`
- **Getting Started (SwiftUI)**: `docs/SWIFTUI_GETTING_STARTED.md`
- **Platform Differences**: `docs/PLATFORM_DIFFERENCES.md`
- **CI/CD Guide**: `docs/CI_CD_GUIDE.md`
- **Playground Apps**: `Playground/LexicalPlayground.xcodeproj`

## Need Help?

- Check the guides listed above
- Review the Playground apps for reference implementations
- Open an issue on GitHub with the `cross-platform` label

---

**Last Updated**: 2025-10-02
**Lexical Version**: 2.0.0
**Platforms**: iOS 13+, macOS 14+
