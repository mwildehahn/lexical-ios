# Platform Differences: iOS vs macOS

This document details the differences between Lexical's iOS and macOS implementations, helping you write cross-platform code and understand platform-specific limitations.

## Architecture Overview

Lexical uses a **single codebase** for both iOS and macOS, with platform-specific code conditionally compiled using:

- `#if canImport(UIKit)` - iOS-specific code
- `#if canImport(AppKit)` - macOS-specific code
- `#if os(iOS)` / `#if os(macOS)` - Alternative conditional compilation

The core architecture remains the same on both platforms, with platform abstractions for view and text rendering.

## Core Components

### Editor

✅ **Fully Cross-Platform**

The `Editor` class works identically on both platforms:

```swift
let editor = Editor()

// Same API on iOS and macOS
try editor.update {
  guard let root = getRoot() else { return }
  let paragraph = createParagraphNode()
  let text = createTextNode(text: "Hello, World!")
  try paragraph.append([text])
  try root.append([paragraph])
}
```

### LexicalView

✅ **Cross-Platform with Platform-Specific Inheritance**

- **iOS**: `LexicalView` inherits from `UIView`
- **macOS**: `LexicalView` inherits from `NSView`

The public API is identical:

```swift
let config = EditorConfig(theme: Theme(), plugins: [])
let featureFlags = FeatureFlags()
let lexicalView = LexicalView(editorConfig: config, featureFlags: featureFlags)
```

### Text Storage and Layout

✅ **Cross-Platform (TextKit Foundation)**

Both platforms use Apple's TextKit for text rendering:

- `NSTextStorage` - Shared
- `NSLayoutManager` - Shared
- `NSTextContainer` - Shared

Platform-specific text views:
- **iOS**: `UITextView` (internal)
- **macOS**: `NSTextView` (internal)

## Node Types

### Text Nodes

✅ **Fully Cross-Platform**

All text node types work identically:

- `TextNode`
- `ParagraphNode`
- `HeadingNode`
- `QuoteNode`
- `CodeNode`
- `LinkNode`
- `ListNode` / `ListItemNode`

```swift
// Same code works on both platforms
let text = createTextNode(text: "Hello")
let bold = createTextNode(text: "Bold").setBold(true)
let heading = HeadingNode(tag: .h1)
```

### DecoratorNodes

❌ **iOS-Only (UIView-based)**

`DecoratorNode` currently only works on iOS because it requires `UIView`:

```swift
#if canImport(UIKit)
import UIKit

class ImageNode: DecoratorNode {
  override public func createView() -> UIView {
    // iOS-only: returns UIView
    return UIImageView()
  }
}
#endif
```

**Future macOS Support**: DecoratorNodes will need `NSView`-based implementations for macOS.

### DecoratorBlockNodes

❌ **iOS-Only (UIView-based)**

Block-level decorators are also iOS-only:

```swift
#if canImport(UIKit)
class CustomBlockNode: DecoratorBlockNode {
  override public func createView() -> UIView {
    // iOS-only
  }
}
#endif
```

## Plugins

### Fully Cross-Platform Plugins

These plugins work on both iOS and macOS:

| Plugin | iOS | macOS | Notes |
|--------|-----|-------|-------|
| **ListPlugin** | ✅ | ✅ | Bullet and numbered lists |
| **LinkPlugin** | ✅ | ✅ | Hyperlink support |
| **EditorHistoryPlugin** | ✅ | ✅ | Undo/redo |
| **LexicalHTML** | ✅ | ✅ | HTML import/export |
| **LexicalMarkdown** | ✅ | ✅ | Markdown import/export |

### iOS-Only Plugins

| Plugin | iOS | macOS | Reason |
|--------|-----|-------|--------|
| **InlineImagePlugin** | ✅ | ❌ | Uses UIView-based DecoratorNode |

## Feature Flags

✅ **Fully Cross-Platform**

All `FeatureFlags` work on both platforms:

