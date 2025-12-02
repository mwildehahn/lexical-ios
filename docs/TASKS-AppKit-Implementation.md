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
- [x] Add `.macOS(.v13)` to platforms array
- [x] Create `LexicalCore` target with no dependencies
- [x] Create `LexicalUIKit` target depending on `LexicalCore`
- [x] Create `LexicalAppKit` target depending on `LexicalCore` with `.when(platforms: [.macOS])`
- [x] Update main `Lexical` target to use platform-conditional dependencies
- [x] Verify package resolves: `swift package resolve`

**STTextView Reference:**
- `/Users/mh/labs/STTextView/Package.swift` - Full example of platform-conditional targets

### 1.2 Create Umbrella Module
- [x] Create `Sources/Lexical/` directory (if restructuring)
- [x] Create `Sources/Lexical/module.swift` with conditional re-exports:
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
- [x] Create `Sources/LexicalCore/`
- [x] Create `Sources/LexicalUIKit/`
- [x] Create `Sources/LexicalAppKit/`
- [x] Verify build succeeds with empty targets: `swift build`

---

## Phase 2: Extract LexicalCore

### 2.1 Identify Platform-Agnostic Files
- [x] Audit each file in current `Lexical/` for UIKit imports
- [x] Create list of files with NO UIKit dependencies (candidates for Core)
- [x] Create list of files with UIKit dependencies (stay in UIKit target)

**Audit Results:**
Files WITHOUT UIKit imports (32 files) - candidates for Core:
- Core: EditorContext, EditorState, Errors, FeatureFlags, LexicalRuntime, Mutations, StyleEvents, TextUtils, Updates
- Nodes: ElementNode, HeadingNode, LineBreakNode, PlaceholderNode, UnknownNode
- Selection: BaseSelection, Point
- Helper: FenwickTree, KeyedDiff, Logging, NSAttributedStringKey+Extensions, ObjCHelpers, PlanDiff, RangeCacheFenwick, RangeCacheIncremental, RangeCacheIndexing, RangeHelpers, SelectionHelpers, Theme
- Plugin: Plugin.swift
- TextKit: TextKitUtils

Files that have `import UIKit` but don't use UIKit types (can change import to Foundation):
- Node.swift, RootNode.swift, ParagraphNode.swift, CodeHighlightNode.swift

Files with actual UIKit dependencies (need abstraction or stay in UIKit):
- TextNode.swift (UIColor, UIRectFill)
- CodeNode.swift (UIColor, UIGraphicsGetCurrentContext)
- QuoteNode.swift (UIColor, UIEdgeInsets, UIBezierPath)
- DecoratorNode.swift, DecoratorContainerNode.swift, DecoratorBlockNode.swift (UIView)
- LexicalView.swift, TextView.swift, etc. (UIKit views)

**Initial Core files added:**
- [x] `PlatformTypes.swift` - Cross-platform type aliases (LexicalColor, LexicalFont, etc.)
- [x] `FeatureFlags.swift` - Feature flag configuration
- [x] `LexicalRuntime.swift` - Runtime configuration
- [x] `Errors.swift` - LexicalError enum

### 2.2 Split and Move Constants (Foundation for everything else)

**Analysis:** `Constants.swift` contains many types. Some are pure Foundation, others have UIKit dependencies or depend on Node/EditorState types. We must split this file first.

**Step 2.2.1: Create CoreTypes.swift with pure Foundation types**
- [x] Create `Sources/LexicalCore/CoreTypes.swift`
- [x] Move `NodeType` struct (no deps)
- [x] Move `Mode` enum (no deps)
- [x] Move `Direction` enum (no deps)
- [x] Move `Destination` enum (no deps)
- [x] Move `CommandType` struct (no deps)
- [x] Move `CommandPriority` enum (no deps)
- [x] Move `TextFormatType` enum (no deps)
- [x] Move `DirtyStatusCause` enum (no deps)
- [x] Move `DirtyType` enum (no deps)
- [x] Move `EditorUpdateReason` enum (no deps)
- [x] Move `TextStorageEditingMode` enum (no deps)
- [x] Move `TextTransform` enum (no deps)
- [x] Move `CustomDrawingLayer` enum (no deps)
- [x] Move `CustomDrawingGranularity` enum (no deps)
- [x] Move `BlockLevelAttributes` class (uses CGFloat only)
- [x] Move `DirtyNodeMap` typealias
- [x] Verify build: `swift build --target LexicalCore`

**Step 2.2.2: Create NodeKey typealias**
- [x] Add `public typealias NodeKey = String` to CoreTypes.swift
- [x] Verify build

**Step 2.2.3: Keep platform-specific constants in original location**
- [x] `LexicalConstants.defaultFont` uses UIFont - stays in Lexical/UIKit
- [x] `LexicalConstants.defaultColor` uses UIColor - stays in Lexical/UIKit
- [x] Add imports in original Constants.swift to use CoreTypes from LexicalCore
- [x] Verify Lexical target still builds

