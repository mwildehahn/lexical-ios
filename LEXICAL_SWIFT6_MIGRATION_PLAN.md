# Lexical iOS Swift 6 Migration Plan: Thread Dictionary to MainActor

## Overview
Migrate Lexical iOS from thread dictionary pattern to MainActor for Swift 6 compatibility while maintaining API compatibility. When working on this plan, use this space to add notes / context / record progress so we can be efficient with the context window as we pass this work off between LLM agents.

## Current State Summary

### Thread Dictionary Pattern (Updates.swift)
```swift
// Current implementation uses thread-local storage
private let activeEditorThreadDictionaryKey = "kActiveEditor"
private let activeEditorStateThreadDictionaryKey = "kActiveEditorState"
private let readOnlyModeThreadDictionaryKey = "kReadOnlyMode"
private let previousParentUpdateBlocksThreadDictionaryKey = "kpreviousParentUpdateBlocks"
private let editorUpdateReasonThreadDictionaryKey = "kEditorUpdateReason"

// Access pattern
public func getActiveEditor() -> Editor? {
  return Thread.current.threadDictionary[activeEditorThreadDictionaryKey] as? Editor
}
```

### Key Facts
- **Thread Usage**: 99% main thread (UIKit integration)
- **API**: Synchronous, no async/await
- **Swift Version**: Currently targets Swift 5.6
- **Package.swift**: `swift-tools-version: 5.6`
- **Async Usage**: Only 2 instances of `DispatchQueue.main.async` in ImageNode classes

## Migration Strategy

### Phase 1: MainActor Annotation
Mark Editor and related classes as @MainActor since they already run on main thread in practice.

### Phase 2: Context Storage Replacement
Replace thread dictionary with a MainActor-isolated context manager.

### Phase 3: API Preservation
Maintain synchronous API by leveraging MainActor isolation.

## Detailed Migration Steps

### Step 1: Create New Context Manager
**File**: `Lexical/Core/EditorContext.swift`
```swift
@MainActor
final class EditorContext {
    private static var current: ContextStack?
    
    struct ContextStack {
        let editor: Editor?
        let editorState: EditorState?
        let readOnlyMode: Bool
        let updateReason: EditorUpdateReason?
        let previous: ContextStack?
        let updateStack: [Editor]
    }
    
    static func withContext<T>(
        editor: Editor?,
        editorState: EditorState?,
        readOnlyMode: Bool,
        updateReason: EditorUpdateReason?,
        operation: () throws -> T
    ) rethrows -> T {
        let previous = current
        let updateStack = previous?.updateStack ?? []
        let newStack = (editor != nil && !readOnlyMode) ? updateStack + [editor!] : updateStack
        
        current = ContextStack(
            editor: editor,
            editorState: editorState,
            readOnlyMode: readOnlyMode,
            updateReason: updateReason,
            previous: previous,
            updateStack: newStack
        )
        
        defer { current = previous }
        return try operation()
    }
    
    static func getActiveEditor() -> Editor? { current?.editor }
    static func getActiveEditorState() -> EditorState? { current?.editorState }
    static func isReadOnlyMode() -> Bool { current?.readOnlyMode ?? true }
    static func getUpdateReason() -> EditorUpdateReason? { current?.updateReason }
    static func isEditorInUpdateStack(_ editor: Editor) -> Bool {
        current?.updateStack.contains(editor) ?? false
    }
}
```

### Step 2: Update Core Classes
**Files to Update**:
1. `Lexical/Core/Editor.swift` - Add @MainActor
2. `Lexical/Core/EditorState.swift` - Add @MainActor where needed
3. `Lexical/Core/Updates.swift` - Replace thread dictionary calls

### Step 3: Migration Mapping

| Current Function | New Implementation | Used In |
|-----------------|-------------------|---------|
| `getActiveEditor()` | `EditorContext.getActiveEditor()` | Utils.swift, Node.swift, Mutations.swift, StatePersistencePlugin.swift |
| `getActiveEditorState()` | `EditorContext.getActiveEditorState()` | Utils.swift, Node.swift, Mutations.swift |
| `isReadOnlyMode()` | `EditorContext.isReadOnlyMode()` | Node.swift, Utils.swift |
| `runWithStateLexicalScopeProperties()` | `EditorContext.withContext()` | Editor.swift (7x), EditorState.swift (1x) |
| `isEditorPresentInUpdateStack()` | `EditorContext.isEditorInUpdateStack()` | Editor.swift (beginUpdate) |

### Step 4: Update Call Sites

