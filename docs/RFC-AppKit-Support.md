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

### Option A: Conditional Compilation (Recommended)

Use `#if canImport(AppKit)` throughout the codebase to handle platform differences inline.

**Pros:**
- Single codebase, easier maintenance
- Changes to shared logic apply to both platforms
- Familiar pattern in Swift ecosystem

**Cons:**
- Conditional blocks can become complex
- Both platforms must compile together

### Option B: Separate Targets

Split into `LexicalCore`, `LexicalUIKit`, and `LexicalAppKit` targets.

**Pros:**
- Clean separation of concerns
- Platform-specific code is isolated
- Can ship platform-specific packages

**Cons:**
- More complex build configuration
- Harder to share code that needs minor platform tweaks
- More files to maintain

### Recommendation

**Use Option A (Conditional Compilation)** with strategic abstractions:

1. Create platform type aliases (`PlatformView`, `PlatformFont`, etc.)
2. Create protocol abstractions where behavior differs significantly
3. Use `#if` blocks for implementation differences
4. Keep the single-target structure initially

---

## Detailed Work Breakdown

### Phase 1: Platform Abstraction Layer

**Estimated effort: 2-3 days**

#### 1.1 Create `PlatformTypes.swift`

```swift
#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
public typealias PlatformView = NSView
public typealias PlatformFont = NSFont
public typealias PlatformColor = NSColor
public typealias PlatformImage = NSImage
#else
import UIKit
public typealias PlatformView = UIView
public typealias PlatformFont = UIFont
public typealias PlatformColor = UIColor
public typealias PlatformImage = UIImage
#endif
```

#### 1.2 Create `SelectionTypes.swift`

Abstract `UITextStorageDirection` and `UITextGranularity`:

```swift
public enum SelectionAffinity: Int {
  case forward
  case backward
}

public enum SelectionGranularity: Int {
  case character, word, sentence, paragraph, line, document
}
```

#### 1.3 Create `PasteboardProtocol.swift`

```swift
@MainActor
public protocol PasteboardProtocol: AnyObject {
  var string: String? { get set }
  func setData(_ data: Data, forType typeIdentifier: String)
  func data(forType typeIdentifier: String) -> Data?
  // ...
}
```

#### 1.4 Update Files

| File | Changes |
|------|---------|
| `Package.swift` | Add `.macOS(.v13)` platform |
| `Constants.swift` | Use platform typealiases |
| `NativeSelection.swift` | Abstract `UITextRange` |
| `FrontendProtocol.swift` | Use `PlatformEdgeInsets`, `PlatformView` |

### Phase 2: Update Core Files

**Estimated effort: 3-5 days**

Add `#if canImport(AppKit)` conditionals to:

| File | Changes Required |
|------|------------------|
| `Events.swift` | Abstract pasteboard, rename to platform-neutral |
| `CopyPasteHelpers.swift` | Use `PasteboardProtocol` |
| `AttributesUtils.swift` | Handle `NSFont`/`UIFont` differences |
| `Utils.swift` | Minor platform conditionals |
| `TextNode.swift` | `UIColor` → `PlatformColor` |
| `RangeSelection.swift` | `UITextStorageDirection` → `SelectionAffinity` |

### Phase 3: Update TextKit Layer

**Estimated effort: 1-2 days**

TextKit classes are mostly cross-platform. Changes needed:

| File | Changes |
|------|---------|
| `TextStorage.swift` | Add import conditional only |
| `LayoutManager.swift` | `showCGGlyphs` needs platform-specific font type |
| `TextContainer.swift` | Add import conditional only |
| `TextAttachment.swift` | `image(forBounds:)` return type differs |
| `LayoutManagerDelegate.swift` | Font type in delegate method |

### Phase 4: Create AppKit Frontend

**Estimated effort: 2-3 weeks**

This is the largest piece of work - creating the AppKit equivalent of `LexicalView` and `TextView`.

#### 4.1 `LexicalViewAppKit.swift`

```swift
#if canImport(AppKit) && !targetEnvironment(macCatalyst)
@MainActor
public class LexicalViewAppKit: NSView, Frontend {
  public let textView: TextViewAppKit
  // Implement Frontend protocol
  // Handle decorator subviews
  // Manage overlay views
}
#endif
```

**Key responsibilities:**
- Initialize TextKit stack
- Create and configure `TextViewAppKit`
- Implement `Frontend` protocol
- Handle decorator view positioning
- Manage placeholder text

#### 4.2 `TextViewAppKit.swift`

