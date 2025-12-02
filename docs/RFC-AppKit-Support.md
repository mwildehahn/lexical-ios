# RFC: AppKit Support for Lexical iOS

**Status:** Draft
**Author:** Claude
**Created:** 2025-12-01
**Target Version:** 2.0

---

## Summary

This RFC proposes adding macOS AppKit support to the Lexical iOS framework, enabling the rich text editor to run natively on macOS alongside its existing iOS/Catalyst support.

---

## Motivation

Lexical iOS currently only supports UIKit-based platforms (iOS, iPadOS, Mac Catalyst). Adding native AppKit support would:

1. **Expand platform reach** - Enable native macOS applications to use Lexical
2. **Improve macOS experience** - Native AppKit provides better macOS integration than Catalyst
3. **Reduce friction** - Developers building cross-platform Swift apps can share editor logic
4. **Align with Lexical ecosystem** - Web Lexical already supports multiple platforms

---

## Current Architecture Analysis

### Codebase Statistics

| Metric | Count |
|--------|-------|
| Total Swift files | 254 |
| Total lines of code | ~43,000 |
| Files importing UIKit | 69 (39 core, 30 plugins) |

### Architecture Layers

```
┌─────────────────────────────────────────────────────────┐
│                    Application Layer                     │
└─────────────────────────────────────────────────────────┘
                            │
┌─────────────────────────────────────────────────────────┐
│                     LexicalView                          │
│              (UIView + Frontend Protocol)                │
└─────────────────────────────────────────────────────────┘
                            │
┌─────────────────────────────────────────────────────────┐
│                       TextView                           │
│                  (UITextView subclass)                   │
└─────────────────────────────────────────────────────────┘
                            │
┌─────────────────────────────────────────────────────────┐
│                    TextKit Layer                         │
│         (TextStorage, LayoutManager, TextContainer)      │
└─────────────────────────────────────────────────────────┘
                            │
┌─────────────────────────────────────────────────────────┐
│                      Core Editor                         │
│    (Editor, EditorState, Nodes, Selection, Reconciler)   │
└─────────────────────────────────────────────────────────┘
```

### Key Abstraction: Frontend Protocol

The codebase has an existing `Frontend` protocol (`Lexical/LexicalView/FrontendProtocol.swift`) that provides a clean boundary between the Editor and the view layer:

```swift
@MainActor
internal protocol Frontend: AnyObject {
  var textStorage: TextStorage { get }
  var layoutManager: LayoutManager { get }
  var textContainerInsets: UIEdgeInsets { get }
  var editor: Editor { get }
  var nativeSelection: NativeSelection { get }
  var isFirstResponder: Bool { get }
  var viewForDecoratorSubviews: UIView? { get }
  var isEmpty: Bool { get }
  var isUpdatingNativeSelection: Bool { get set }
  var interceptNextSelectionChangeAndReplaceWithRange: NSRange? { get set }
  var textLayoutWidth: CGFloat { get }

  func moveNativeSelection(type: NativeSelectionModificationType,
                           direction: UITextStorageDirection,
                           granularity: UITextGranularity)
  func unmarkTextWithoutUpdate()
  func presentDeveloperFacingError(message: String)
  func updateNativeSelection(from selection: BaseSelection) throws
  func setMarkedTextFromReconciler(_ markedText: NSAttributedString, selectedRange: NSRange)
  func resetSelectedRange()
  func showPlaceholderText()
  func resetTypingAttributes(for selectedNode: Node)
}
```

This protocol is the **key integration point** for AppKit support.

---

## Platform Compatibility Analysis

### Fully Platform-Agnostic Components (No Changes Needed)

These components use Foundation/CoreGraphics only and work on both platforms:

| Component | Location | Lines |
|-----------|----------|-------|
| Node system | `Core/Nodes/` | ~3,000 |
| EditorState | `Core/EditorState.swift` | ~200 |
| Selection algorithms | `Core/Selection/` | ~2,500 |
| Reconciler | `Core/Reconciler.swift`, `OptimizedReconciler.swift` | ~4,000 |
| Serialization | Various | ~500 |
| Theme system | `Core/Theme.swift` | ~300 |
| Command dispatch | `Core/Editor.swift` | ~1,500 |

**Estimated reusable code: ~12,000 lines (28% of codebase)**

### Components Requiring Platform Abstraction

