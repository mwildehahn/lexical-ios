# AppKit Implementation Task List

This task list is designed for an LLM agent to implement AppKit support for Lexical iOS.

---

## Before You Begin

**READ THE RFC FIRST:** Before starting any tasks, read the full RFC for context:
- **`/Users/mh/labs/lexical-ios/docs/RFC-AppKit-Support.md`**

The RFC contains:
- Motivation and goals for AppKit support
- Architecture analysis of the current codebase
- Platform compatibility analysis (what's shared vs platform-specific)
- UIKit vs AppKit API differences
- The recommended implementation strategy (separate targets with umbrella re-exports)
- Detailed rationale for design decisions

**Reference Implementation:** STTextView at `/Users/mh/labs/STTextView` demonstrates the cross-platform patterns we're following. File references throughout this task list point to specific implementations.

---

## Instructions for Agent

1. **Read the RFC** (`docs/RFC-AppKit-Support.md`) to understand the full context
2. **Find your place** - Look for the first unchecked `[ ]` task to resume work
3. **Work sequentially** within each phase
4. **Mark tasks `[x]`** when complete (edit this file)
5. **Reference STTextView** files listed for implementation patterns
6. **Build frequently** - Run `swift build` after changes to catch issues early
7. **Commit after each phase** completion

---

## Phase 1: Package Structure & Umbrella Module

### 1.1 Update Package.swift
- [ ] Add `.macOS(.v13)` to platforms array
- [ ] Create `LexicalCore` target with no dependencies
- [ ] Create `LexicalUIKit` target depending on `LexicalCore`
- [ ] Create `LexicalAppKit` target depending on `LexicalCore` with `.when(platforms: [.macOS])`
- [ ] Update main `Lexical` target to use platform-conditional dependencies
- [ ] Verify package resolves: `swift package resolve`

**STTextView Reference:**
- `/Users/mh/labs/STTextView/Package.swift` - Full example of platform-conditional targets

### 1.2 Create Umbrella Module
- [ ] Create `Sources/Lexical/` directory (if restructuring)
- [ ] Create `Sources/Lexical/module.swift` with conditional re-exports:
  ```swift
  #if os(macOS) && !targetEnvironment(macCatalyst)
  @_exported import LexicalAppKit
  #else
  @_exported import LexicalUIKit
  #endif
  @_exported import LexicalCore
  ```

**STTextView Reference:**
- `/Users/mh/labs/STTextView/Sources/STTextView/module.swift` - Umbrella re-export pattern

### 1.3 Create Directory Structure
- [ ] Create `Sources/LexicalCore/`
- [ ] Create `Sources/LexicalUIKit/`
- [ ] Create `Sources/LexicalAppKit/`
- [ ] Verify build succeeds with empty targets: `swift build`

---

## Phase 2: Extract LexicalCore

### 2.1 Identify Platform-Agnostic Files
- [ ] Audit each file in current `Lexical/` for UIKit imports
- [ ] Create list of files with NO UIKit dependencies (candidates for Core)
- [ ] Create list of files with UIKit dependencies (stay in UIKit target)

### 2.2 Move Node System to Core
- [ ] Move `Nodes/Node.swift` to `LexicalCore/`
- [ ] Move `Nodes/TextNode.swift` to `LexicalCore/`
- [ ] Move `Nodes/ElementNode.swift` to `LexicalCore/`
- [ ] Move `Nodes/RootNode.swift` to `LexicalCore/`
- [ ] Move `Nodes/ParagraphNode.swift` to `LexicalCore/`
- [ ] Move `Nodes/LineBreakNode.swift` to `LexicalCore/`
- [ ] Move `Nodes/DecoratorNode.swift` to `LexicalCore/`
- [ ] Move all remaining node files to `LexicalCore/`
- [ ] Fix any import issues (remove UIKit, use Foundation)
- [ ] Verify Core target builds: `swift build --target LexicalCore`

**STTextView Reference:**
- `/Users/mh/labs/STTextView/Sources/STTextViewCommon/` - Example of shared platform-agnostic code

### 2.3 Move Editor State to Core
- [ ] Move `EditorState.swift` to `LexicalCore/`
- [ ] Move `EditorHistory.swift` to `LexicalCore/` (if exists)
- [ ] Extract platform-agnostic parts of `Editor.swift` to `LexicalCore/EditorCore.swift`
- [ ] Keep UIKit-specific Editor code in `LexicalUIKit/`

### 2.4 Move Selection Logic to Core
- [ ] Move `Selection/BaseSelection.swift` to `LexicalCore/`
- [ ] Move `Selection/RangeSelection.swift` to `LexicalCore/` (extract UI types)
- [ ] Move `Selection/NodeSelection.swift` to `LexicalCore/`
- [ ] Move `Selection/GridSelection.swift` to `LexicalCore/`
- [ ] Create `SelectionTypes.swift` in Core for platform-neutral selection enums
- [ ] Verify Core target builds

### 2.5 Move Reconciler to Core
- [ ] Move `Reconciler.swift` to `LexicalCore/`
- [ ] Move `OptimizedReconciler.swift` to `LexicalCore/`
- [ ] Abstract any UIKit dependencies (if any)
- [ ] Verify Core target builds

### 2.6 Move Theme System to Core
- [ ] Move `Theme.swift` to `LexicalCore/`
- [ ] Abstract color/font types if needed
- [ ] Verify Core target builds

### 2.7 Create LexicalViewProtocol
- [ ] Create `LexicalCore/LexicalViewProtocol.swift`
- [ ] Define protocol with associated types for platform-specific types
- [ ] Include all methods needed by Editor to communicate with view layer

**STTextView Reference:**
- `/Users/mh/labs/STTextView/Sources/STTextViewCommon/STTextViewProtocol.swift` - Protocol with associated types pattern

### 2.8 Verify Phase 2 Complete
- [ ] `swift build --target LexicalCore` succeeds
- [ ] `swift build --target LexicalUIKit` succeeds
- [ ] Run existing tests to verify no regressions

---

## Phase 3: Organize LexicalUIKit

### 3.1 Move Remaining UIKit Files
- [ ] Move `LexicalView.swift` to `LexicalUIKit/`
- [ ] Move `TextView.swift` to `LexicalUIKit/`
- [ ] Move `InputDelegateProxy.swift` to `LexicalUIKit/`
- [ ] Move `NativeSelection.swift` to `LexicalUIKit/`
- [ ] Move `CopyPasteHelpers.swift` to `LexicalUIKit/`
- [ ] Move `AttributesUtils.swift` to `LexicalUIKit/`
- [ ] Move overlay/decorator view files to `LexicalUIKit/`

### 3.2 Update LexicalView to Conform to Protocol
- [ ] Make `LexicalView` conform to `LexicalViewProtocol`
- [ ] Add required typealiases for associated types
- [ ] Verify UIKit target builds: `swift build --target LexicalUIKit`

### 3.3 Organize UIKit Extensions
- [ ] Create `LexicalUIKit/Extensions/` directory
- [ ] Split `TextView.swift` into logical extensions:
  - [ ] `TextView+UITextInput.swift`
  - [ ] `TextView+Keyboard.swift`
  - [ ] `TextView+Selection.swift`

**STTextView Reference:**
- `/Users/mh/labs/STTextView/Sources/STTextViewUIKit/STTextView+UITextInput.swift`
- `/Users/mh/labs/STTextView/Sources/STTextViewUIKit/STTextView+UIKeyInput.swift`

### 3.4 Verify Phase 3 Complete
- [ ] `swift build` succeeds for all targets
- [ ] `swift test` passes
- [ ] iOS app/demo still works

---

## Phase 4: Create LexicalAppKit

### 4.1 Create Basic AppKit LexicalView
- [ ] Create `LexicalAppKit/LexicalView.swift`
- [ ] Inherit from `NSView`
- [ ] Conform to `LexicalViewProtocol`
- [ ] Add typealiases: `ViewType = NSView`, `ColorType = NSColor`, etc.
- [ ] Implement basic initializers
- [ ] Verify builds: `swift build --target LexicalAppKit`

**STTextView Reference:**
- `/Users/mh/labs/STTextView/Sources/STTextViewAppKit/STTextView.swift` - Main AppKit text view

### 4.2 Create AppKit TextView
- [ ] Create `LexicalAppKit/TextView.swift`
- [ ] Inherit from `NSTextView` (or `NSView` if building from scratch)
- [ ] Set up TextKit stack (NSTextStorage, NSLayoutManager, NSTextContainer)
- [ ] Connect to LexicalView

**STTextView Reference:**
- `/Users/mh/labs/STTextView/Sources/STTextViewAppKit/STTextView.swift` - Lines 1-200 for setup

### 4.3 Implement NSTextInputClient
- [ ] Create `LexicalAppKit/TextView+NSTextInputClient.swift`
- [ ] Implement `insertText(_:replacementRange:)`
- [ ] Implement `setMarkedText(_:selectedRange:replacementRange:)`
- [ ] Implement `unmarkText()`
- [ ] Implement `selectedRange()` -> `NSRange`
- [ ] Implement `markedRange()` -> `NSRange`
- [ ] Implement `hasMarkedText()` -> `Bool`
- [ ] Implement `attributedSubstring(forProposedRange:actualRange:)`
- [ ] Implement `validAttributesForMarkedText()` -> `[NSAttributedString.Key]`
- [ ] Implement `firstRect(forCharacterRange:actualRange:)` -> `NSRect`
- [ ] Implement `characterIndex(for:)` -> `Int`

**STTextView Reference:**
- `/Users/mh/labs/STTextView/Sources/STTextViewAppKit/STTextView+NSTextInputClient.swift` - Full implementation

### 4.4 Implement Keyboard Handling
- [ ] Create `LexicalAppKit/TextView+Keyboard.swift`
- [ ] Override `keyDown(with:)`
- [ ] Override `performKeyEquivalent(with:)` -> `Bool`
- [ ] Map key events to Lexical commands
- [ ] Handle arrow keys, delete, return, tab
- [ ] Handle modifier keys (Cmd, Ctrl, Option, Shift)

**STTextView Reference:**
- `/Users/mh/labs/STTextView/Sources/STTextViewAppKit/STTextView+Key.swift` - Key event handling
- `/Users/mh/labs/STTextView/Sources/STTextViewAppKit/Extensions/NSEvent+Helpers.swift` - Key helpers

### 4.5 Implement Selection Management
- [ ] Create `LexicalAppKit/NativeSelection.swift`
- [ ] Implement selection using `NSRange` (simpler than UIKit's UITextRange)
- [ ] Connect to Lexical's selection system
- [ ] Handle selection change notifications

**STTextView Reference:**
- `/Users/mh/labs/STTextView/Sources/STTextViewAppKit/STTextView+Select.swift` - Selection handling

### 4.6 Implement Copy/Paste
- [ ] Create `LexicalAppKit/CopyPasteHelpers.swift`
- [ ] Use `NSPasteboard` instead of `UIPasteboard`
- [ ] Implement `copy:`, `cut:`, `paste:` actions
- [ ] Handle rich text and plain text pasteboard types

**STTextView Reference:**
- `/Users/mh/labs/STTextView/Sources/STTextViewAppKit/STTextView+CopyPaste.swift` - Pasteboard handling

### 4.7 Implement First Responder
- [ ] Override `acceptsFirstResponder` -> `Bool` (return true)
- [ ] Override `becomeFirstResponder()` -> `Bool`
- [ ] Override `resignFirstResponder()` -> `Bool`
- [ ] Handle `window?.makeFirstResponder(self)` pattern

**STTextView Reference:**
- `/Users/mh/labs/STTextView/Sources/STTextViewAppKit/STTextView.swift` - Search for "firstResponder"

### 4.8 Implement Mouse Handling
- [ ] Override `mouseDown(with:)`
- [ ] Override `mouseDragged(with:)`
- [ ] Override `mouseUp(with:)`
- [ ] Convert mouse coordinates to text positions
- [ ] Update selection on mouse events

**STTextView Reference:**
- `/Users/mh/labs/STTextView/Sources/STTextViewAppKit/STTextView+Mouse.swift` - Mouse event handling

### 4.9 Implement Undo/Redo
- [ ] Create `LexicalAppKit/TextView+Undo.swift`
- [ ] Connect to `undoManager`
- [ ] Register undo actions for text changes

**STTextView Reference:**
- `/Users/mh/labs/STTextView/Sources/STTextViewAppKit/STTextView+Undo.swift` - Undo management
- `/Users/mh/labs/STTextView/Sources/STTextViewCommon/CoalescingUndoManager.swift` - Coalescing pattern

### 4.10 Implement Scrolling
- [ ] Handle scroll view integration
- [ ] Implement `scrollRangeToVisible(_:)`
- [ ] Handle viewport updates

**STTextView Reference:**
- `/Users/mh/labs/STTextView/Sources/STTextViewAppKit/STTextView+Scrolling.swift` - Scroll handling

### 4.11 Verify Phase 4 Complete
- [ ] `swift build --target LexicalAppKit` succeeds
- [ ] `swift build` succeeds for all platforms
- [ ] Basic text input works in AppKit test app

---

## Phase 5: TextKit Layer

### 5.1 Create AppKit LayoutManager
- [ ] Create `LexicalAppKit/LayoutManager.swift`
- [ ] Handle `NSFont` instead of `UIFont` in delegate methods
- [ ] Override `showCGGlyphs` if needed

**STTextView Reference:**
- `/Users/mh/labs/STTextView/Sources/STTextViewAppKit/STTextView+NSTextLayoutManagerDelegate.swift`

### 5.2 Create AppKit TextAttachment Support
- [ ] Create `LexicalAppKit/TextAttachment.swift` if needed
- [ ] Handle `NSImage` instead of `UIImage`

### 5.3 Create AppKit AttributesUtils
- [ ] Create `LexicalAppKit/AttributesUtils.swift`
- [ ] Use `NSFont`, `NSColor` instead of UIKit equivalents
- [ ] Maintain same public API as UIKit version

### 5.4 Verify Phase 5 Complete
- [ ] Rich text rendering works on macOS
- [ ] Font and color attributes applied correctly

---

## Phase 6: Delegate & Plugin System

### 6.1 Create AppKit Delegate Protocol
- [ ] Create `LexicalAppKit/LexicalViewDelegate.swift`
- [ ] Mirror UIKit delegate methods
- [ ] Add AppKit-specific delegate methods if needed

**STTextView Reference:**
- `/Users/mh/labs/STTextView/Sources/STTextViewAppKit/STTextViewDelegate.swift` - Delegate pattern

### 6.2 Update Plugin System for AppKit
- [ ] Audit plugins for UIKit dependencies
- [ ] Create AppKit versions of platform-specific plugins
- [ ] Ensure plugin protocol works cross-platform

**STTextView Reference:**
- `/Users/mh/labs/STTextView/Sources/STTextViewAppKit/Plugin/STPlugin.swift` - Plugin architecture

### 6.3 Verify Phase 6 Complete
- [ ] Delegates work on both platforms
- [ ] Core plugins function on macOS

---

## Phase 7: Testing & Validation

### 7.1 Create macOS Test Target
- [ ] Add macOS test target to Package.swift
- [ ] Configure test target for macOS platform

### 7.2 Port Existing Tests
- [ ] Identify platform-agnostic tests
- [ ] Move/copy tests to run on both platforms
- [ ] Create platform-specific test helpers

### 7.3 Add AppKit-Specific Tests
- [ ] Test NSTextInputClient implementation
- [ ] Test keyboard event handling
- [ ] Test mouse event handling
- [ ] Test copy/paste with NSPasteboard
- [ ] Test IME/marked text input

### 7.4 Integration Testing
- [ ] Test full editing workflow on macOS
- [ ] Test rich text formatting
- [ ] Test undo/redo
- [ ] Test selection behaviors
- [ ] Test with Japanese/Chinese IME input

### 7.5 Verify Phase 7 Complete
- [ ] All tests pass on iOS
- [ ] All tests pass on macOS
- [ ] No regressions in existing functionality

---

## Phase 8: SwiftUI Wrappers (Optional)

### 8.1 Create SwiftUI Target Structure
- [ ] Add `LexicalSwiftUI` umbrella target
- [ ] Add `LexicalSwiftUIUIKit` target
- [ ] Add `LexicalSwiftUIAppKit` target

**STTextView Reference:**
- `/Users/mh/labs/STTextView/Package.swift` - SwiftUI target setup

### 8.2 Create UIKit SwiftUI Wrapper
- [ ] Create `LexicalSwiftUIUIKit/LexicalEditorView.swift`
- [ ] Implement `UIViewRepresentable`
- [ ] Create Coordinator for delegate handling
- [ ] Expose bindings for text content

**STTextView Reference:**
- `/Users/mh/labs/STTextView/Sources/STTextViewSwiftUIUIKit/TextView.swift` - UIViewRepresentable pattern

### 8.3 Create AppKit SwiftUI Wrapper
- [ ] Create `LexicalSwiftUIAppKit/LexicalEditorView.swift`
- [ ] Implement `NSViewRepresentable`
- [ ] Create Coordinator for delegate handling
- [ ] Match UIKit wrapper's public API

**STTextView Reference:**
- `/Users/mh/labs/STTextView/Sources/STTextViewSwiftUIAppKit/TextView.swift` - NSViewRepresentable pattern

### 8.4 Create SwiftUI Umbrella Module
- [ ] Create `LexicalSwiftUI/module.swift` with conditional re-exports

### 8.5 Verify Phase 8 Complete
- [ ] SwiftUI wrapper works on iOS
- [ ] SwiftUI wrapper works on macOS
- [ ] Same API on both platforms

---

## Phase 9: Documentation & Cleanup

### 9.1 Update Documentation
- [ ] Update README with macOS support
- [ ] Document any API differences between platforms
- [ ] Add macOS to installation instructions

### 9.2 Create Example Apps
- [ ] Create/update iOS example app
- [ ] Create macOS example app
- [ ] Demonstrate cross-platform usage

### 9.3 Final Cleanup
- [ ] Remove any remaining `#if` conditionals that aren't needed
- [ ] Ensure consistent code style across targets
- [ ] Review and remove any dead code

### 9.4 Final Verification
- [ ] `swift build` succeeds on macOS for all targets
- [ ] `swift build` succeeds on iOS for all targets
- [ ] `swift test` passes on all platforms
- [ ] Example apps work correctly

---

## Quick Reference: Key STTextView Files

| Feature | STTextView File |
|---------|-----------------|
| Package structure | `Package.swift` |
| Umbrella module | `Sources/STTextView/module.swift` |
| Shared protocol | `Sources/STTextViewCommon/STTextViewProtocol.swift` |
| AppKit main view | `Sources/STTextViewAppKit/STTextView.swift` |
| NSTextInputClient | `Sources/STTextViewAppKit/STTextView+NSTextInputClient.swift` |
| Key handling | `Sources/STTextViewAppKit/STTextView+Key.swift` |
| Mouse handling | `Sources/STTextViewAppKit/STTextView+Mouse.swift` |
| Selection | `Sources/STTextViewAppKit/STTextView+Select.swift` |
| Copy/paste | `Sources/STTextViewAppKit/STTextView+CopyPaste.swift` |
| Undo | `Sources/STTextViewAppKit/STTextView+Undo.swift` |
| Delegate | `Sources/STTextViewAppKit/STTextViewDelegate.swift` |
| SwiftUI AppKit | `Sources/STTextViewSwiftUIAppKit/TextView.swift` |
| SwiftUI UIKit | `Sources/STTextViewSwiftUIUIKit/TextView.swift` |

---

## Notes for Agent

1. **Build frequently** - Run `swift build` after each major change to catch issues early
2. **Test incrementally** - Don't wait until the end to test
3. **Commit often** - Commit after completing each numbered task or sub-phase
4. **Reference STTextView** - When stuck, read the referenced files for implementation patterns
5. **Keep parity** - The AppKit implementation should mirror UIKit's structure and API
6. **Document decisions** - Add comments explaining platform-specific choices