### 2.3 Move Theme System to Core
- [x] Copy `Theme.swift` to `Sources/LexicalCore/Theme.swift`
- [x] Remove UIKit import (uses Foundation only)
- [x] Update to import CoreTypes if needed
- [x] Verify build: `swift build --target LexicalCore`

### 2.4 Move Helper Utilities to Core

**Step 2.4.1: Move standalone helpers (no Node dependencies)**
- [x] Move `Helper/FenwickTree.swift` to `Sources/LexicalCore/Helper/`
- [x] Move `Helper/KeyedDiff.swift` to `Sources/LexicalCore/Helper/`
- [ ] Move `Helper/PlanDiff.swift` to `Sources/LexicalCore/Helper/` - **BLOCKED: depends on Editor, EditorState, RangeCacheItem**
- [ ] Move `Helper/ObjCHelpers.swift` to `Sources/LexicalCore/Helper/` - **BLOCKED: depends on Editor**
- [x] Move `Helper/NSAttributedStringKey+Extensions.swift` to `Sources/LexicalCore/Helper/`
- [x] Verify build after each move

**Step 2.4.2: Move Serialization.swift**
- [ ] Move `Core/Serialization.swift` to `Sources/LexicalCore/` - **BLOCKED: depends on Node types (RootNode, TextNode, etc.)**
- [ ] Fix any import issues
- [ ] Verify build

### 2.5 Move Node System to Core

**Step 2.5.1: Move Node.swift (base class)**
- [x] Copy `Core/Nodes/Node.swift` to `Sources/LexicalCore/Nodes/Node.swift`
- [x] Change `import UIKit` to `import Foundation`
- [x] Identify and list missing dependencies (documented below)
- [ ] Resolve dependencies and verify build

**Node.swift Dependencies Discovered:**

*Types needed (must be moved to LexicalCore):*
- `Editor` - main editor class (complex, many UIKit deps)
- `EditorState` - editor state class
- `ElementNode` - base class for element nodes
- `TextNode`, `RootNode`, `ParagraphNode`, `HeadingNode`, `QuoteNode`
- `CodeNode`, `CodeHighlightNode`, `LineBreakNode`, `PlaceholderNode`
- `DecoratorNode`, `DecoratorBlockNode`, `DecoratorContainerNode`
- `RangeSelection`, `BaseSelection` - selection types

*Utility functions needed:*
- `getActiveEditor()`, `getActiveEditorState()` - from Updates.swift
- `errorOnReadOnly()`, `isReadOnlyMode()` - from Updates.swift
- `generateKey()`, `getNodeByKey()` - from Utils.swift
- `internallyMarkNodeAsDirty()`, `internallyMarkSiblingsAsDirty()` - from Utils.swift
- `isElementNode()`, `isRootNode()`, `isTextNode()` - from Utils.swift
- `getSelection()`, `removeFromParent()` - from Utils.swift
- `maybeMoveChildrenSelectionToParent()` - from Utils.swift
- `moveSelectionPointToSibling()`, `moveSelectionPointToEnd()` - from SelectionHelpers.swift
- `updateElementSelectionOnCreateDeleteNode()` - from SelectionHelpers.swift

*Constants needed:*
- `LexicalConstants.uninitializedNodeKey` - from Constants.swift
- `kRootNodeKey` - from EditorState.swift

**Step 2.5.2: Move required utilities for Node**
Given the extensive dependencies, we need to move most of the core system together.

*Phase A: Move constants and simple types*
- [x] Move `kRootNodeKey` to LexicalCore/CoreTypes.swift
- [x] Add `LexicalCoreConstants.uninitializedNodeKey` to LexicalCore/CoreTypes.swift
- [x] Add `StringExtensions.swift` with `lengthAsNSString()` method

**Key Finding: Deep Coupling**
Attempted to move Node.swift and related types but discovered deep coupling:
- Node.swift depends on ~15 utility functions from Utils.swift, SelectionHelpers.swift
- Utility functions depend on Editor and EditorState
- Editor has heavy UIKit dependencies (decorators, text storage, etc.)
- Selection types depend on Node types (circular dependency)

**Revised Approach Needed:**
Instead of moving Node to Core, consider:
1. **Protocol Extraction**: Create protocols in LexicalCore that Editor/EditorState conform to
2. **Dependency Injection**: Pass editor/state access via protocols rather than global functions
3. **Gradual Migration**: Move types one at a time with protocol-based dependencies

*Phase B: Protocol Extraction (Started)*
Created foundation protocols in LexicalCore to enable future Node migration:

- [x] Create `NodeContext` protocol in `LexicalCore/Protocols/NodeContext.swift`
  - Defines operations Node needs: node map access, dirty tracking, key generation, selection ops