| Component | Issue | Complexity |
|-----------|-------|------------|
| `Constants.swift` | `UIFont`, `UIColor` defaults | Low |
| `NativeSelection.swift` | `UITextRange`, `UITextStorageDirection` | Medium |
| `Events.swift` | `UIPasteboard` references | Medium |
| `CopyPasteHelpers.swift` | `UIPasteboard`, `UIFont` | Medium |
| `AttributesUtils.swift` | `UIFont`, `UIColor` usage | Low |

### Components Requiring Reimplementation for AppKit

| Component | UIKit Class | AppKit Equivalent | Complexity |
|-----------|-------------|-------------------|------------|
| `LexicalView.swift` | `UIView` | `NSView` | High |
| `TextView.swift` | `UITextView` | `NSTextView` | High |
| `TextStorage.swift` | `NSTextStorage` | `NSTextStorage` (shared) | Low |
| `LayoutManager.swift` | `NSLayoutManager` | `NSLayoutManager` (shared) | Low |
| `TextContainer.swift` | `NSTextContainer` | `NSTextContainer` (shared) | Low |
| `InputDelegateProxy.swift` | `UITextInputDelegate` | `NSTextInputClient` | High |
| Keyboard handling | `UIKeyCommand` | `NSEvent`, `performKeyEquivalent` | Medium |
| Decorator views | `UIView` subviews | `NSView` subviews | Medium |

---

## UIKit vs AppKit Differences

### TextKit (Mostly Compatible)

Both platforms share TextKit 1 foundations:
- `NSTextStorage` - identical API
- `NSLayoutManager` - identical API
- `NSTextContainer` - identical API
- `NSAttributedString` - identical API

**Key difference:** On AppKit, `NSLayoutManager.showCGGlyphs` uses `NSFont` instead of `UIFont`.

### Text Input

| Aspect | UIKit | AppKit |
|--------|-------|--------|
| Protocol | `UITextInput`, `UITextInputDelegate` | `NSTextInputClient` |
| Selection | `UITextRange`, `UITextPosition` | `NSRange` directly |
| Marked text | Via `setMarkedText(_:selectedRange:)` | Via `setMarkedText(_:selectedRange:replacementRange:)` |
| Key events | `UIKeyCommand`, `pressesBegan` | `keyDown:`, `performKeyEquivalent:` |
| Insert text | `insertText(_:)` | `insertText(_:replacementRange:)` |

### Clipboard

| UIKit | AppKit |
|-------|--------|
| `UIPasteboard` | `NSPasteboard` |
| `UIPasteboard.general` | `NSPasteboard.general` |
| `setData(_:forPasteboardType:)` | `setData(_:forType:)` |
| `data(forPasteboardType:)` | `data(forType:)` |

### Views & Responders

| UIKit | AppKit |
|-------|--------|
| `UIView` | `NSView` |
| `UITextView` | `NSTextView` |
| `becomeFirstResponder()` | `window?.makeFirstResponder(self)` |
| `isFirstResponder` | `window?.firstResponder == self` |
| `UIEdgeInsets` | `NSEdgeInsets` |
| `contentMode` | No equivalent (manual) |

---

## Proposed Implementation Strategy

### Option A: Conditional Compilation

Use `#if canImport(AppKit)` throughout the codebase to handle platform differences inline.

**Pros:**
- Single codebase, easier maintenance
- Changes to shared logic apply to both platforms
- Familiar pattern in Swift ecosystem

**Cons:**
- Conditional blocks can become complex
- Both platforms must compile together
- Platform-specific code mixed with shared code

### Option B: Separate Targets (Recommended)

