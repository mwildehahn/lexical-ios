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
7. **Commit frequently** - Create logical commits as you complete related tasks. Don't wait until an entire phase is complete. Good commit boundaries include:
   - Completing a numbered task or sub-task
   - Getting the build working after a set of related changes
   - Adding a new file or moving files
   - Fixing a category of errors (e.g., "wrap all UIKit imports in conditional compilation")

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

*Phase C: NodeContext Implementation (Completed)*
Created the bridge between LexicalCore protocols and Lexical concrete types:

- [x] Create `NodeContextImpl` in `Lexical/Core/NodeContextImpl.swift`
  - Implements `NodeContext` protocol from LexicalCore
  - Bridges protocol method calls to existing global functions (generateKey, internallyMarkNodeAsDirty, etc.)
  - Selection-related methods return nil for now (full implementation deferred until Node migration)
- [x] Wire up `NodeContextProvider` in `EditorContext.withContext()`
  - NodeContextProvider.current is set when entering update/read blocks
  - Enables LexicalCore types to access editor context via protocol

*Phase D: Node Migration (Deferred)*
The remaining phases require refactoring Node.swift to use the protocol-based dependencies:
- [ ] Refactor Node.swift to use `NodeContextProvider.current` instead of global functions
- [ ] Make Node, ElementNode, TextNode conform to their respective protocols
- [ ] Make Point, RangeSelection, BaseSelection conform to their respective protocols
- [ ] Move Node.swift to LexicalCore with protocol-based dependencies

*Phase E: Conditional Compilation Approach (Completed)*
Instead of fully migrating to LexicalCore, wrapped UIKit-specific code with `#if canImport(UIKit)` guards to enable macOS builds:

- [x] Wrap DecoratorNode.swift `getAttributedStringAttributes` in UIKit guards
- [x] Wrap Editor.swift `CustomDrawingHandlerInfo`, `registerCustomDrawing` in UIKit guards
- [x] Make `UpdateBehaviourModificationMode` cross-platform with platform-specific initializers
- [x] Wrap Editor.swift `rangeCache` initialization and access in UIKit guards
- [x] Wrap Editor.swift frontend-related methods in UIKit guards
- [x] Wrap RangeSelection.swift `modify`, `applyNativeSelection`, `applySelectionRange`, `init(nativeSelection:)` in UIKit guards
- [x] Add AppKit stubs for `deleteCharacter`, `deleteWord`, `deleteLine` in RangeSelection.swift
- [x] Wrap SelectionUtils.swift `createNativeSelection`, `validatePosition`, `stringLocationForPoint`, `createSelection` in UIKit guards
- [x] Update `getSelection()` to return nil on AppKit when no existing selection
- [x] Wrap Utils.swift `decoratorView`, `destroyCachedDecoratorView`, `getAttributedStringFromFrontend` in UIKit guards
- [x] Wrap RootNode.swift `LexicalReadOnlyTextKitContext` check in UIKit guards
- [x] Wrap Events.swift `onSelectionChange`, `registerRichText` and related functions in UIKit guards
- [x] Wrap ReconcilerShadowCompare.swift entire file in UIKit guards
- [x] Add NSEdgeInsets Equatable conformance to PlatformTypes.swift for macOS
- [x] **BUILD SUCCESS: `swift build --target Lexical` now succeeds on macOS**

*Technical Debt Note:*
This approach creates conditional compilation throughout Core files rather than clean separation. This is pragmatic for initial macOS support but should be revisited in favor of proper LexicalCore extraction when time permits.

*Phase F: Plugin Conditional Compilation (Completed)*
Added conditional compilation to all plugins to enable `swift build` to succeed on macOS:

- [x] Add `Exports.swift` to Lexical target with `@_exported import LexicalCore`
  - Enables plugins to access LexicalCore types through Lexical module
- [x] **EditorHistoryPlugin**: Remove unnecessary UIKit import (no actual UIKit usage)
  - `History.swift`, `HistoryConstants.swift`, `EditorHistoryPlugin.swift`
- [x] **LexicalListPlugin**: Wrap UIKit-specific code in conditional compilation
  - `ListPlugin.swift`: Wrap `registerCustomDrawing` block and `UIImpactFeedbackGenerator` usage
  - `ListItemNode.swift`: Remove unnecessary UIKit import
  - `ListStyleEvents.swift`: Wrap `resetTypingAttributes` call
