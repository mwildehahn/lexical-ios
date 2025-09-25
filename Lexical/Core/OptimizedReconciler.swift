/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import UIKit

// Optimized reconciler entry point. Initially a thin wrapper so we can land
// the feature flag, metrics, and supporting data structures incrementally.

internal enum OptimizedReconciler {
  // Instruction set for applying minimal changes to TextStorage
  enum Instruction {
    case delete(range: NSRange)
    case insert(location: Int, attrString: NSAttributedString)
    case setAttributes(range: NSRange, attributes: [NSAttributedString.Key: Any])
    case fixAttributes(range: NSRange)
    case decoratorAdd(key: NodeKey)
    case decoratorRemove(key: NodeKey)
    case decoratorDecorate(key: NodeKey)
    case applyBlockAttributes(nodeKey: NodeKey)
  }

  // MARK: - Instruction application & coalescing
  @MainActor
  private static func applyInstructions(_ instructions: [Instruction], editor: Editor) {
    guard let textStorage = editor.textStorage else { return }

    // Gather deletes and inserts
    var deletes: [NSRange] = []
    var inserts: [(Int, NSAttributedString)] = []
    var sets: [(NSRange, [NSAttributedString.Key: Any])] = []

    for inst in instructions {
      switch inst {
      case .delete(let r): deletes.append(r)
      case .insert(let loc, let s): inserts.append((loc, s))
      case .setAttributes(let r, let attrs): sets.append((r, attrs))
      case .fixAttributes: ()
      case .decoratorAdd, .decoratorRemove, .decoratorDecorate, .applyBlockAttributes:
        ()
      }
    }

    func coalesceDeletes(_ ranges: [NSRange]) -> [NSRange] {
      if ranges.isEmpty { return [] }
      // Merge overlapping/adjacent and sort descending by location for safe deletion
      let sorted = ranges.sorted { lhs, rhs in
        lhs.location < rhs.location
      }
      var merged: [NSRange] = []
      var current = sorted[0]
      for r in sorted.dropFirst() {
        if NSMaxRange(current) >= r.location { // overlap or adjacent
          let end = max(NSMaxRange(current), NSMaxRange(r))
          current = NSRange(location: current.location, length: end - current.location)
        } else {
          merged.append(current)
          current = r
        }
      }
      merged.append(current)
      return merged.sorted { $0.location > $1.location }
    }

    func coalesceInserts(_ ops: [(Int, NSAttributedString)]) -> [(Int, NSAttributedString)] {
      if ops.isEmpty { return [] }
      // Combine consecutive inserts at the same location in ascending order
      let sorted = ops.sorted { $0.0 < $1.0 }
      var out: [(Int, NSMutableAttributedString)] = []
      for (loc, s) in sorted {
        if let last = out.last, last.0 == loc {
          out[out.count - 1].1.append(s)
        } else {
          out.append((loc, NSMutableAttributedString(attributedString: s)))
        }
      }
      return out.map { ($0.0, NSAttributedString(attributedString: $0.1)) }
    }

    let deletesCoalesced = coalesceDeletes(deletes)
    let insertsCoalesced = coalesceInserts(inserts)

    let previousMode = textStorage.mode
    textStorage.mode = .controllerMode
    textStorage.beginEditing()

    var modifiedRanges: [NSRange] = []
    for r in deletesCoalesced where r.length > 0 {
      textStorage.deleteCharacters(in: r)
      modifiedRanges.append(r)
    }
    for (loc, s) in insertsCoalesced where s.length > 0 {
      textStorage.insert(s, at: loc)
      modifiedRanges.append(NSRange(location: loc, length: s.length))
    }
    for (r, attrs) in sets {
      textStorage.setAttributes(attrs, range: r)
      modifiedRanges.append(r)
    }

    // Fix attributes over the minimal covering range
    if let cover = modifiedRanges.reduce(nil as NSRange?) { acc, r in
      guard let a = acc else { return r }
      let start = min(a.location, r.location)
      let end = max(NSMaxRange(a), NSMaxRange(r))
      return NSRange(location: start, length: end - start)
    } {
      textStorage.fixAttributes(in: cover)
    }

    textStorage.endEditing()
    textStorage.mode = previousMode
  }

  @MainActor
  internal static func updateEditorState(
    currentEditorState: EditorState,
    pendingEditorState: EditorState,
    editor: Editor,
    shouldReconcileSelection: Bool,
    markedTextOperation: MarkedTextOperation?
  ) throws {
    guard let textStorage = editor.textStorage else {
      fatalError("Cannot run optimized reconciler on an editor with no text storage")
    }

    // Composition (marked text) fast path first
    if let mto = markedTextOperation {
      if try fastPath_Composition(
        currentEditorState: currentEditorState,
        pendingEditorState: pendingEditorState,
        editor: editor,
        shouldReconcileSelection: shouldReconcileSelection,
        op: mto
      ) { return }
    }

    // Try optimized fast paths before falling back (even if fullReconcile)
    if try fastPath_ReorderChildren(
      currentEditorState: currentEditorState,
      pendingEditorState: pendingEditorState,
      editor: editor,
      shouldReconcileSelection: shouldReconcileSelection
    ) {
      return
    }

    // Text-only and attribute-only fast paths
    if try fastPath_TextOnly(
      currentEditorState: currentEditorState,
      pendingEditorState: pendingEditorState,
      editor: editor,
      shouldReconcileSelection: shouldReconcileSelection
    ) {
      return
    }

    if try fastPath_PreamblePostambleOnly(
      currentEditorState: currentEditorState,
      pendingEditorState: pendingEditorState,
      editor: editor,
      shouldReconcileSelection: shouldReconcileSelection
    ) {
      return
    }

    // Coalesced contiguous multi-node replace (e.g., paste across multiple nodes)
    if try fastPath_ContiguousMultiNodeReplace(
      currentEditorState: currentEditorState,
      pendingEditorState: pendingEditorState,
      editor: editor,
      shouldReconcileSelection: shouldReconcileSelection
    ) {
      return
    }

    // Fallback to legacy until additional optimized planners are implemented
    // If still here, fallback
    if editor.featureFlags.useOptimizedReconcilerStrictMode {
      try optimizedSlowPath(
        currentEditorState: currentEditorState,
        pendingEditorState: pendingEditorState,
        editor: editor,
        shouldReconcileSelection: shouldReconcileSelection
      )
    } else {
      try delegateToLegacy(
        currentEditorState: currentEditorState,
        pendingEditorState: pendingEditorState,
        editor: editor,
        shouldReconcileSelection: shouldReconcileSelection,
        markedTextOperation: markedTextOperation
      )
    }
  }