- [x] Create `NodeProtocol`, `ElementNodeProtocol`, `TextNodeProtocol`, `DecoratorNodeProtocol`
  - Abstract interfaces for node types
- [x] Create `BaseSelectionProtocol`, `RangeSelectionProtocol`, `PointProtocol`
  - Abstract interfaces for selection types
- [x] Create `NodeContextProvider` for dependency injection
  - Will be used when Node.swift is moved to LexicalCore
- [x] Move `SelectionType` to `LexicalCore/CoreTypes.swift`
  - Removed duplicate from `Lexical/Core/Selection/Point.swift`
- [x] Move `TextFormat` to `LexicalCore/TextFormat.swift`
  - Removed duplicate from `Lexical/Core/Nodes/TextNode.swift`

*Phase C-D: Deferred*
The remaining phases require the Lexical target to implement the protocols:
- [ ] Create concrete `NodeContext` implementation in Lexical target
- [ ] Wire up `NodeContextProvider` in EditorContext
- [ ] Refactor Node.swift to use protocols instead of concrete types
- [ ] Move Node.swift to LexicalCore with protocol-based dependencies

**Step 2.5.3: Move ElementNode.swift**
- [ ] Copy `Core/Nodes/ElementNode.swift` to `Sources/LexicalCore/Nodes/`
- [ ] Fix imports (uses Foundation only)
- [ ] Verify build

**Step 2.5.4: Move simple node types (no UIKit usage)**
- [ ] Move `LineBreakNode.swift` to LexicalCore/Nodes/
- [ ] Move `HeadingNode.swift` to LexicalCore/Nodes/
- [ ] Move `PlaceholderNode.swift` to LexicalCore/Nodes/
- [ ] Move `UnknownNode.swift` to LexicalCore/Nodes/
- [ ] Verify build after each move

**Step 2.5.5: Move nodes with UIKit imports but no actual usage**
- [ ] Move `RootNode.swift` - change `import UIKit` to `import Foundation`
- [ ] Move `ParagraphNode.swift` - change `import UIKit` to `import Foundation`
- [ ] Move `CodeHighlightNode.swift` - change `import UIKit` to `import Foundation`
- [ ] Verify build after each move

**Step 2.5.6: Move nodes that need platform abstraction**
- [ ] Move `TextNode.swift` - replace UIColor with LexicalColor, UIRectFill with lexicalRectFill
- [ ] Move `CodeNode.swift` - replace UIColor/UIGraphicsGetCurrentContext with platform abstractions
- [ ] Move `QuoteNode.swift` - replace UIColor/UIEdgeInsets/UIBezierPath with platform abstractions
- [ ] Verify build after each move

**Step 2.5.7: Decorator nodes - may need to stay in UIKit**
DecoratorNode and children use UIView directly. Options:
- [ ] Option A: Keep DecoratorNode.swift in LexicalUIKit, create protocol in Core
- [ ] Option B: Create DecoratorNodeProtocol in Core, implementations in UIKit/AppKit
- [ ] Document decision and implement chosen approach
- [ ] Verify build

### 2.6 Move Selection Logic to Core

**Step 2.6.1: Move selection base types**
- [ ] Move `Selection/Point.swift` to `Sources/LexicalCore/Selection/`
- [ ] Move `Selection/BaseSelection.swift` to `Sources/LexicalCore/Selection/`
- [ ] Verify build

**Step 2.6.2: Move selection implementations**
- [ ] Move `Selection/RangeSelection.swift` to LexicalCore (has UIKit imports - audit actual usage)
- [ ] Move `Selection/NodeSelection.swift` to LexicalCore (has UIKit imports - audit actual usage)
- [ ] Move `Selection/GridSelection.swift` to LexicalCore (has UIKit imports - audit actual usage)
- [ ] For any UIKit-specific selection code, extract to LexicalUIKit
- [ ] Verify build

### 2.7 Move EditorState to Core
- [ ] Move `EditorState.swift` to `Sources/LexicalCore/`
- [ ] Audit for any UIKit dependencies
- [ ] Verify build

### 2.8 Move Reconciler to Core (Complex - many dependencies)
- [ ] Audit `Reconciler.swift` for all dependencies
- [ ] Audit `OptimizedReconciler.swift` for all dependencies
- [ ] Move helper files needed by reconciler first
- [ ] Move `Reconciler.swift` to LexicalCore
- [ ] Move `OptimizedReconciler.swift` to LexicalCore
- [ ] Replace any UIKit types with platform abstractions
- [ ] Verify build

### 2.9 Verify Phase 2 Complete
- [ ] `swift build --target LexicalCore` succeeds
- [ ] `swift build --target LexicalUIKit` succeeds
- [ ] `swift build --target Lexical` succeeds (iOS)
- [ ] Run existing tests to verify no regressions
- [ ] Commit Phase 2 changes

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