- [x] **LexicalLinkPlugin**: Wrap UIKit-specific code in conditional compilation
  - `LinkNode.swift`: Remove unnecessary UIKit import
  - `LinkPlugin.swift`: Wrap `LexicalView` property and usage
- [x] **LexicalAutoLinkPlugin**: Remove unnecessary UIKit imports
  - `AutoLinkPlugin.swift`, `AutoLinkNode.swift`
- [x] **LexicalCodeHighlightPlugin**: Remove unnecessary UIKit import
  - `CodeHighlightPlugin.swift`
- [x] **LexicalHTML**: Remove unnecessary UIKit import
  - `HTMLPlugin.swift`
- [x] **SelectableDecoratorNode**: Wrap entire file contents in UIKit guards (fully UIKit-dependent)
  - `SelectableDecoratorNode.swift`, `SelectableDecoratorView.swift`
- [x] **LexicalInlineImagePlugin**: Wrap UIKit-dependent code
  - `InlineImagePlugin.swift`: Wrap entire file (depends on ImageNode)
  - `ImageNode.swift`: Wrap entire file (uses UIImageView, UIImage)
  - `SelectableImageNode.swift`: Wrap entire file (uses UIKit views)
- [x] **LexicalTablePlugin**: Wrap entire files in UIKit guards (fully UIKit-dependent)
  - `TableNode.swift`, `TableNodeView.swift`, `TableNodeScrollableWrapperView.swift`
- [x] **LexicalMentionsPlugin**: Add cross-platform color support
  - `MentionNode.swift`: Conditional UIColor/NSColor usage
- [x] Remove unnecessary UIKit guard from `SelectionHelpers.swift`
  - Functions use only Foundation/LexicalCore types, no UIKit needed
- [x] **BUILD SUCCESS: `swift build` now succeeds for all targets on macOS**

*Test Note:*
Tests are iOS-specific (use UIKit types like `LexicalView`, `LexicalReadOnlyTextKitContext`) and should be run on iOS simulators. macOS test support would require AppKit test infrastructure.

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
- [x] Create `LexicalCore/LexicalViewProtocol.swift`
- [x] Define protocol with associated types for platform-specific types
- [x] Include all methods needed by Editor to communicate with view layer

**STTextView Reference:**
- `/Users/mh/labs/STTextView/Sources/STTextViewCommon/STTextViewProtocol.swift` - Protocol with associated types pattern

**Implementation Notes:**
Created `Sources/LexicalCore/Protocols/LexicalViewProtocol.swift` with:
- `NativeSelectionProtocol` - Platform-agnostic selection representation
- `NativeSelectionModificationType` - Move vs extend selection
- `FrontendProtocol` - Interface between Editor and view layer
- `LexicalViewProtocol` - Public API for Lexical views with associated types

### 2.8 Verify Phase 2 Complete
- [x] `swift build --target LexicalCore` succeeds
- [x] `swift build --target LexicalUIKit` succeeds
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
- [x] Create `LexicalAppKit/LexicalView.swift`
- [x] Inherit from `NSView`
- [ ] Conform to `LexicalViewProtocol` (protocol defined but conformance pending)
- [x] Implement basic initializers
- [x] Verify builds: `swift build --target LexicalAppKit`

**Implementation Notes:**
Created `Sources/LexicalAppKit/LexicalView.swift` with:
- `LexicalView` class inheriting from NSView
- `LexicalViewDelegate` protocol mirroring UIKit version
- `LexicalPlaceholderText` configuration class
- NSScrollView wrapper for the text view
- Public API matching UIKit version (editor, text, attributedText, etc.)
- First responder and accessibility support

**STTextView Reference:**
- `/Users/mh/labs/STTextView/Sources/STTextViewAppKit/STTextView.swift` - Main AppKit text view

### 4.2 Create AppKit TextView
- [x] Create `LexicalAppKit/TextView.swift`
- [x] Inherit from `NSTextView`
- [x] Set up TextKit stack (NSTextStorage, NSLayoutManager, NSTextContainer)
- [x] Connect to LexicalView