  // MARK: - Legacy delegate
  @MainActor
  private static func delegateToLegacy(
    currentEditorState: EditorState,
    pendingEditorState: EditorState,
    editor: Editor,
    shouldReconcileSelection: Bool,
    markedTextOperation: MarkedTextOperation?
  ) throws {
    print("🔥 OPTIMIZED RECONCILER: delegating to legacy path")
    try Reconciler.updateEditorState(
      currentEditorState: currentEditorState,
      pendingEditorState: pendingEditorState,
      editor: editor,
      shouldReconcileSelection: shouldReconcileSelection,
      markedTextOperation: markedTextOperation
    )
  }

  // MARK: - Optimized slow path fallback (no legacy)
  @MainActor
  private static func optimizedSlowPath(
    currentEditorState: EditorState,
    pendingEditorState: EditorState,
    editor: Editor,
    shouldReconcileSelection: Bool
  ) throws {
    guard let textStorage = editor.textStorage else { return }
    let theme = editor.getTheme()
    let previousMode = textStorage.mode
    textStorage.mode = .controllerMode
    textStorage.beginEditing()
    // Rebuild full string from pending state (root children)
    let built = NSMutableAttributedString()
    if let root = pendingEditorState.getRootNode() as? ElementNode {
      for child in root.getChildrenKeys() {
        built.append(buildAttributedSubtree(nodeKey: child, state: pendingEditorState, theme: theme))
      }
    }
    let fullRange = NSRange(location: 0, length: textStorage.string.lengthAsNSString())
    textStorage.replaceCharacters(in: fullRange, with: built)
    textStorage.fixAttributes(in: NSRange(location: 0, length: built.length))
    textStorage.endEditing()
    // Apply block-level attributes for all nodes (parity with legacy slow path)
    applyBlockAttributesPass(editor: editor, pendingEditorState: pendingEditorState, affectedKeys: nil, treatAllNodesAsDirty: true)
    textStorage.mode = previousMode

    // Recompute entire range cache locations
    _ = recomputeRangeCacheSubtree(nodeKey: kRootNodeKey, state: pendingEditorState, startLocation: 0, editor: editor)

    // Update decorators positions
    if let ts = editor.textStorage {
      for (key, _) in ts.decoratorPositionCache {
        if let loc = editor.rangeCache[key]?.location { ts.decoratorPositionCache[key] = loc }
      }
    }

    // Selection reconcile
    let prevSelection = currentEditorState.selection
    let nextSelection = pendingEditorState.selection
    var selectionsAreDifferent = false
    if let nextSelection, let prevSelection { selectionsAreDifferent = !nextSelection.isSelection(prevSelection) }
    let needsUpdate = editor.dirtyType != .noDirtyNodes
    if shouldReconcileSelection && (needsUpdate || nextSelection == nil || selectionsAreDifferent) {
      try reconcileSelection(prevSelection: prevSelection, nextSelection: nextSelection, editor: editor)
    }

    print("🔥 OPTIMIZED RECONCILER: optimized slow path applied (full rebuild)")
  }