```swift
#if canImport(AppKit) && !targetEnvironment(macCatalyst)
@MainActor
public class TextViewAppKit: NSTextView, NSTextInputClient {
  weak var editor: Editor?

  // NSTextInputClient implementation
  // Keyboard event handling
  // Selection management
  // Marked text (IME) support
}
#endif
```

**Key responsibilities:**
- Implement `NSTextInputClient` for text input
- Handle `keyDown:` for keyboard events
- Manage selection via `selectedRange`
- Support marked text for IME
- Integrate with Lexical's command system

#### 4.3 Key Implementation Challenges

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

**Estimated effort: 3-5 days**

Most plugins are platform-agnostic. These need attention:

| Plugin | Changes Needed |
|--------|----------------|
| `LexicalInlineImagePlugin` | Abstract `UIImage`/`NSImage` |
| `SelectableDecoratorNode` | Abstract view handling |
| `LexicalCodeHighlightPlugin` | Verify font handling |

### Phase 6: Testing

**Estimated effort: 1-2 weeks**

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

## Estimated Timeline

| Phase | Duration | Dependencies |
|-------|----------|--------------|
| Phase 1: Platform Abstraction | 2-3 days | None |
| Phase 2: Core Updates | 3-5 days | Phase 1 |
| Phase 3: TextKit Updates | 1-2 days | Phase 1 |
| Phase 4: AppKit Frontend | 2-3 weeks | Phases 1-3 |
| Phase 5: Plugin Updates | 3-5 days | Phase 4 |
| Phase 6: Testing | 1-2 weeks | Phase 5 |

**Total estimated effort: 5-8 weeks**

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

1. **TextKit 2**: Should we support TextKit 2 on macOS 13+? (UIKit version requires iOS 16+)
2. **SwiftUI**: Should we provide a SwiftUI wrapper for the AppKit view?
3. **Catalyst Priority**: How important is Catalyst support vs native AppKit?
4. **Plugin Scope**: Which plugins must work on day one?

---

## Appendix: File-by-File Analysis

### Files Requiring Changes

<details>
<summary>Click to expand full file list</summary>

#### Core (39 files with UIKit imports)

| File | UIKit Usage | Change Type |
|------|-------------|-------------|
| `Editor.swift` | `UIKeyCommand` | Conditional |
| `Events.swift` | `UIPasteboard` | Abstract |
| `Constants.swift` | `UIFont`, `UIColor` | Typealias |
| `TextNode.swift` | `UIColor` | Typealias |
| `Utils.swift` | Minor | Conditional |
| `RangeSelection.swift` | `UITextStorageDirection` | Abstract |
| `SelectionUtils.swift` | Selection types | Abstract |
| `GridSelection.swift` | Selection types | Abstract |
| `NodeSelection.swift` | Selection types | Abstract |
| `Reconciler.swift` | Minor | Conditional |
| `OptimizedReconciler.swift` | Minor | Conditional |

#### LexicalView (6 files)

| File | Change Type |
|------|-------------|
| `LexicalView.swift` | Wrap in `#if` |
| `FrontendProtocol.swift` | Abstract types |
| `LexicalOverlayView.swift` | Wrap in `#if` |
| `ResponderForNodeSelection.swift` | Wrap in `#if` |
| `ReadOnly/LexicalReadOnlyView.swift` | Wrap in `#if` |
| `ReadOnly/LexicalReadOnlyTextKitContext.swift` | Conditional |

#### TextView (3 files)

| File | Change Type |
|------|-------------|
| `TextView.swift` | Wrap in `#if`, create AppKit version |
| `NativeSelection.swift` | Abstract |
| `InputDelegateProxy.swift` | Wrap in `#if` |

#### TextKit (7 files)

| File | Change Type |
|------|-------------|
| `TextStorage.swift` | Import conditional |
| `LayoutManager.swift` | Font type conditional |
| `TextContainer.swift` | Import conditional |
| `TextAttachment.swift` | Image type conditional |
| `LayoutManagerDelegate.swift` | Font type conditional |
| `RangeCache.swift` | Selection type abstract |
| `TextKitUtils.swift` | None (pure Foundation) |

#### Helper (3 files)

| File | Change Type |
|------|-------------|
| `CopyPasteHelpers.swift` | Abstract pasteboard |
| `AttributesUtils.swift` | Font/color conditionals |
| `ReconcilerShadowCompare.swift` | None |

</details>

---

## References

- [Apple TextKit Documentation](https://developer.apple.com/documentation/appkit/textkit)
- [NSTextInputClient Protocol](https://developer.apple.com/documentation/appkit/nstextinputclient)
- [Lexical Web Documentation](https://lexical.dev/)
- [Swift Conditional Compilation](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/statements/#Conditional-Compilation-Block)