**Implementation Notes:**
Created `Sources/LexicalAppKit/TextView.swift` with:
- `TextViewAppKit` class inheriting from NSTextView
- `TextStorageAppKit` custom NSTextStorage with Editor integration
- Custom NSLayoutManager and NSTextContainer setup
- Placeholder text support
- First responder handling
- NSTextViewDelegate implementation

**Architecture Note:**
LexicalAppKit depends on the main Lexical target (not just LexicalCore) because Editor and EditorConfig
are still in Lexical/. The Lexical target builds on macOS via conditional compilation.

**STTextView Reference:**
- `/Users/mh/labs/STTextView/Sources/STTextViewAppKit/STTextView.swift` - Lines 1-200 for setup

### 4.3 Implement NSTextInputClient
- [x] Create `LexicalAppKit/TextView+NSTextInputClient.swift`
- [x] Implement `insertText(_:replacementRange:)`
- [x] Implement `setMarkedText(_:selectedRange:replacementRange:)`
- [x] Implement `unmarkText()`
- [x] Implement `selectedRange()` -> `NSRange` (provided by NSTextView)
- [x] Implement `markedRange()` -> `NSRange` (provided by NSTextView)
- [x] Implement `hasMarkedText()` -> `Bool` (provided by NSTextView)
- [x] Implement `attributedSubstring(forProposedRange:actualRange:)`
- [x] Implement `validAttributesForMarkedText()` -> `[NSAttributedString.Key]`
- [x] Implement `firstRect(forCharacterRange:actualRange:)` -> `NSRect`
- [x] Implement `characterIndex(for:)` -> `Int`

**Implementation Notes:**
Since TextViewAppKit inherits from NSTextView, most NSTextInputClient methods are provided by the superclass.
The extension in `TextView+NSTextInputClient.swift` overrides key methods:
- `insertText(_:replacementRange:)` - Adds delegate check and placeholder updates
- `setMarkedText/unmarkText` - Hooks for Lexical composition tracking
- Geometry methods for IME window positioning

**STTextView Reference:**
- `/Users/mh/labs/STTextView/Sources/STTextViewAppKit/STTextView+NSTextInputClient.swift` - Full implementation

### 4.4 Implement Keyboard Handling
- [x] Create `LexicalAppKit/TextView+Keyboard.swift`
- [x] Override `keyDown(with:)` - Routes through input context for IME support
- [x] Override `performKeyEquivalent(with:)` -> `Bool`
- [x] Handle deletion operations (backspace, delete, word delete, line delete)
- [x] Handle newlines and tabs
- [x] Handle cut/paste operations

**Implementation Notes:**
Keyboard handling uses NSTextView's built-in responder chain. The extension adds:
- Input context routing for IME support
- Placeholder visibility updates after all text-modifying operations
- Hook points for Lexical command integration (to be expanded)

**STTextView Reference:**
- `/Users/mh/labs/STTextView/Sources/STTextViewAppKit/STTextView+Key.swift` - Key event handling
- `/Users/mh/labs/STTextView/Sources/STTextViewAppKit/Extensions/NSEvent+Helpers.swift` - Key helpers

### 4.5 Implement Selection Management
- [x] Create `LexicalAppKit/NativeSelection.swift`
- [x] Implement selection using `NSRange`
- [x] Create `NativeSelectionAppKit` conforming to `NativeSelectionProtocol`
- [ ] Connect to Lexical's selection system (partial - hooks in place)

**Implementation Notes:**
Created `NativeSelection.swift` with:
- `NativeSelectionAppKit` struct capturing NSTextView selection state
- Selection change handling hooks (`handleSelectionChange`)
- `applySelection` for programmatic selection updates

### 4.6 Implement Copy/Paste
- [x] Create `LexicalAppKit/CopyPasteHelpers.swift`
- [x] Use `NSPasteboard` instead of `UIPasteboard`
- [x] Implement `copy:`, `cut:`, `paste:` actions
- [x] Handle rich text (RTF) and plain text pasteboard types
- [x] Define custom `.lexicalNodes` pasteboard type

**Implementation Notes:**
Created `CopyPasteHelpers.swift` with:
- Multi-format copy (Lexical nodes, RTF, plain text)
- Paste with format preference (Lexical > RTF > plain text)
- Drag-and-drop type declarations