  // MARK: - Fast path: single TextNode content change
  @MainActor
  private static func fastPath_TextOnly(
    currentEditorState: EditorState,
    pendingEditorState: EditorState,
    editor: Editor,
    shouldReconcileSelection: Bool
  ) throws -> Bool {
    // Find a single TextNode whose text part changed (length may or may not change).
    // We allow other dirty nodes (e.g., parents marked dirty), but only operate when
    // exactly one TextNode's text is modified.
    let textDirtyKeys = editor.dirtyNodes.keys.filter { key in
      (currentEditorState.nodeMap[key] is TextNode) || (pendingEditorState.nodeMap[key] is TextNode)
    }
    guard textDirtyKeys.count == 1, let dirtyKey = textDirtyKeys.first,
          let prevNode = currentEditorState.nodeMap[dirtyKey] as? TextNode,
          let nextNode = pendingEditorState.nodeMap[dirtyKey] as? TextNode,
          let prevRange = editor.rangeCache[dirtyKey]
    else { return false }

    // Parent identity should remain stable for the fast path
    if prevNode.parent != nextNode.parent { return false }

    let newText = nextNode.getTextPart()
    let oldTextLen = prevRange.textLength
    let newTextLen = newText.lengthAsNSString()
    if oldTextLen == newTextLen {
      // Attribute-only fast path if underlying string content is identical
      guard let textStorage = editor.textStorage else { return false }
      let textRange = NSRange(
        location: prevRange.location + prevRange.preambleLength + prevRange.childrenLength,
        length: oldTextLen)
      if textRange.upperBound <= textStorage.length {
        let currentText = textStorage.attributedSubstring(from: textRange).string
        if currentText == newText {
          let attributes = AttributeUtils.attributedStringStyles(
            from: nextNode, state: pendingEditorState, theme: editor.getTheme())
          let previousMode = textStorage.mode
          textStorage.mode = .controllerMode
          textStorage.beginEditing()
          textStorage.setAttributes(attributes, range: textRange)
          textStorage.fixAttributes(in: textRange)
          textStorage.endEditing()
          textStorage.mode = previousMode

          // No length delta, but re-apply decorator positions for safety
          for (key, _) in textStorage.decoratorPositionCache {
            if let loc = editor.rangeCache[key]?.location {
              textStorage.decoratorPositionCache[key] = loc
            }
          }

          let prevSelection = currentEditorState.selection
          let nextSelection = pendingEditorState.selection
          var selectionsAreDifferent = false
          if let nextSelection, let prevSelection {
            selectionsAreDifferent = !nextSelection.isSelection(prevSelection)
          }
          let needsUpdate = editor.dirtyType != .noDirtyNodes
          if shouldReconcileSelection
            && (needsUpdate || nextSelection == nil || selectionsAreDifferent)
          {
            try reconcileSelection(
              prevSelection: prevSelection, nextSelection: nextSelection, editor: editor)
          }

          print("🔥 OPTIMIZED RECONCILER: attribute-only fast path applied")
          return true
        }
      }
      // Content changed but length kept → try pre/post part deltas for element siblings, else fallback
      return false
    }

    // Prepare DFS order and Fenwick tree for potential multi-node location shifts
    let keysInOrder = sortedNodeKeysByLocation(rangeCache: editor.rangeCache)
    var indexOf: [NodeKey: Int] = [:]
    indexOf.reserveCapacity(keysInOrder.count)
    for (i, k) in keysInOrder.enumerated() { indexOf[k] = i + 1 }
    var bit = FenwickTree(keysInOrder.count)

    // Plan minimal instructions: delete old text range, insert new attributed text
    let textStart = prevRange.location + prevRange.preambleLength + prevRange.childrenLength
    let deleteRange = NSRange(location: textStart, length: oldTextLen)

    // Build attributed string with correct styles for the new text
    let attrString = AttributeUtils.attributedStringByAddingStyles(
      NSAttributedString(string: newText), from: nextNode, state: pendingEditorState,
      theme: editor.getTheme())

    var instructions: [Instruction] = []
    if deleteRange.length > 0 {
      instructions.append(.delete(range: deleteRange))
    }
    if attrString.length > 0 {
      instructions.append(.insert(location: textStart, attrString: attrString))
    }

    applyInstructions(instructions, editor: editor)

    // Update RangeCache using Fenwick when enabled, otherwise fallback helper
    let delta = newTextLen - oldTextLen
    if editor.featureFlags.useReconcilerFenwickDelta {
      // Update lengths in cache without walking tree
      if var item = editor.rangeCache[dirtyKey] { item.textLength = newTextLen; editor.rangeCache[dirtyKey] = item }
      // Update ancestors' childrenLength
      if let node = pendingEditorState.nodeMap[dirtyKey] as? TextNode {
        let parentKeys = node.getParents().map { $0.getKey() }
        for pk in parentKeys { if var it = editor.rangeCache[pk] { it.childrenLength += delta; editor.rangeCache[pk] = it } }
      }
      editor.rangeCache = rebuildLocationsWithFenwick(prev: editor.rangeCache, deltas: [dirtyKey: delta])
    } else {
      updateRangeCacheForTextChange(nodeKey: dirtyKey, delta: delta)
    }

    // Update decorator positions to match new locations
    if let ts = editor.textStorage {
      for (key, _) in ts.decoratorPositionCache {
        if let loc = editor.rangeCache[key]?.location {
          ts.decoratorPositionCache[key] = loc
        }
      }
    }

    // Block-level attributes: apply for this node and its ancestors only (optimized scope)
    var affected: Set<NodeKey> = [dirtyKey]
    if let node = pendingEditorState.nodeMap[dirtyKey] { for p in node.getParents() { affected.insert(p.getKey()) } }
    applyBlockAttributesPass(editor: editor, pendingEditorState: pendingEditorState, affectedKeys: affected, treatAllNodesAsDirty: false)

    // Reconcile selection similarly to legacy when requested
    let prevSelection = currentEditorState.selection
    let nextSelection = pendingEditorState.selection
    var selectionsAreDifferent = false
    if let nextSelection, let prevSelection { selectionsAreDifferent = !nextSelection.isSelection(prevSelection) }
    let needsUpdate = editor.dirtyType != .noDirtyNodes
    if shouldReconcileSelection && (needsUpdate || nextSelection == nil || selectionsAreDifferent) {
      try reconcileSelection(prevSelection: prevSelection, nextSelection: nextSelection, editor: editor)
    }

    print("🔥 OPTIMIZED RECONCILER: text-only fast path applied (delta=\(delta))")
    return true
  }