#### Example Migration Pattern
```swift
// Before
try runWithStateLexicalScopeProperties(
    activeEditor: self,
    activeEditorState: pendingEditorState,
    readOnlyMode: false,
    editorUpdateReason: reason
) {
    // operations
}

// After
try EditorContext.withContext(
    editor: self,
    editorState: pendingEditorState,
    readOnlyMode: false,
    updateReason: reason
) {
    // operations
}
```

## Files Requiring Updates

### Critical Path (Must Update)
1. [ ] `Lexical/Core/Updates.swift` - Replace thread dictionary implementation
2. [ ] `Lexical/Core/Editor.swift` - Add @MainActor, update beginUpdate/beginRead
3. [ ] `Lexical/Core/EditorState.swift` - Update beginRead method
4. [ ] `Lexical/Core/Utils.swift` - Update helper functions
5. [ ] `Lexical/Core/Nodes/Node.swift` - Update getWritable()

### Secondary Updates (Can be batched)
1. [ ] `Lexical/Core/Mutations.swift` - Update handleTextMutation
2. [ ] `Lexical/Core/Reconciler.swift` - Verify MainActor compliance
3. [ ] `Plugins/LexicalStatePersistencePlugin/LexicalStatePersistencePlugin/StatePersistencePlugin.swift`
4. [ ] `Plugins/EditorHistoryPlugin/EditorHistoryPlugin/History.swift`

### UIKit Integration Points (Already Main Thread)
- `Lexical/TextView/TextView.swift` - All delegate methods
- `Lexical/LexicalView/LexicalView.swift` - UI framework integration

## Specific Code Locations

### Thread Dictionary Usage (Updates.swift)
- Lines 15-30: Global accessor functions
- Lines 125-161: Private implementation with `runWithStateLexicalScopeProperties`

### Call Sites in Editor.swift
- Line 663: `beginUpdate` - Main update mechanism
- Line 774: `beginRead` - Read-only access
- Line 750: Update listeners wrapper
- Line 970: `parseEditorState` - JSON parsing

### Documentation Updates Needed
- `Lexical/Documentation.docc/QuickStart.md` - Line 81: "You must not dispatch to another thread"
- Update to explain MainActor requirement

## Potential Issues & Solutions

### Issue 1: Background Thread Access
**Problem**: ImageNode classes use `DispatchQueue.main.async`
**Solution**: These are already dispatching to main, can be simplified with MainActor

### Issue 2: Plugin Compatibility
**Problem**: Plugins might assume any-thread access
**Solution**: Document MainActor requirement, provide migration guide

### Issue 3: Test Updates
**Problem**: Tests might need MainActor annotations
**Solution**: Use `@MainActor` on test classes or `MainActor.run {}`

### Issue 4: Objective-C Compatibility
**Problem**: Some classes like `Editor` are marked `@objc`
**Solution**: MainActor is compatible with @objc, but verify in practice

## Validation Checklist
- [ ] All tests pass
- [ ] No Swift 6 warnings about thread safety
- [ ] Performance unchanged (measure update/read operations)
- [ ] API remains synchronous
- [ ] Documentation updated
- [ ] Playground app works correctly

## Code Search Patterns for Sub-Agents

### Find Thread Dictionary Usage
```bash
grep -n "threadDictionary" Lexical/Core/Updates.swift
grep -rn "getActiveEditor()" Lexical/ Plugins/
grep -rn "getActiveEditorState()" Lexical/ Plugins/
grep -rn "runWithStateLexicalScopeProperties" Lexical/
```

### Find Potential Background Thread Usage
```bash
grep -rn "DispatchQueue" Lexical/ Plugins/
grep -rn "async" Lexical/ Plugins/
grep -rn "Task {" Lexical/ Plugins/
```

### Current Results Summary
- `threadDictionary`: Only in Updates.swift
- `getActiveEditor()`: ~15 call sites
- `DispatchQueue`: Only in ImageNode classes
- No `Task {` usage found

## Progress Tracking

### Phase 1: Core Migration
- [ ] Create EditorContext.swift
- [ ] Update Updates.swift
- [ ] Update Editor.swift
- [ ] Run basic tests

### Phase 2: Full Migration
- [ ] Update all call sites
- [ ] Update plugins
- [ ] Update tests
- [ ] Update documentation

### Phase 3: Cleanup
- [ ] Remove old thread dictionary code
- [ ] Update Package.swift to Swift 6
- [ ] Performance validation
- [ ] Update CI/CD for Swift 6

## Notes for Sub-Agents

1. **Always check**: Is this code already on MainActor? Most Lexical code already is.
2. **Preserve API**: Keep functions synchronous, no async/await unless absolutely necessary.
3. **Test incrementally**: Update one file, run tests, commit.
4. **Document assumptions**: If you make assumptions about thread safety, document them.
5. **Watch for**: The `isUpdating` flag pattern - this needs to work correctly with new context