### 4.7 Implement First Responder
- [x] First responder handled in `TextView.swift` via NSTextView
- [x] `becomeFirstResponder()` and `resignFirstResponder()` override
- [x] Delegate notifications for editing begin/end

**Note:** NSTextView provides first responder handling. Overrides added in TextView.swift.

### 4.8 Implement Mouse Handling
- [x] Create `LexicalAppKit/TextView+Mouse.swift`
- [x] Override `mouseDown(with:)` - with link click handling
- [x] Override `mouseDragged(with:)`
- [x] Override `mouseUp(with:)`
- [x] Override `rightMouseDown(with:)` for context menu
- [x] Cursor rect management

**Implementation Notes:**
NSTextView handles most mouse selection. Extension adds:
- Link click detection and handling
- Selection change notifications
- Context menu positioning

### 4.9 Implement Undo/Redo
- [x] Create `LexicalAppKit/TextView+Undo.swift`
- [x] Access `undoManager` property
- [x] Undo grouping helpers
- [x] `withoutUndoRegistration` utility

**Implementation Notes:**
NSTextView provides built-in undo when `allowsUndo = true`. Extension adds:
- Menu item validation
- Undo grouping helpers for batch operations
- Utility to perform changes without undo registration

### 4.10 Implement Scrolling
- [x] Scroll view integration in `LexicalView.swift`
- [x] `scrollRangeToVisible(_:)` provided by NSTextView
- [x] `scrollSelectionToVisible()` in LexicalView

**Note:** NSScrollView integration done in LexicalView. NSTextView provides scrollRangeToVisible.

### 4.11 Verify Phase 4 Complete
- [x] `swift build --target LexicalAppKit` succeeds
- [x] `swift build` succeeds for all platforms
- [ ] Basic text input works in AppKit test app (requires test app)

---

## Phase 5: TextKit Layer

### 5.1 Create AppKit LayoutManager
- [x] Create `LexicalAppKit/LayoutManager.swift`
- [x] Handle `NSFont` instead of `UIFont` in delegate methods
- [x] Override `showCGGlyphs` for link color fixes
- [x] Create `LayoutManagerDelegateAppKit` for text transform (uppercase/lowercase)

**STTextView Reference:**
- `/Users/mh/labs/STTextView/Sources/STTextViewAppKit/STTextView+NSTextLayoutManagerDelegate.swift`

**Implementation Notes:**
Created `Sources/LexicalAppKit/LayoutManager.swift` with:
- `LayoutManagerAppKit` class with custom drawing and decorator positioning
- `LayoutManagerDelegateAppKit` for glyph generation with text transforms
- Updated `TextViewAppKit` to use custom layout manager and delegate
- Updated `TextStorageAppKit` with decorator position cache and editing mode support

### 5.2 Create AppKit TextAttachment Support
- [x] Create `LexicalAppKit/TextAttachment.swift`
- [x] Handle `NSImage` instead of `UIImage`

**Implementation Notes:**
Created `Sources/LexicalAppKit/TextAttachment.swift` with:
- `TextAttachmentAppKit` class for decorator node attachments
- Stub for bounds calculation (full implementation pending decorator view support)
- Empty image override to prevent AppKit placeholder drawing

### 5.3 Create AppKit AttributesUtils
- [x] Create `LexicalAppKit/AttributesUtils.swift`
- [x] Use `NSFont`, `NSColor` instead of UIKit equivalents
- [x] Maintain same public API as UIKit version (except block-level attributes which depend on UIKit-only types)

**Implementation Notes:**
Created `Sources/LexicalAppKit/AttributesUtils.swift` with:
- `AttributeUtilsAppKit` enum with attribute styling functions
- `LexicalConstantsAppKit` for default font and color
- Paragraph style generation from attributes
- NSAttributedString.Key extensions (matching UIKit)
- Note: `applyBlockLevelAttributes` not ported (requires UIKit-only `RangeCacheItem`)

### 5.4 Verify Phase 5 Complete
- [x] `swift build` succeeds for all targets
- [ ] Rich text rendering works on macOS (requires test app)
- [ ] Font and color attributes applied correctly (requires test app)

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