  // MARK: - Fast path: reorder children of a single ElementNode (same keys, new order)
  @MainActor
  private static func fastPath_ReorderChildren(
    currentEditorState: EditorState,
    pendingEditorState: EditorState,
    editor: Editor,
    shouldReconcileSelection: Bool
  ) throws -> Bool {
    // Identify all parents whose children order changed but set of keys is identical
    // We allow multiple dirty nodes; we only check the structural condition.
    var candidates: [NodeKey] = pendingEditorState.nodeMap.compactMap { key, node in
      guard let prev = currentEditorState.nodeMap[key] as? ElementNode,
            let next = node as? ElementNode else { return nil }
      let prevChildren = prev.getChildrenKeys(fromLatest: false)
      let nextChildren = next.getChildrenKeys(fromLatest: false)
      if prevChildren == nextChildren { return nil }
      if Set(prevChildren) != Set(nextChildren) { return nil }
      return key
    }
    // Process candidates in document order for stability
    candidates.sort { a, b in
      let la = editor.rangeCache[a]?.location ?? 0
      let lb = editor.rangeCache[b]?.location ?? 0
      return la < lb
    }

    var appliedAny = false
    for parentKey in candidates {
      guard
          let parentPrev = currentEditorState.nodeMap[parentKey] as? ElementNode,
          let parentNext = pendingEditorState.nodeMap[parentKey] as? ElementNode,
          let parentPrevRange = editor.rangeCache[parentKey]
      else { continue }

    let nextChildren = parentNext.getChildrenKeys(fromLatest: false)

    // Compute LIS (stable children); if almost all children are stable, moves are few
    let prevChildren = parentPrev.getChildrenKeys(fromLatest: false)
    let stableSet = computeStableChildKeys(prev: prevChildren, next: nextChildren)
    print("🔥 OPTIMIZED RECONCILER: reorder candidates parent=\(parentKey) total=\(nextChildren.count) stable=\(stableSet.count)")

    // Build attributed string for children in new order and compute subtree lengths
    let theme = editor.getTheme()
    let built = NSMutableAttributedString()
    for childKey in nextChildren {
      built.append(buildAttributedSubtree(nodeKey: childKey, state: pendingEditorState, theme: theme))
    }

    // Children region range in existing storage
    let childrenStart = parentPrevRange.location + parentPrevRange.preambleLength
    let childrenRange = NSRange(location: childrenStart, length: parentPrevRange.childrenLength)
    if childrenRange.length != built.length {
      // Not a pure reorder; bail and let legacy handle complex changes
      return false
    }

    // Decide whether to do minimal moves or full region rebuild
    let movedCount = nextChildren.filter { !stableSet.contains($0) }.count
    let lisLen = stableSet.count
    let preferMinimalMoves = lisLen >= max(2, nextChildren.count / 5) // if at least 20% stable, do minimal moves
    if movedCount == 0 {
      // Nothing to do beyond cache recompute
      _ = recomputeRangeCacheSubtree(
        nodeKey: parentKey, state: pendingEditorState, startLocation: parentPrevRange.location,
        editor: editor)
    } else if preferMinimalMoves {
      // Minimal move plan: delete moved child ranges, then insert them at target positions in next order
      var instructions: [Instruction] = []
      // Delete moved children in descending location order
      let movedKeys = prevChildren.filter { !stableSet.contains($0) }
      let movedDeleteRanges: [NSRange] = movedKeys.compactMap { k in editor.rangeCache[k]?.range }
      for r in movedDeleteRanges.sorted(by: { $0.location > $1.location }) {
        instructions.append(.delete(range: r))
      }

      // Compute pending lengths for all children
      var nextLen: [NodeKey: Int] = [:]
      for k in nextChildren {
        nextLen[k] = subtreeTotalLength(nodeKey: k, state: pendingEditorState)
      }
      // Insert moved children at target positions based on next order
      var acc = 0
      for k in nextChildren {
        if stableSet.contains(k) {
          acc += nextLen[k] ?? 0
        } else {
          let insertLoc = childrenStart + acc
          let attr = buildAttributedSubtree(nodeKey: k, state: pendingEditorState, theme: theme)
          instructions.append(.insert(location: insertLoc, attrString: attr))
          acc += attr.length
        }
      }

      applyInstructions(instructions, editor: editor)
    } else {
      // Region rebuild fallback when many moves
      guard let textStorage = editor.textStorage else { return false }
      let previousMode = textStorage.mode
      textStorage.mode = .controllerMode
      textStorage.beginEditing()
      textStorage.replaceCharacters(in: childrenRange, with: built)
      textStorage.fixAttributes(in: NSRange(location: childrenRange.location, length: built.length))
      textStorage.endEditing()
      textStorage.mode = previousMode
    }

    // Rebuild locations for the reordered subtree without recomputing lengths.
    // Compute child-level new starts using next order and shift entire subtrees accordingly.
    // This keeps decorator-bearing subtrees intact while avoiding a full subtree recompute.
    let prevChildrenOrder = prevChildren
    let nextChildrenOrder = nextChildren

    // Entire-range length for each direct child (unchanged by reorder)
    var childLength: [NodeKey: Int] = [:]
    var childOldStart: [NodeKey: Int] = [:]
    for k in prevChildrenOrder {
      if let item = editor.rangeCache[k] {
        childLength[k] = item.range.length
        childOldStart[k] = item.location
      } else {
        // Fallback to computing from state if cache missing (should be rare)
        let len = subtreeTotalLength(nodeKey: k, state: currentEditorState)
        childLength[k] = len
        childOldStart[k] = parentPrevRange.location + parentPrevRange.preambleLength // safe base
      }
    }

    // Compute new starts based on next order
    var childNewStart: [NodeKey: Int] = [:]
    var accLen = 0
    for k in nextChildrenOrder {
      childNewStart[k] = childrenStart + accLen
      accLen += childLength[k] ?? 0
    }

    // Shift locations for each direct child subtree by delta, including all descendants (decorators included)
    for k in nextChildrenOrder {
      guard let oldStart = childOldStart[k], let newStart = childNewStart[k] else { continue }
      let deltaShift = newStart - oldStart
      if deltaShift == 0 { continue }

      // Walk the subtree in pending state (reflects new structure) and add delta to each cached location
      for subKey in subtreeKeysDFS(rootKey: k, state: pendingEditorState) {
        if var item = editor.rangeCache[subKey] {
          item.location += deltaShift
          editor.rangeCache[subKey] = item
        }
      }

      // Update decorator positions for any decorator nodes inside this subtree
      if let ts = editor.textStorage {
        for (dKey, loc) in ts.decoratorPositionCache {
          if editor.rangeCache[dKey] != nil, subtreeContains(rootKey: k, candidateKey: dKey, state: pendingEditorState) {
            ts.decoratorPositionCache[dKey] = (editor.rangeCache[dKey]?.location) ?? (loc + deltaShift)
          }
        }
      }
    }

    // Update decorator positions for keys within this subtree
    if let ts = editor.textStorage {
      for (key, _) in ts.decoratorPositionCache {
        if let loc = editor.rangeCache[key]?.location {
          ts.decoratorPositionCache[key] = loc
        }
      }
    }

    // Apply block-level attributes for parent and direct children (reorder may affect paragraph boundaries)
    var affected: Set<NodeKey> = [parentKey]
    for k in nextChildren { affected.insert(k) }
    applyBlockAttributesPass(editor: editor, pendingEditorState: pendingEditorState, affectedKeys: affected, treatAllNodesAsDirty: false)

    // Selection handling
    let prevSelection = currentEditorState.selection
    let nextSelection = pendingEditorState.selection
    var selectionsAreDifferent = false
    if let nextSelection, let prevSelection { selectionsAreDifferent = !nextSelection.isSelection(prevSelection) }
    let needsUpdate = editor.dirtyType != .noDirtyNodes
    if shouldReconcileSelection && (needsUpdate || nextSelection == nil || selectionsAreDifferent) {
      try reconcileSelection(prevSelection: prevSelection, nextSelection: nextSelection, editor: editor)
    }

      print("🔥 OPTIMIZED RECONCILER: children reorder fast path applied (parent=\(parentKey), moved=\(movedCount), total=\(nextChildren.count))")
      appliedAny = true
    }
    return appliedAny
  }