```swift
let flags = FeatureFlags(
  useOptimizedReconciler: true,
  useReconcilerFenwickDelta: true,
  useReconcilerKeyedDiff: true,
  useReconcilerBlockRebuild: true
)
```

## Themes

✅ **Cross-Platform with Platform Type Aliases**

Themes work on both platforms using type aliases:

```swift
#if canImport(UIKit)
typealias PlatformFont = UIFont
typealias PlatformColor = UIColor
#elseif canImport(AppKit)
typealias PlatformFont = NSFont
typealias PlatformColor = NSColor
#endif

var theme = Theme()
theme.paragraph = [
  .font: PlatformFont.systemFont(ofSize: 16),
  .foregroundColor: PlatformColor.label
]
```

## Selection and Commands

✅ **Fully Cross-Platform**

Selection handling works the same way:

```swift
// Same API on both platforms
try editor.update {
  if let selection = getSelection() as? RangeSelection {
    try selection.insertNodes(nodes: [createTextNode(text: "Insert")])
  }
}
```

## Input Handling

⚠️ **Platform-Specific Internals**

While the public API is the same, internal input handling differs:

### iOS
- Uses `UITextViewDelegate`
- Touch-based selection
- Software keyboard handling

### macOS
- Uses `NSTextViewDelegate`
- Mouse/trackpad selection
- Hardware keyboard handling

**For Users**: These differences are abstracted away - you don't need to handle them.

## Testing

### Cross-Platform Tests

Most tests run on both platforms:

```swift
@testable import Lexical
import XCTest

class NodeTests: XCTestCase {
  func testTextNode() {
    // Runs on both iOS and macOS
    let text = createTextNode(text: "Test")
    XCTAssertEqual(text.getTextContent(), "Test")
  }
}
```

### Platform-Specific Tests

Tests using UIKit/AppKit APIs are wrapped:

```swift
#if canImport(UIKit)
import UIKit

class DecoratorTests: XCTestCase {
  // iOS-only tests for decorator nodes
}
#endif
```

```swift
#if canImport(AppKit)
import AppKit

class MacOSFrontendTests: XCTestCase {
  // macOS-specific tests
}
#endif
```

## SwiftUI Integration

✅ **Cross-Platform**

The `LexicalEditor` SwiftUI view works on both platforms:

```swift
import SwiftUI
import Lexical

struct ContentView: View {
    @State private var text: String = ""

    var body: some View {
        LexicalEditor(
            editorConfig: EditorConfig(theme: Theme(), plugins: []),
            featureFlags: FeatureFlags(),
            placeholderText: "Start typing...",
            text: $text
        )
    }
}
```

Internally, it uses:
- `UIViewRepresentable` on iOS
- `NSViewRepresentable` on macOS

## Build Commands

### iOS

```bash
# Build for iOS Simulator
xcodebuild -project Playground/LexicalPlayground.xcodeproj \
  -scheme LexicalPlayground -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' build

# Run iOS tests
xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace \
  -scheme Lexical-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' test
```

### macOS

```bash
# Build for macOS
xcodebuild -workspace TestApp/LexicalMacOSTest.xcworkspace \
  -scheme LexicalMacOSTest -destination 'platform=macOS' build

# Run macOS tests
swift test
```

## API Availability

### Minimum Deployment Targets

- **iOS**: 13.0+
- **macOS**: 14.0+

### Using @available

When writing cross-platform code that uses newer APIs:

```swift
if #available(iOS 15.0, macOS 14.0, *) {
  // Use newer API
} else {
  // Fallback
}
```

## Common Pitfalls

### 1. Assuming UIKit/AppKit APIs

❌ **Wrong**:
```swift
func setupView() {
  let view = UIView() // Breaks on macOS
}
```

✅ **Correct**:
```swift
#if canImport(UIKit)
import UIKit
typealias PlatformView = UIView
#elseif canImport(AppKit)
import AppKit
typealias PlatformView = NSView
#endif

func setupView() {
  let view = PlatformView()
}
```

