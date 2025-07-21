# Lexical iOS Swift 6 Migration Plan: Thread Dictionary to MainActor

## Overview
Migrate Lexical iOS from thread dictionary pattern to MainActor for Swift 6 compatibility while maintaining API compatibility. When working on this plan, use this space to add notes / context / record progress so we can be efficient with the context window as we pass this work off between LLM agents.

- **Strategy Update**: Mark entire classes we own with @MainActor instead of individual methods
- **Next Steps**: Run build to identify remaining compilation errors
- **Build Command**: `swift build --sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" -Xswiftc "-target" -Xswiftc "x86_64-apple-ios13.0-simulator"`

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
Mark Editor and related classes as @MainActor since they already run on main thread in practice. Prefer to mark classes we own in the library with @MainActor vs adding it to each individual method.

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

## Notes for Sub-Agents

1. **Always check**: Is this code already on MainActor? Most Lexical code already is.
2. **Preserve API**: Keep functions synchronous, no async/await unless absolutely necessary.
3. **Watch for**: The `isUpdating` flag pattern - this needs to work correctly with new context

## Migration Command Reference

```bash
# NOTE: when running these build commands, let's think about being efficient with the token output for processing so use ` |head` with a limit so we can work our way through the errors in a context efficient way.

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

3. **Test the changes**:
   - Run all unit tests
   - Test the Playground app
   - Verify no performance regressions

4. **Final cleanup**:
   - Remove any remaining thread dictionary code
   - Update Package.swift to Swift 6
   - Update documentation

## Strategy Change (December 2024)

### Old Approach
- Adding @MainActor to individual methods that showed compilation errors
- Time-consuming and creates inconsistent API surface

### New Approach  
- Mark entire classes we own with @MainActor
- All methods in the class automatically become MainActor-isolated
- Cleaner, more consistent, and easier to maintain
- Node class marked as @MainActor means ALL node subclasses inherit this

### Benefits
1. **Consistency**: All methods in a class have the same isolation
2. **Simplicity**: No need to annotate each method individually  
3. **Inheritance**: Subclasses automatically inherit MainActor isolation
4. **Maintenance**: Easier to understand and maintain the codebase

### Known Issues to Address

1. **Protocol Conformance**: Some methods like `deleteCharacter` and `insertParagraph` in RangeSelection show warnings about MainActor isolation and protocol conformance. May need to update BaseSelection protocol.

2. **Decodable Conformance**: SerializedNodeArray shows a warning about MainActor-isolated init(from:) and Decodable protocol.

3. **Cross-actor calls**: Any remaining errors about calling MainActor-isolated functions from non-isolated contexts.

## Progress Tracking (December 2024)

### Phase 1: Core Migration - COMPLETED ✅
- [x] Create EditorContext.swift
- [x] Update Updates.swift
- [x] Update Editor.swift
- [x] Run basic tests

### Phase 2: Full Migration - IN PROGRESS
- [x] Update core selection files (Point, RangeSelection, NodeSelection, SelectionUtils)
- [x] Update Utils.swift
- [x] Update Reconciler.swift (partial)
- [x] Update Serialization.swift (partial)
- [x] **NEW STRATEGY**: Mark entire classes with @MainActor instead of individual methods
- [x] Marked Node class as @MainActor (all subclasses inherit this)
- [x] Marked UI/TextKit classes as @MainActor
- [x] Fixed many Helper functions (CopyPasteHelpers, SelectionHelpers, RangeHelpers, AttributeUtils)
- [ ] **Fix remaining compilation errors** (~1242 errors remaining)
- [ ] Update all plugins
- [ ] Update tests
- [ ] Update documentation

### Phase 2.1: Completed Updates (December 2024)
**Classes marked with @MainActor:**
- [x] Node.swift - Entire class marked (all node subclasses inherit)
- [x] Editor.swift - Already marked in Phase 1
- [x] EditorState.swift - Already marked in Phase 1
- [x] TextView.swift & TextViewDelegate
- [x] LexicalView.swift
- [x] LayoutManager.swift
- [x] TextStorage.swift
- [x] TextContainer.swift
- [x] TextAttachment.swift
- [x] LayoutManagerDelegate.swift
- [x] InputDelegateProxy.swift
- [x] ResponderForNodeSelection.swift
- [x] AttributeUtils - Entire enum marked

**Individual method/function updates:**
- [x] Plugin.swift - installedInstance()
- [x] GarbageCollection.swift - garbageCollectDetachedNodes(), garbageCollectDetachedDeepChildNodes()
- [x] Events.swift - shouldInsertTextAfterOrBeforeTextNode()
- [x] SelectionHelpers.swift - cloneWithProperties(), getIndexFromPossibleClone(), getParentAvoidingExcludedElements(), copyLeafNodeBranchToRoot()
- [x] CopyPasteHelpers.swift - setPasteboard(), insertDataTransferForRichText(), insertPlainText(), insertRTF(), insertGeneratedNodes(), generateArrayFromSelectedNodes(), basicInsertStrategy()
- [x] RangeHelpers.swift - performRangeSearch(), performRangeSearchWithPayload(), searchInNode()
- [x] Serialization.swift - Updated DeserializationConstructor typealias and defaultDeserializationMapping
- [x] Node.swift - Added nonisolated to init(from:) methods for Decodable conformance

### Phase 3: Cleanup
- [ ] Remove old thread dictionary code
- [ ] Update Package.swift to Swift 6
- [ ] Performance validation
- [ ] Update CI/CD for Swift 6

This migration maintains API compatibility while ensuring thread safety for Swift 6.