  // Build full attributed subtree for a node in pending state (preamble + children + text + postamble)
  @MainActor
  private static func buildAttributedSubtree(
    nodeKey: NodeKey, state: EditorState, theme: Theme
  ) -> NSAttributedString {
    guard let node = state.nodeMap[nodeKey] else { return NSAttributedString() }
    let output = NSMutableAttributedString()
    let pre = AttributeUtils.attributedStringByAddingStyles(
      NSAttributedString(string: node.getPreamble()), from: node, state: state, theme: theme)
    output.append(pre)

    if let element = node as? ElementNode {
      for child in element.getChildrenKeys() {
        output.append(buildAttributedSubtree(nodeKey: child, state: state, theme: theme))
      }
    }

    let text = AttributeUtils.attributedStringByAddingStyles(
      NSAttributedString(string: node.getTextPart()), from: node, state: state, theme: theme)
    output.append(text)

    let post = AttributeUtils.attributedStringByAddingStyles(
      NSAttributedString(string: node.getPostamble()), from: node, state: state, theme: theme)
    output.append(post)
    return output
  }

  // Recompute range cache (location + part lengths) for a subtree using the pending state.
  // Returns total length (entireRange) written for this node.
  @MainActor
  @discardableResult
  private static func recomputeRangeCacheSubtree(
    nodeKey: NodeKey, state: EditorState, startLocation: Int, editor: Editor
  ) -> Int {
    guard let node = state.nodeMap[nodeKey] else { return 0 }
    var item = editor.rangeCache[nodeKey] ?? RangeCacheItem()
    item.location = startLocation
    let preLen = node.getPreamble().lengthAsNSString()
    let preSpecial = node.getPreamble().lengthAsNSString(includingCharacters: ["\u{200B}"])
    item.preambleLength = preLen
    item.preambleSpecialCharacterLength = preSpecial
    var cursor = startLocation + preLen
    var childrenLen = 0
    if let element = node as? ElementNode {
      for childKey in element.getChildrenKeys() {
        let childLen = recomputeRangeCacheSubtree(
          nodeKey: childKey, state: state, startLocation: cursor, editor: editor)
        cursor += childLen
        childrenLen += childLen
      }
    }
    item.childrenLength = childrenLen
    let textLen = node.getTextPart().lengthAsNSString()
    item.textLength = textLen
    cursor += textLen
    let postLen = node.getPostamble().lengthAsNSString()
    item.postambleLength = postLen
    editor.rangeCache[nodeKey] = item
    return preLen + childrenLen + textLen + postLen
  }

  // Minimal selection reconciler mirroring legacy logic
  @MainActor
  private static func reconcileSelection(
    prevSelection: BaseSelection?,
    nextSelection: BaseSelection?,
    editor: Editor
  ) throws {
    guard let nextSelection else {
      if let prevSelection, !prevSelection.dirty {
        return
      }
      editor.frontend?.resetSelectedRange()
      return
    }
    try editor.frontend?.updateNativeSelection(from: nextSelection)
  }