### 2. Hardcoding Colors/Fonts

❌ **Wrong**:
```swift
let color = UIColor.systemBlue // Breaks on macOS
```

✅ **Correct**:
```swift
#if canImport(UIKit)
typealias PlatformColor = UIColor
#elseif canImport(AppKit)
typealias PlatformColor = NSColor
#endif

let color = PlatformColor.systemBlue
```

### 3. Using DecoratorNodes Without Checks

❌ **Wrong**:
```swift
class MyNode: DecoratorNode {
  override public func createView() -> UIView {
    // Breaks on macOS
  }
}
```

✅ **Correct**:
```swift
#if canImport(UIKit)
import UIKit

class MyNode: DecoratorNode {
  override public func createView() -> UIView {
    // iOS-only
  }
}
#endif
```

## Best Practices

### 1. Write Cross-Platform Code by Default

Prefer APIs that work on both platforms:

```swift
// Good - works everywhere
let text = createTextNode(text: "Hello")
let paragraph = createParagraphNode()
try paragraph.append([text])
```

### 2. Use Type Aliases for Platform Types

```swift
#if canImport(UIKit)
typealias PlatformView = UIView
typealias PlatformColor = UIColor
typealias PlatformFont = UIFont
#elseif canImport(AppKit)
typealias PlatformView = NSView
typealias PlatformColor = NSColor
typealias PlatformFont = NSFont
#endif
```

### 3. Test on Both Platforms

Always verify your code works on both iOS and macOS:

```bash
# iOS
xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace \
  -scheme Lexical-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' test

# macOS
swift test
```

### 4. Document Platform Requirements

If a feature is platform-specific, document it:

```swift
/// Custom image node for inline images.
/// - Note: iOS only. Requires UIKit.
#if canImport(UIKit)
class ImageNode: DecoratorNode {
  // ...
}
#endif
```

## Future Work

### Planned Cross-Platform Support

- **DecoratorNodes for macOS**: Implement NSView-based decorators
- **InlineImagePlugin for macOS**: Port to NSView
- **Custom DecoratorBlocks for macOS**: Block-level NSView decorators

### Contributing

To add cross-platform support:

1. Identify platform-specific dependencies (UIView, NSView, etc.)
2. Create platform abstractions using conditional compilation
3. Test on both iOS and macOS
4. Update documentation

## Summary

| Feature | iOS | macOS | Notes |
|---------|-----|-------|-------|
| **Editor Core** | ✅ | ✅ | Fully compatible |
| **LexicalView** | ✅ | ✅ | Platform-specific inheritance |
| **Text Nodes** | ✅ | ✅ | All types supported |
| **DecoratorNodes** | ✅ | ❌ | Requires NSView implementation |
| **List Plugin** | ✅ | ✅ | Fully compatible |
| **Link Plugin** | ✅ | ✅ | Fully compatible |
| **History Plugin** | ✅ | ✅ | Fully compatible |
| **InlineImage Plugin** | ✅ | ❌ | Depends on DecoratorNode |
| **HTML Export** | ✅ | ✅ | Fully compatible |
| **Markdown Export** | ✅ | ✅ | Fully compatible |
| **SwiftUI** | ✅ | ✅ | Cross-platform wrapper |
| **Themes** | ✅ | ✅ | Platform type aliases |
| **Selection** | ✅ | ✅ | Fully compatible |

## Resources

- [Getting Started - iOS](https://facebook.github.io/lexical-ios/documentation/lexical/)
- [Getting Started - macOS](MACOS_GETTING_STARTED.md)
- [Getting Started - SwiftUI](SWIFTUI_GETTING_STARTED.md)
- [iOS Playground](../Playground/LexicalPlayground.xcodeproj)
- [macOS Playground](../TestApp/LexicalMacOSTest.xcworkspace)