## Migration Command Reference

```bash
# Build for iOS Simulator
swift build --sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
  -Xswiftc "-target" -Xswiftc "x86_64-apple-ios13.0-simulator"

xcodebuild test \
  -scheme Lexical \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5'

# Build with Swift 6 strict concurrency checking
swift build --sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
  -Xswiftc "-target" -Xswiftc "x86_64-apple-ios13.0-simulator" \
  -Xswiftc -swift-version -Xswiftc 6 \
  -Xswiftc -strict-concurrency=complete
```

## Progress Update - December 2024

### Completed Work

#### Phase 1: Core Migration - COMPLETED
- [x] Created `EditorContext.swift` with MainActor-isolated context manager
- [x] Updated `Updates.swift` to use EditorContext instead of thread dictionary
- [x] Added @MainActor to `Editor` class
- [x] Added @MainActor to `EditorState` class

#### Phase 2: Method Updates - IN PROGRESS
The following files have been updated with @MainActor annotations:

1. **Core/Updates.swift**
   - All public functions now use EditorContext
   - Removed thread dictionary implementation

2. **Core/Editor.swift**
   - Editor class marked as @MainActor
   - beginRead and beginUpdate methods work with new context

3. **Core/EditorState.swift**
   - EditorState class marked as @MainActor

4. **Core/Utils.swift**
   - Updated: getNodeByKey, generateKey, getCompositionKey, getRoot
   - Updated: decoratorView, getAttributedStringFromFrontend, setSelection

5. **Core/Selection/Point.swift**
   - Updated: updatePoint, getNode methods

6. **Core/Selection/RangeSelection.swift**
   - Updated: getPlaintext, insertParagraph, deleteCharacter, modify
   - Updated: applySelectionRange, init?(nativeSelection:), setTextNodeRange
   - Updated: insertText, insertLineBreak, deleteWord, deleteLine
   - Updated: applyNativeSelection, formatText, updateSelection

7. **Core/Selection/NodeSelection.swift**
   - Updated: getNodes, insertParagraph

8. **Core/Selection/SelectionUtils.swift**
   - Updated: getSelection, sanityCheckPoint, editorStateHasDirtySelection
   - Updated: stringLocationForPoint, createSelection, makeRangeSelection
   - Updated: normalizeSelectionPointsForBoundaries, selectPointOnNode
   - Updated: sanityCheckSelection, moveSelectionPointToSibling
   - Updated: createNativeSelection, updateElementSelectionOnCreateDeleteNode
   - Updated: updateSelectionResolveTextNodes, transferStartingElementPointToTextPoint
   - Updated: setBlocksType

9. **Core/Reconciler.swift**
   - Updated: reconcileSelection method

10. **Core/Serialization.swift**
    - Updated: SerializedNodeArray init(from decoder:)

### Next Steps

When resuming this migration:

1. **Run the build command** to see remaining compilation errors:
   ```bash
   swift build --sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
     -Xswiftc "-target" -Xswiftc "x86_64-apple-ios13.0-simulator"
   ```

2. **Continue fixing compilation errors** - likely remaining issues:
   - Protocol conformance issues (BaseSelection methods need @MainActor)
   - Any remaining functions that call MainActor-isolated code
   - Potential issues with Objective-C compatibility

3. **Update remaining files** that haven't been touched yet:
   - [ ] `Lexical/Core/Mutations.swift`
   - [ ] `Lexical/Core/Nodes/Node.swift` - Update getWritable()
   - [ ] Plugin files that use getActiveEditor/getActiveEditorState

4. **Test the changes**:
   - Run all unit tests
   - Test the Playground app
   - Verify no performance regressions

5. **Final cleanup**:
   - Remove any remaining thread dictionary code
   - Update Package.swift to Swift 6
   - Update documentation

### Known Issues to Address

1. **Protocol Conformance**: Some methods like `deleteCharacter` and `insertParagraph` in RangeSelection show warnings about MainActor isolation and protocol conformance. May need to update BaseSelection protocol.

2. **Decodable Conformance**: SerializedNodeArray shows a warning about MainActor-isolated init(from:) and Decodable protocol.

3. **Cross-actor calls**: Any remaining errors about calling MainActor-isolated functions from non-isolated contexts.

### Migration Pattern Reference

When you see an error like:
```
error: call to main actor-isolated global function 'getActiveEditor()' in a synchronous nonisolated context
```

Add `@MainActor` to the calling function:
```swift
// Before
public func someFunction() {
  let editor = getActiveEditor()
}

// After
@MainActor
public func someFunction() {
  let editor = getActiveEditor()
}
```

This migration maintains API compatibility while ensuring thread safety for Swift 6.