  // MARK: - Fast path: preamble/postamble change only for a single node (children & text unchanged)
  @MainActor
  private static func fastPath_PreamblePostambleOnly(
    currentEditorState: EditorState,
    pendingEditorState: EditorState,
    editor: Editor,
    shouldReconcileSelection: Bool
  ) throws -> Bool {
    guard editor.dirtyNodes.count == 1, let dirtyKey = editor.dirtyNodes.keys.first else {
      return false
    }
    guard let prevNode = currentEditorState.nodeMap[dirtyKey],
          let nextNode = pendingEditorState.nodeMap[dirtyKey],
          let prevRange = editor.rangeCache[dirtyKey] else { return false }

    // Ensure children/text lengths unchanged
    let nextTextLen = nextNode.getTextPart().lengthAsNSString()
    if nextTextLen != prevRange.textLength { return false }
    // We approximate children unchanged by comparing aggregated length via pending state subtree build
    var computedChildrenLen = 0
    if let element = nextNode as? ElementNode {
      for child in element.getChildrenKeys() {
        computedChildrenLen += subtreeTotalLength(nodeKey: child, state: pendingEditorState)
      }
    }
    if computedChildrenLen != prevRange.childrenLength { return false }

    let nextPreLen = nextNode.getPreamble().lengthAsNSString()
    let nextPostLen = nextNode.getPostamble().lengthAsNSString()
    let preChanged = nextPreLen != prevRange.preambleLength
    let postChanged = nextPostLen != prevRange.postambleLength
    if !preChanged && !postChanged { return false }

    let theme = editor.getTheme()
    var applied: [Instruction] = []

    // Apply postamble first (higher location)
    if postChanged {
      let postLoc = prevRange.location + prevRange.preambleLength + prevRange.childrenLength + prevRange.textLength
      let oldR = NSRange(location: postLoc, length: prevRange.postambleLength)
      applied.append(.delete(range: oldR))
      let postAttr = AttributeUtils.attributedStringByAddingStyles(
        NSAttributedString(string: nextNode.getPostamble()), from: nextNode, state: pendingEditorState,
        theme: theme)
      if postAttr.length > 0 { applied.append(.insert(location: postLoc, attrString: postAttr)) }
      let delta = nextPostLen - prevRange.postambleLength
      if editor.featureFlags.useReconcilerFenwickDelta {
        if var item = editor.rangeCache[dirtyKey] { item.postambleLength = nextPostLen; editor.rangeCache[dirtyKey] = item }
        if let node = pendingEditorState.nodeMap[dirtyKey] { let parents = node.getParents().map { $0.getKey() }; for pk in parents { if var it = editor.rangeCache[pk] { it.childrenLength += delta; editor.rangeCache[pk] = it } } }
        editor.rangeCache = rebuildLocationsWithFenwick(prev: editor.rangeCache, deltas: [dirtyKey: delta])
      } else {
        updateRangeCacheForNodePartChange(nodeKey: dirtyKey, part: .postamble, newPartLength: nextPostLen, delta: delta)
      }
    }

    // Apply preamble second (lower location)
    if preChanged {
      let preLoc = prevRange.location
      let oldR = NSRange(location: preLoc, length: prevRange.preambleLength)
      applied.append(.delete(range: oldR))
      let preAttr = AttributeUtils.attributedStringByAddingStyles(
        NSAttributedString(string: nextNode.getPreamble()), from: nextNode, state: pendingEditorState,
        theme: theme)
      if preAttr.length > 0 { applied.append(.insert(location: preLoc, attrString: preAttr)) }
      let delta = nextPreLen - prevRange.preambleLength
      let preSpecial = nextNode.getPreamble().lengthAsNSString(includingCharacters: ["\u{200B}"])
      if editor.featureFlags.useReconcilerFenwickDelta {
        if var item = editor.rangeCache[dirtyKey] { item.preambleLength = nextPreLen; item.preambleSpecialCharacterLength = preSpecial; editor.rangeCache[dirtyKey] = item }
        if let node = pendingEditorState.nodeMap[dirtyKey] { let parents = node.getParents().map { $0.getKey() }; for pk in parents { if var it = editor.rangeCache[pk] { it.childrenLength += delta; editor.rangeCache[pk] = it } } }
        editor.rangeCache = rebuildLocationsWithFenwick(prev: editor.rangeCache, deltas: [dirtyKey: delta])
      } else {
        updateRangeCacheForNodePartChange(nodeKey: dirtyKey, part: .preamble, newPartLength: nextPreLen, preambleSpecialCharacterLength: preSpecial, delta: delta)
      }
    }
    applyInstructions(applied, editor: editor)

    // Update decorators positions
    if let ts = editor.textStorage {
      for (key, _) in ts.decoratorPositionCache {
        if let loc = editor.rangeCache[key]?.location {
          ts.decoratorPositionCache[key] = loc
        }
      }
    }

    // Block-level attributes: apply for this node and its ancestors only (optimized scope)
    var affected: Set<NodeKey> = [dirtyKey]
    if let node = pendingEditorState.nodeMap[dirtyKey] { for p in node.getParents() { affected.insert(p.getKey()) } }
    applyBlockAttributesPass(editor: editor, pendingEditorState: pendingEditorState, affectedKeys: affected, treatAllNodesAsDirty: false)

    // Selection handling
    let prevSelection = currentEditorState.selection
    let nextSelection = pendingEditorState.selection
    var selectionsAreDifferent = false
    if let nextSelection, let prevSelection { selectionsAreDifferent = !nextSelection.isSelection(prevSelection) }
    let needsUpdate = editor.dirtyType != .noDirtyNodes
    if shouldReconcileSelection && (needsUpdate || nextSelection == nil || selectionsAreDifferent) {
      try reconcileSelection(prevSelection: prevSelection, nextSelection: nextSelection, editor: editor)
    }

    print("🔥 OPTIMIZED RECONCILER: pre/post fast path applied (key=\(dirtyKey))")
    return true
  }