Split into separate targets with umbrella re-exports, following the pattern used by [STTextView](https://github.com/nicklockwood/STTextView):

```
LexicalCore          - Platform-agnostic: nodes, selection, reconciler, editor state
LexicalUIKit         - UIKit implementation: LexicalView, TextView, UITextInput
LexicalAppKit        - AppKit implementation: LexicalView, TextView, NSTextInputClient
Lexical              - Umbrella target that re-exports the correct implementation
```

**Pros:**
- Clean separation of concerns
- Platform-specific code is fully isolated
- No `#if` blocks cluttering shared code
- Each target compiles independently
- Easier to test platform-specific code
- Proven pattern (STTextView uses this successfully)

**Cons:**
- More complex initial Package.swift setup
- Some code duplication in platform targets

### Recommendation

**Use Option B (Separate Targets)** with umbrella re-exports:

1. Create `LexicalCore` target with platform-agnostic code
2. Create `LexicalUIKit` and `LexicalAppKit` targets for platform-specific implementations
3. Create umbrella `Lexical` target that conditionally re-exports the correct implementation
4. Use a shared `LexicalViewProtocol` with associated types for platform-specific types
5. Maintain parallel file structure between UIKit and AppKit implementations

This approach is proven by STTextView, which successfully supports macOS, iOS, and Mac Catalyst with this architecture.

---

## Detailed Work Breakdown

### Phase 1: Target Structure & Package Setup

#### 1.1 Update `Package.swift`

Restructure into separate targets with platform-conditional dependencies:

```swift
let package = Package(
    name: "Lexical",
    platforms: [.iOS(.v16), .macOS(.v13), .macCatalyst(.v16)],
    products: [
        .library(name: "Lexical", targets: ["Lexical"]),
    ],
    targets: [
        // Umbrella target - re-exports platform-specific implementation
        .target(
            name: "Lexical",
            dependencies: [
                .target(name: "LexicalUIKit",
                        condition: .when(platforms: [.iOS, .macCatalyst])),
                .target(name: "LexicalAppKit",
                        condition: .when(platforms: [.macOS])),
            ]
        ),
        // Platform-agnostic core
        .target(
            name: "LexicalCore",
            dependencies: []
        ),
        // UIKit implementation
        .target(
            name: "LexicalUIKit",
            dependencies: ["LexicalCore"]
        ),
        // AppKit implementation
        .target(
            name: "LexicalAppKit",
            dependencies: ["LexicalCore"]
        ),
    ]
)
```

#### 1.2 Create Umbrella Module (`Sources/Lexical/module.swift`)

```swift
import Foundation

#if os(macOS) && !targetEnvironment(macCatalyst)
@_exported import LexicalAppKit
#else
@_exported import LexicalUIKit
#endif

@_exported import LexicalCore
```

This allows consumers to simply `import Lexical` and get the correct implementation.

#### 1.3 Create `LexicalViewProtocol` with Associated Types

Instead of typealiases, use associated types for flexibility (following STTextView's pattern):

```swift
// In LexicalCore
@MainActor
public protocol LexicalViewProtocol {
    associatedtype ViewType
    associatedtype ColorType
    associatedtype FontType
    associatedtype EdgeInsetsType

    var textStorage: TextStorage { get }
    var layoutManager: LayoutManager { get }
    var textContainerInsets: EdgeInsetsType { get }
    var editor: Editor { get }
    var isFirstResponder: Bool { get }
    var viewForDecoratorSubviews: ViewType? { get }
    // ...
}
```

#### 1.4 Organize Source Directories

```
Sources/
├── Lexical/                    # Umbrella (just module.swift)
├── LexicalCore/                # Platform-agnostic
│   ├── Nodes/
│   ├── Selection/
│   ├── Editor.swift
│   ├── EditorState.swift
│   ├── Reconciler.swift
│   ├── Theme.swift
│   └── LexicalViewProtocol.swift
├── LexicalUIKit/               # iOS/Catalyst
│   ├── LexicalView.swift
│   ├── TextView.swift
│   ├── InputDelegateProxy.swift
│   ├── NativeSelection.swift
│   └── Extensions/
└── LexicalAppKit/              # macOS
    ├── LexicalView.swift       # Parallel structure
    ├── TextView.swift
    ├── TextInputClient.swift
    ├── NativeSelection.swift
    └── Extensions/
```

### Phase 2: Extract Platform-Agnostic Core

Move truly platform-agnostic code into `LexicalCore`:

| Component | Move to LexicalCore | Notes |
|-----------|---------------------|-------|
| `Nodes/` | Yes (entire directory) | No UIKit dependencies |
| `EditorState.swift` | Yes | Pure state management |
| `Editor.swift` | Partial | Extract command dispatch, keep keyboard in UIKit |
| `Reconciler.swift` | Yes | Core diffing logic |
| `Theme.swift` | Yes | Uses Foundation types |
| `Selection/` | Partial | Core algorithms move, UI types stay |

Files that stay in `LexicalUIKit` (with parallel versions in `LexicalAppKit`):

| File | Reason |
|------|--------|
| `Events.swift` | Uses `UIPasteboard` |
| `CopyPasteHelpers.swift` | Platform pasteboard |
| `NativeSelection.swift` | `UITextRange`/`NSRange` differences |
| `AttributesUtils.swift` | Font/color handling |

### Phase 3: TextKit Layer

TextKit 1 classes (`NSTextStorage`, `NSLayoutManager`, `NSTextContainer`) are shared between UIKit and AppKit with nearly identical APIs.

| File | Target | Notes |
|------|--------|-------|
| `TextStorage.swift` | `LexicalCore` | Identical on both platforms |
| `LayoutManager.swift` | Platform targets | `showCGGlyphs` uses different font types |
| `TextContainer.swift` | `LexicalCore` | Identical on both platforms |
| `TextAttachment.swift` | Platform targets | Image type differs |
| `LayoutManagerDelegate.swift` | Platform targets | Font type in delegate |

**Note:** STTextView uses TextKit 2 (`NSTextLayoutManager`) which has better cross-platform parity. Consider whether Lexical should migrate to TextKit 2 for simpler cross-platform support (see Open Questions).

### Phase 4: Create AppKit Frontend

This is the largest piece of work - creating the AppKit implementation in `LexicalAppKit/` with a parallel structure to `LexicalUIKit/`.

#### 4.1 File Structure (Parallel to UIKit)

Following STTextView's pattern, maintain identical file organization:

```
LexicalUIKit/                    LexicalAppKit/
├── LexicalView.swift            ├── LexicalView.swift
├── TextView.swift               ├── TextView.swift
├── TextView+UITextInput.swift   ├── TextView+NSTextInputClient.swift
├── TextView+Keyboard.swift      ├── TextView+Keyboard.swift
├── NativeSelection.swift        ├── NativeSelection.swift
├── CopyPasteHelpers.swift       ├── CopyPasteHelpers.swift
└── Delegate.swift               └── Delegate.swift
```

#### 4.2 `LexicalView.swift` (in LexicalAppKit)

```swift
import AppKit
import LexicalCore

@MainActor
public class LexicalView: NSView, LexicalViewProtocol {
    public typealias ViewType = NSView
    public typealias ColorType = NSColor
    public typealias FontType = NSFont
    public typealias EdgeInsetsType = NSEdgeInsets

    public let textView: TextView
    // Implement LexicalViewProtocol
    // Handle decorator subviews
    // Manage overlay views
}
```

#### 4.3 `TextView.swift` (in LexicalAppKit)

```swift
import AppKit
import LexicalCore

@MainActor
public class TextView: NSTextView, NSTextInputClient {
    weak var editor: Editor?

    // NSTextInputClient implementation
    // Keyboard event handling via keyDown:/performKeyEquivalent:
    // Selection management via selectedRange
    // Marked text (IME) support
}
```

#### 4.4 Key Implementation Challenges

1. **Selection Model Differences**
   - UIKit uses opaque `UITextRange`/`UITextPosition`
   - AppKit uses `NSRange` directly
   - Need to bridge in `NativeSelection`

2. **Marked Text (IME)**
   - UIKit: `setMarkedText(_:selectedRange:)`
   - AppKit: `setMarkedText(_:selectedRange:replacementRange:)`
   - Additional `replacementRange` parameter needs handling

3. **Keyboard Commands**
   - UIKit: `UIKeyCommand` with modifiers
   - AppKit: `performKeyEquivalent:`, `keyDown:`
   - Need to map keyboard shortcuts appropriately

4. **First Responder**
   - UIKit: `becomeFirstResponder()` returns `Bool`
   - AppKit: `window?.makeFirstResponder(self)`
   - Different responder chain behavior

### Phase 5: Update Plugins

Most plugins are platform-agnostic. These need attention:

| Plugin | Changes Needed |
|--------|----------------|
| `LexicalInlineImagePlugin` | Abstract `UIImage`/`NSImage` |
| `SelectableDecoratorNode` | Abstract view handling |
| `LexicalCodeHighlightPlugin` | Verify font handling |

### Phase 6: SwiftUI Wrappers (Optional)

Following STTextView's pattern, provide SwiftUI wrappers in separate targets:

```swift
// Package.swift additions
.target(
    name: "LexicalSwiftUI",
    dependencies: [
        .target(name: "LexicalSwiftUIUIKit",
                condition: .when(platforms: [.iOS, .macCatalyst])),
        .target(name: "LexicalSwiftUIAppKit",
                condition: .when(platforms: [.macOS])),
    ]
),
.target(name: "LexicalSwiftUIUIKit", dependencies: ["Lexical"]),
.target(name: "LexicalSwiftUIAppKit", dependencies: ["Lexical"]),
```

Each platform target provides the same public API:

```swift
// LexicalSwiftUIUIKit/LexicalEditorView.swift
public struct LexicalEditorView: UIViewRepresentable {
    @Binding var text: AttributedString
    // ...
}

// LexicalSwiftUIAppKit/LexicalEditorView.swift
public struct LexicalEditorView: NSViewRepresentable {
    @Binding var text: AttributedString
    // ...
}
```

### Phase 7: Testing

1. **Unit Tests**
   - Ensure existing tests pass on macOS
   - Add macOS-specific test cases
   - Test keyboard input handling

2. **Integration Tests**
   - Full editing workflows
   - Copy/paste between platforms
   - IME input (Japanese, Chinese, etc.)

3. **Visual Testing**
   - Verify rendering parity
   - Test custom drawing
   - Decorator positioning

---

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| TextKit differences between platforms | High | Thorough testing, fallback behaviors |
| IME handling complexity | Medium | Test with multiple input methods early |
| Selection edge cases | Medium | Port UIKit selection tests, add AppKit cases |
| Decorator view positioning | Medium | Abstract positioning logic |
| Plugin compatibility | Low | Most plugins are platform-agnostic |

---

## Success Criteria

1. **Compilation**: Package compiles for both iOS and macOS
2. **Basic Editing**: Text input, deletion, selection work on macOS
3. **Rich Text**: Bold, italic, underline formatting works
4. **Copy/Paste**: Works within app and with system
5. **IME Support**: Japanese/Chinese input works correctly
6. **Plugins**: Core plugins function on macOS
7. **Test Parity**: Test suite passes on both platforms

---

## Open Questions

1. **TextKit 2 Migration**: STTextView uses TextKit 2 exclusively, which has better cross-platform parity. Should Lexical migrate from TextKit 1 to TextKit 2? This would be a larger undertaking but would simplify the platform abstraction.
2. **SwiftUI Priority**: Should SwiftUI wrappers be included in the initial release, or added later?
3. **Catalyst Priority**: How important is Catalyst support vs native AppKit? The umbrella target approach supports both.
4. **Plugin Scope**: Which plugins must work on day one?
5. **Naming**: Should the classes be named identically (`LexicalView`) in both targets, or differently (`LexicalViewUIKit`/`LexicalViewAppKit`)? STTextView uses identical names.

---

## Appendix: Target Organization

### Proposed Target Structure

<details>
<summary>Click to expand full target breakdown</summary>

#### LexicalCore (Platform-Agnostic)

Files that move to `LexicalCore` with no platform dependencies:

| Directory/File | Notes |
|----------------|-------|
| `Nodes/` | All node types (TextNode, ElementNode, etc.) |
| `Selection/` | Core selection algorithms |
| `EditorState.swift` | State management |
| `Reconciler.swift` | Core diffing logic |
| `OptimizedReconciler.swift` | Performance-optimized reconciler |
| `Theme.swift` | Theme definitions |
| `TextStorage.swift` | NSTextStorage (shared API) |
| `TextContainer.swift` | NSTextContainer (shared API) |
| `LexicalViewProtocol.swift` | New - shared protocol with associated types |

#### LexicalUIKit (iOS/Catalyst)

Files that remain in or are created for `LexicalUIKit`:

| File | Notes |
|------|-------|
| `LexicalView.swift` | UIView-based implementation |
| `TextView.swift` | UITextView subclass |
| `TextView+UITextInput.swift` | UITextInput protocol |
| `TextView+Keyboard.swift` | UIKeyCommand handling |
| `NativeSelection.swift` | UITextRange/UITextPosition |
| `InputDelegateProxy.swift` | UITextInputDelegate |
| `CopyPasteHelpers.swift` | UIPasteboard |
| `AttributesUtils.swift` | UIFont/UIColor handling |
| `LayoutManager.swift` | UIKit font types |
| `LexicalOverlayView.swift` | Overlay handling |

#### LexicalAppKit (macOS)

New files created in `LexicalAppKit` (parallel to UIKit):

| File | Notes |
|------|-------|
| `LexicalView.swift` | NSView-based implementation |
| `TextView.swift` | NSTextView subclass |
| `TextView+NSTextInputClient.swift` | NSTextInputClient protocol |
| `TextView+Keyboard.swift` | keyDown:/performKeyEquivalent: |
| `NativeSelection.swift` | NSRange-based |
| `CopyPasteHelpers.swift` | NSPasteboard |
| `AttributesUtils.swift` | NSFont/NSColor handling |
| `LayoutManager.swift` | AppKit font types |
| `LexicalOverlayView.swift` | Overlay handling |

</details>

---

## References

- [STTextView](https://github.com/nicklockwood/STTextView) - Reference implementation for cross-platform text view architecture
- [Apple TextKit Documentation](https://developer.apple.com/documentation/appkit/textkit)
- [NSTextInputClient Protocol](https://developer.apple.com/documentation/appkit/nstextinputclient)
- [Lexical Web Documentation](https://lexical.dev/)
- [Swift Conditional Compilation](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/statements/#Conditional-Compilation-Block)