  // MARK: - Fast path: composition (marked text) start/update
  @MainActor
  private static func fastPath_Composition(
    currentEditorState: EditorState,
    pendingEditorState: EditorState,
    editor: Editor,
    shouldReconcileSelection: Bool,
    op: MarkedTextOperation
  ) throws -> Bool {
    guard let textStorage = editor.textStorage else { return false }
    // Only special-handle start of composition. Updates/end are handled by Events via insert/replace
    guard op.createMarkedText else { return false }

    // Locate Point at replacement start if possible
    let startLocation = op.selectionRangeToReplace.location
    let point = try? pointAtStringLocation(startLocation, searchDirection: .forward, rangeCache: editor.rangeCache)

    // Prepare attributed marked text with styles from owning node if available
    var attrs: [NSAttributedString.Key: Any] = [:]
    if let p = point, let node = pendingEditorState.nodeMap[p.key] {
      attrs = AttributeUtils.attributedStringStyles(from: node, state: pendingEditorState, theme: editor.getTheme())
    }
    let markedAttr = NSAttributedString(string: op.markedTextString, attributes: attrs)

    // Replace characters in storage at requested range
    let delta = markedAttr.length - op.selectionRangeToReplace.length
    let previousMode = textStorage.mode
    textStorage.mode = .controllerMode
    textStorage.beginEditing()
    textStorage.replaceCharacters(in: op.selectionRangeToReplace, with: markedAttr)
    textStorage.fixAttributes(in: NSRange(location: op.selectionRangeToReplace.location, length: markedAttr.length))
    textStorage.endEditing()
    textStorage.mode = previousMode

    // Update range cache if we can resolve to a TextNode
    if let p = point, let textNode = pendingEditorState.nodeMap[p.key] as? TextNode {
      updateRangeCacheForTextChange(nodeKey: textNode.key, delta: delta)
    }

    // Set marked text via frontend API
    if let p = point {
      let startPoint = p
      let endPoint = Point(key: p.key, offset: p.offset + markedAttr.length, type: .text)
      try editor.frontend?.updateNativeSelection(from: RangeSelection(anchor: startPoint, focus: endPoint, format: TextFormat()))
    }
    editor.frontend?.setMarkedTextFromReconciler(markedAttr, selectedRange: op.markedTextInternalSelection)

    // Skip selection reconcile after marked text (legacy behavior)
    print("🔥 OPTIMIZED RECONCILER: composition fast path applied (len=\(markedAttr.length))")
    return true
  }

  // MARK: - Fast path: contiguous multi-node region replace under a common ancestor
  @MainActor
  private static func fastPath_ContiguousMultiNodeReplace(
    currentEditorState: EditorState,
    pendingEditorState: EditorState,
    editor: Editor,
    shouldReconcileSelection: Bool
  ) throws -> Bool {
    // Require 2+ dirty nodes and no marked text handling pending
    guard editor.dirtyNodes.count >= 2 else { return false }

    // Find lowest common ancestor (LCA) element in pending state for all dirty nodes
    let dirtyKeys = Array(editor.dirtyNodes.keys)
    func ancestors(of key: NodeKey) -> [NodeKey] {
      var list: [NodeKey] = []
      var k: NodeKey? = key
      while let cur = k, let node = pendingEditorState.nodeMap[cur] {
        if let p = node.parent { list.append(p); k = p } else { break }
      }
      return list
    }
    var common: Set<NodeKey>? = nil
    for k in dirtyKeys {
      let a = Set(ancestors(of: k))
      common = (common == nil) ? a : common!.intersection(a)
      if common?.isEmpty == true { return false }
    }
    guard let candidateAncestors = common, let ancestorKey = candidateAncestors.first,
          let ancestorPrev = currentEditorState.nodeMap[ancestorKey] as? ElementNode,
          let ancestorNext = pendingEditorState.nodeMap[ancestorKey] as? ElementNode,
          let ancestorPrevRange = editor.rangeCache[ancestorKey]
    else { return false }

    // Ensure no creates/deletes inside ancestor (same key set prev vs next)
    func collectDescendants(state: EditorState, root: NodeKey) -> Set<NodeKey> {
      guard let node = state.nodeMap[root] else { return [] }
      var out: Set<NodeKey> = []
      if let el = node as? ElementNode {
        for c in el.getChildrenKeys(fromLatest: false) {
          out.insert(c)
          out.formUnion(collectDescendants(state: state, root: c))
        }
      }
      return out
    }
    let prevSet = collectDescendants(state: currentEditorState, root: ancestorKey)
    let nextSet = collectDescendants(state: pendingEditorState, root: ancestorKey)
    if prevSet != nextSet { return false }

    // Build attributed content for ancestor's children in next order
    let theme = editor.getTheme()
    let nextChildren = ancestorNext.getChildrenKeys(fromLatest: false)
    let built = NSMutableAttributedString()
    for child in nextChildren { built.append(buildAttributedSubtree(nodeKey: child, state: pendingEditorState, theme: theme)) }

    // Replace the children region for the ancestor
    guard let textStorage = editor.textStorage else { return false }
    let previousMode = textStorage.mode
    let childrenStart = ancestorPrevRange.location + ancestorPrevRange.preambleLength
    let childrenRange = NSRange(location: childrenStart, length: ancestorPrevRange.childrenLength)
    textStorage.mode = .controllerMode
    textStorage.beginEditing()
    textStorage.replaceCharacters(in: childrenRange, with: built)
    textStorage.fixAttributes(in: NSRange(location: childrenRange.location, length: built.length))
    textStorage.endEditing()
    textStorage.mode = previousMode

    // Recompute the range cache for this subtree (locations and lengths)
    _ = recomputeRangeCacheSubtree(
      nodeKey: ancestorKey, state: pendingEditorState, startLocation: ancestorPrevRange.location,
      editor: editor)

    // Update decorator positions for this subtree
    if let ts = editor.textStorage {
      for (key, _) in ts.decoratorPositionCache {
        if let loc = editor.rangeCache[key]?.location { ts.decoratorPositionCache[key] = loc }
      }
    }

    // Block-level attributes for ancestor + its parents
    var affected: Set<NodeKey> = [ancestorKey]
    if let ancNode = pendingEditorState.nodeMap[ancestorKey] { for p in ancNode.getParents() { affected.insert(p.getKey()) } }
    applyBlockAttributesPass(editor: editor, pendingEditorState: pendingEditorState, affectedKeys: affected, treatAllNodesAsDirty: false)

    // Selection reconcile
    let prevSelection = currentEditorState.selection
    let nextSelection = pendingEditorState.selection
    var selectionsAreDifferent = false
    if let nextSelection, let prevSelection { selectionsAreDifferent = !nextSelection.isSelection(prevSelection) }
    let needsUpdate = editor.dirtyType != .noDirtyNodes
    if shouldReconcileSelection && (needsUpdate || nextSelection == nil || selectionsAreDifferent) {
      try reconcileSelection(prevSelection: prevSelection, nextSelection: nextSelection, editor: editor)
    }

    print("🔥 OPTIMIZED RECONCILER: coalesced contiguous region replace (ancestor=\(ancestorKey), dirty=\(editor.dirtyNodes.count))")
    return true
  }

  // Compute total entireRange length for a node subtree in the provided state.
  @MainActor
  private static func subtreeTotalLength(nodeKey: NodeKey, state: EditorState) -> Int {
    guard let node = state.nodeMap[nodeKey] else { return 0 }
    var sum = node.getPreamble().lengthAsNSString()
    if let el = node as? ElementNode {
      for c in el.getChildrenKeys() { sum += subtreeTotalLength(nodeKey: c, state: state) }
    }
    sum += node.getTextPart().lengthAsNSString()
    sum += node.getPostamble().lengthAsNSString()
    return sum
  }

  // MARK: - Block-level attributes pass (parity with legacy)
  @MainActor
  private static func applyBlockAttributesPass(
    editor: Editor,
    pendingEditorState: EditorState,
    affectedKeys: Set<NodeKey>?,
    treatAllNodesAsDirty: Bool
  ) {
    guard let textStorage = editor.textStorage else { return }
    let theme = editor.getTheme()

    // Build node set to apply
    var nodesToApply: Set<NodeKey> = []
    if treatAllNodesAsDirty {
      nodesToApply = Set(pendingEditorState.nodeMap.keys)
    } else {
      nodesToApply = Set(editor.dirtyNodes.keys)
      // include parents of each dirty node
      for k in editor.dirtyNodes.keys {
        if let n = pendingEditorState.nodeMap[k] { for p in n.getParents() { nodesToApply.insert(p.getKey()) } }
      }
      if let affectedKeys { nodesToApply.formUnion(affectedKeys) }
    }

    let lastDescendentAttributes = getRoot()?.getLastChild()?.getAttributedStringAttributes(theme: theme) ?? [:]

    let previousMode = textStorage.mode
    textStorage.mode = .controllerMode
    textStorage.beginEditing()
    let rangeCache = editor.rangeCache
    for nodeKey in nodesToApply {
      guard let node = getNodeByKey(key: nodeKey), node.isAttached(), let cacheItem = rangeCache[nodeKey], let attributes = node.getBlockLevelAttributes(theme: theme) else { continue }
      AttributeUtils.applyBlockLevelAttributes(
        attributes, cacheItem: cacheItem, textStorage: textStorage, nodeKey: nodeKey,
        lastDescendentAttributes: lastDescendentAttributes)
    }
    textStorage.endEditing()
    textStorage.mode = previousMode
  }

  // Collect all node keys in a subtree (DFS order), including the root key.
  @MainActor
  private static func subtreeKeysDFS(rootKey: NodeKey, state: EditorState) -> [NodeKey] {
    guard let node = state.nodeMap[rootKey] else { return [] }
    var out: [NodeKey] = [rootKey]
    if let el = node as? ElementNode {
      for c in el.getChildrenKeys(fromLatest: false) {
        out.append(contentsOf: subtreeKeysDFS(rootKey: c, state: state))
      }
    }
    return out
  }

  // Checks whether candidateKey is inside the subtree rooted at rootKey in the provided state.
  @MainActor
  private static func subtreeContains(rootKey: NodeKey, candidateKey: NodeKey, state: EditorState) -> Bool {
    if rootKey == candidateKey { return true }
    guard let node = state.nodeMap[rootKey] as? ElementNode else { return false }
    for c in node.getChildrenKeys(fromLatest: false) {
      if subtreeContains(rootKey: c, candidateKey: candidateKey, state: state) { return true }
    }
    return false
  }
}
