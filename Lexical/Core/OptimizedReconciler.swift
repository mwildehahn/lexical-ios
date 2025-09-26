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
  struct InstructionApplyStats { let deletes: Int; let inserts: Int; let sets: Int; let fixes: Int; let duration: TimeInterval }
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
  private static func applyInstructions(_ instructions: [Instruction], editor: Editor, fixAttributesEnabled: Bool = true) -> InstructionApplyStats {
    guard let textStorage = editor.textStorage else { return InstructionApplyStats(deletes: 0, inserts: 0, sets: 0, fixes: 0, duration: 0) }

    // Gather deletes and inserts
    var deletes: [NSRange] = []
    var inserts: [(Int, NSAttributedString)] = []
    var sets: [(NSRange, [NSAttributedString.Key: Any])] = []

    var fixCount = 0
    for inst in instructions {
      switch inst {
      case .delete(let r): deletes.append(r)
      case .insert(let loc, let s): inserts.append((loc, s))
      case .setAttributes(let r, let attrs): sets.append((r, attrs))
      case .fixAttributes: fixCount += 1
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
    let applyStart = CFAbsoluteTimeGetCurrent()
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

    // Fix attributes over the minimal covering range (optional)
    if fixAttributesEnabled {
      if let cover = modifiedRanges.reduce(nil as NSRange?, { acc, r in
        guard let a = acc else { return r }
        let start = min(a.location, r.location)
        let end = max(NSMaxRange(a), NSMaxRange(r))
        return NSRange(location: start, length: end - start)
      }) {
        textStorage.fixAttributes(in: cover)
      }
    }

    textStorage.endEditing()
    textStorage.mode = previousMode
    let applyDuration = CFAbsoluteTimeGetCurrent() - applyStart
    return InstructionApplyStats(deletes: deletesCoalesced.count, inserts: insertsCoalesced.count, sets: sets.count, fixes: (fixCount > 0 ? 1 : 0), duration: applyDuration)
  }

  @MainActor
  internal static func updateEditorState(
    currentEditorState: EditorState,
    pendingEditorState: EditorState,
    editor: Editor,
    shouldReconcileSelection: Bool,
    markedTextOperation: MarkedTextOperation?
  ) throws {
    guard editor.textStorage != nil else { fatalError("Cannot run optimized reconciler on an editor with no text storage") }

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
    // Optional central aggregation of Fenwick deltas across paths
    var fenwickAggregatedDeltas: [NodeKey: Int] = [:]
    // Pre-compute part diffs (used by some paths and metrics)
    let _ = computePartDiffs(editor: editor, prevState: currentEditorState, nextState: pendingEditorState)
    // Structural insert fast path (before reorder)
    if try fastPath_InsertBlock(
      currentEditorState: currentEditorState,
      pendingEditorState: pendingEditorState,
      editor: editor,
      shouldReconcileSelection: shouldReconcileSelection,
      fenwickAggregatedDeltas: &fenwickAggregatedDeltas
    ) { return }
    // If insert-block consumed and central aggregation collected deltas, apply them once
    if editor.featureFlags.useReconcilerFenwickDelta && editor.featureFlags.useReconcilerFenwickCentralAggregation && !fenwickAggregatedDeltas.isEmpty {
      editor.rangeCache = rebuildLocationsWithFenwick(prev: editor.rangeCache, deltas: fenwickAggregatedDeltas)
      fenwickAggregatedDeltas.removeAll(keepingCapacity: true)
    }

    if try fastPath_ReorderChildren(
      currentEditorState: currentEditorState,
      pendingEditorState: pendingEditorState,
      editor: editor,
      shouldReconcileSelection: shouldReconcileSelection
    ) {
      return
    }

    // Text-only and attribute-only fast paths
    // Central aggregation: handle multiple text/pre/post changes in one pass
    if editor.featureFlags.useReconcilerFenwickDelta && editor.featureFlags.useReconcilerFenwickCentralAggregation {
      var anyApplied = false
      if try fastPath_TextOnly_Multi(
        currentEditorState: currentEditorState,
        pendingEditorState: pendingEditorState,
        editor: editor,
        fenwickAggregatedDeltas: &fenwickAggregatedDeltas
      ) { anyApplied = true }
      if try fastPath_PreamblePostambleOnly_Multi(
        currentEditorState: currentEditorState,
        pendingEditorState: pendingEditorState,
        editor: editor,
        fenwickAggregatedDeltas: &fenwickAggregatedDeltas
      ) { anyApplied = true }
      if anyApplied {
        if !fenwickAggregatedDeltas.isEmpty {
          editor.rangeCache = rebuildLocationsWithFenwick(prev: editor.rangeCache, deltas: fenwickAggregatedDeltas)
        }
        // One-time selection reconcile
        let prevSelection = currentEditorState.selection
        let nextSelection = pendingEditorState.selection
        var selectionsAreDifferent = false
        if let nextSelection, let prevSelection { selectionsAreDifferent = !nextSelection.isSelection(prevSelection) }
        let needsUpdate = editor.dirtyType != .noDirtyNodes
        if shouldReconcileSelection && (needsUpdate || nextSelection == nil || selectionsAreDifferent) {
          try reconcileSelection(prevSelection: prevSelection, nextSelection: nextSelection, editor: editor)
        }
        return
      }
    }

    if try fastPath_TextOnly(
      currentEditorState: currentEditorState,
      pendingEditorState: pendingEditorState,
      editor: editor,
      shouldReconcileSelection: shouldReconcileSelection,
      fenwickAggregatedDeltas: &fenwickAggregatedDeltas
    ) {
      // If central aggregation is enabled, apply aggregated rebuild now
      if editor.featureFlags.useReconcilerFenwickDelta && editor.featureFlags.useReconcilerFenwickCentralAggregation && !fenwickAggregatedDeltas.isEmpty {
        editor.rangeCache = rebuildLocationsWithFenwick(prev: editor.rangeCache, deltas: fenwickAggregatedDeltas)
      }
      return
    }

    if try fastPath_PreamblePostambleOnly(
      currentEditorState: currentEditorState,
      pendingEditorState: pendingEditorState,
      editor: editor,
      shouldReconcileSelection: shouldReconcileSelection,
      fenwickAggregatedDeltas: &fenwickAggregatedDeltas
    ) {
      if editor.featureFlags.useReconcilerFenwickDelta && editor.featureFlags.useReconcilerFenwickCentralAggregation && !fenwickAggregatedDeltas.isEmpty {
        editor.rangeCache = rebuildLocationsWithFenwick(prev: editor.rangeCache, deltas: fenwickAggregatedDeltas)
      }
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
    if editor.featureFlags.useReconcilerShadowCompare { print("🔥 OPTIMIZED RECONCILER: delegating to legacy path") }
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
    if let root = pendingEditorState.getRootNode() {
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

    // Recompute entire range cache locations and prune stale entries
    _ = recomputeRangeCacheSubtree(nodeKey: kRootNodeKey, state: pendingEditorState, startLocation: 0, editor: editor)
    pruneRangeCacheGlobally(nextState: pendingEditorState, editor: editor)

    // Reconcile decorators for the entire document (add/remove/decorate + positions)
    reconcileDecoratorOpsForSubtree(ancestorKey: kRootNodeKey, prevState: currentEditorState, nextState: pendingEditorState, editor: editor)

    // Selection reconcile
    let prevSelection = currentEditorState.selection
    let nextSelection = pendingEditorState.selection
    var selectionsAreDifferent = false
    if let nextSelection, let prevSelection { selectionsAreDifferent = !nextSelection.isSelection(prevSelection) }
    let needsUpdate = editor.dirtyType != .noDirtyNodes
    if shouldReconcileSelection && (needsUpdate || nextSelection == nil || selectionsAreDifferent) {
      try reconcileSelection(prevSelection: prevSelection, nextSelection: nextSelection, editor: editor)
    }

    if editor.featureFlags.useReconcilerShadowCompare { print("🔥 OPTIMIZED RECONCILER: optimized slow path applied (full rebuild)") }
    if let metrics = editor.metricsContainer {
      let metric = ReconcilerMetric(
        duration: 0, dirtyNodes: editor.dirtyNodes.count, rangesAdded: 0, rangesDeleted: 0,
        treatedAllNodesAsDirty: true, pathLabel: "slow")
      metrics.record(.reconcilerRun(metric))
    }
  }

  // MARK: - Fast path: single TextNode content change
  @MainActor
  private static func fastPath_TextOnly(
    currentEditorState: EditorState,
    pendingEditorState: EditorState,
    editor: Editor,
    shouldReconcileSelection: Bool,
    fenwickAggregatedDeltas: inout [NodeKey: Int]
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
          if let metrics = editor.metricsContainer {
            let metric = ReconcilerMetric(
              duration: 0, dirtyNodes: editor.dirtyNodes.count, rangesAdded: 0, rangesDeleted: 0,
              treatedAllNodesAsDirty: false, pathLabel: "attr-only", planningDuration: 0,
              applyDuration: 0, deleteCount: 0, insertCount: 0, setAttributesCount: 1, fixAttributesCount: 1)
            metrics.record(.reconcilerRun(metric))
          }
          if editor.featureFlags.useReconcilerShadowCompare { print("🔥 OPTIMIZED RECONCILER: attribute-only fast path applied") }
          return true
        }
      }
      // Content changed but length kept → try pre/post part deltas for element siblings, else fallback
      return false
    }

    // Prepare DFS order for potential multi-node location shifts (Fenwick available via helper when used)
    let keysInOrder = sortedNodeKeysByLocation(rangeCache: editor.rangeCache)
    var indexOf: [NodeKey: Int] = [:]
    indexOf.reserveCapacity(keysInOrder.count)
    for (i, k) in keysInOrder.enumerated() { indexOf[k] = i + 1 }

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

    // Insert-block builds complete attributed content; we can skip fixAttributes here.
    let stats = applyInstructions(instructions, editor: editor, fixAttributesEnabled: false)

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
      if editor.featureFlags.useReconcilerFenwickCentralAggregation {
        fenwickAggregatedDeltas[dirtyKey, default: 0] += delta
      } else {
        editor.rangeCache = rebuildLocationsWithFenwick(prev: editor.rangeCache, deltas: [dirtyKey: delta])
      }
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

    if let metrics = editor.metricsContainer {
      let metric = ReconcilerMetric(
        duration: 0, dirtyNodes: editor.dirtyNodes.count, rangesAdded: 0, rangesDeleted: 0,
        treatedAllNodesAsDirty: false, pathLabel: "text-only", planningDuration: 0,
        applyDuration: stats.duration, deleteCount: stats.deletes, insertCount: stats.inserts,
        setAttributesCount: stats.sets, fixAttributesCount: stats.fixes)
      metrics.record(.reconcilerRun(metric))
    }
    if editor.featureFlags.useReconcilerShadowCompare { print("🔥 OPTIMIZED RECONCILER: text-only fast path applied (delta=\(delta))") }
    return true
  }

  // MARK: - Fast path: insert block (single new direct child under an Element)
  @MainActor
  private static func fastPath_InsertBlock(
    currentEditorState: EditorState,
    pendingEditorState: EditorState,
    editor: Editor,
    shouldReconcileSelection: Bool,
    fenwickAggregatedDeltas: inout [NodeKey: Int]
  ) throws -> Bool {
    // Find a parent Element whose children gained exactly one child (no removals)
    // and no other structural deltas.
    let dirtyParents = editor.dirtyNodes.keys.compactMap { key -> (NodeKey, ElementNode, ElementNode)? in
      guard let prev = currentEditorState.nodeMap[key] as? ElementNode,
            let next = pendingEditorState.nodeMap[key] as? ElementNode else { return nil }
      return (key, prev, next)
    }
    guard let cand = dirtyParents.first(where: { (parentKey, prev, next) in
      let prevChildren = prev.getChildrenKeys(fromLatest: false)
      let nextChildren = next.getChildrenKeys(fromLatest: false)
      if nextChildren.count != prevChildren.count + 1 { return false }
      let prevSet = Set(prevChildren)
      let nextSet = Set(nextChildren)
      let added = nextSet.subtracting(prevSet)
      let removed = prevSet.subtracting(nextSet)
      return added.count == 1 && removed.isEmpty
    }) else { return false }

    let (parentKey, prevParent, nextParent) = cand
    let prevChildren = prevParent.getChildrenKeys(fromLatest: false)
    let nextChildren = nextParent.getChildrenKeys(fromLatest: false)
    let prevSet = Set(prevChildren)
    let addedKey = Set(nextChildren).subtracting(prevSet).first!

    // Compute insert index in nextChildren
    guard let insertIndex = nextChildren.firstIndex(of: addedKey) else { return false }
    guard let parentPrevRange = editor.rangeCache[parentKey] else { return false }
    let childrenStart = parentPrevRange.location + parentPrevRange.preambleLength
    // Sum lengths of previous siblings that existed before
    var acc = 0
    for k in nextChildren.prefix(insertIndex) {
      if let r = editor.rangeCache[k]?.range {
        acc += r.length
      } else {
        acc += subtreeTotalLength(nodeKey: k, state: currentEditorState)
      }
    }
    let insertLoc = childrenStart + acc
    let theme = editor.getTheme()
    var instructions: [Instruction] = []

    // If inserting not at index 0, the previous sibling's postamble may change (e.g., add a newline).
    // We replace old postamble (if any) and insert the new postamble + the new block in a single combined insert.
    var totalShift = 0
    var combinedInsertPrefix: NSAttributedString? = nil
    var deleteOldPostRange: NSRange? = nil
    if insertIndex > 0 {
      let prevSiblingKey = nextChildren[insertIndex - 1]
      if let prevSiblingRange = editor.rangeCache[prevSiblingKey],
         let prevSiblingNext = pendingEditorState.nodeMap[prevSiblingKey] {
        let oldPost = prevSiblingRange.postambleLength
        let newPost = prevSiblingNext.getPostamble().lengthAsNSString()
        if newPost != oldPost {
          let postLoc = prevSiblingRange.location + prevSiblingRange.preambleLength + prevSiblingRange.childrenLength + prevSiblingRange.textLength
          // Will delete old postamble (if present) and then insert (newPost + new block) at postLoc
          if oldPost > 0 { deleteOldPostRange = NSRange(location: postLoc, length: oldPost) }
          let postAttrStr = AttributeUtils.attributedStringByAddingStyles(NSAttributedString(string: prevSiblingNext.getPostamble()), from: prevSiblingNext, state: pendingEditorState, theme: theme)
          if postAttrStr.length > 0 { combinedInsertPrefix = postAttrStr }
          // Update cache + ancestor childrenLength and account for location shift for following content
          let deltaPost = newPost - oldPost
          totalShift += deltaPost
          if var it = editor.rangeCache[prevSiblingKey] { it.postambleLength = newPost; editor.rangeCache[prevSiblingKey] = it }
          // bump ancestors
          let parents = prevSiblingNext.getParents().map { $0.getKey() }
          for pk in parents { if var item = editor.rangeCache[pk] { item.childrenLength += deltaPost; editor.rangeCache[pk] = item } }
          // insertion happens at original postLoc; combinedInsertPrefix accounts for the new postamble content
        }
      }
    }

    let attr = buildAttributedSubtree(nodeKey: addedKey, state: pendingEditorState, theme: theme)
    if let del = deleteOldPostRange { instructions.append(.delete(range: del)) }
    if attr.length > 0 {
      if let prefix = combinedInsertPrefix {
        let combined = NSMutableAttributedString(attributedString: prefix)
        combined.append(attr)
        instructions.append(.insert(location: insertLoc, attrString: combined))
      } else {
        instructions.append(.insert(location: insertLoc, attrString: attr))
      }
    }
    if instructions.isEmpty { return false }

    let stats = applyInstructions(instructions, editor: editor)

    // Prefer Fenwick range shift when Fenwick deltas are enabled
    if editor.featureFlags.useReconcilerFenwickDelta || editor.featureFlags.useReconcilerInsertBlockFenwick {
      // Compute range cache only for the inserted subtree at its final location
      let insertedLen = attr.length
      _ = recomputeRangeCacheSubtree(
        nodeKey: addedKey, state: pendingEditorState, startLocation: insertLoc, editor: editor)

      // Update parent + ancestor part lengths (childrenLength) without walking unrelated subtrees
      if let addedNode = pendingEditorState.nodeMap[addedKey] {
        let parents = addedNode.getParents().map { $0.getKey() }
        for pk in parents {
          if var item = editor.rangeCache[pk] { item.childrenLength += insertedLen; editor.rangeCache[pk] = item }
        }
      }

      // Shift locations of nodes at/after the insertion point using a range-based Fenwick rebuild.
      // Start at the next existing sibling (prev state) or the first key after the parent's subtree end.
      var startKeyForShift: NodeKey? = nil
      if insertIndex < prevChildren.count {
        startKeyForShift = prevChildren[insertIndex]
      } else {
        // Find first key whose location is >= end of the parent's subtree (prev state)
        let parentEnd = parentPrevRange.location + parentPrevRange.range.length
        startKeyForShift = firstKey(afterOrAt: parentEnd, in: editor.rangeCache)
      }
      if let startKeyForShift {
        editor.rangeCache = rebuildLocationsWithFenwickRanges(
          prev: editor.rangeCache,
          ranges: [(startKey: startKeyForShift, endKeyExclusive: nil, delta: totalShift + insertedLen)]
        )
      }

      // Reconcile decorators within the inserted subtree (mark additions, set positions)
      reconcileDecoratorOpsForSubtree(
        ancestorKey: addedKey,
        prevState: currentEditorState,
        nextState: pendingEditorState,
        editor: editor
      )
    } else {
      // Legacy-safe: recompute the entire parent subtree range cache to keep all postamble changes accurate
      _ = recomputeRangeCacheSubtree(
        nodeKey: parentKey, state: pendingEditorState, startLocation: parentPrevRange.location,
        editor: editor)
      // Reconcile decorators for parent subtree (covers additions for the new block)
      reconcileDecoratorOpsForSubtree(ancestorKey: parentKey, prevState: currentEditorState, nextState: pendingEditorState, editor: editor)
    }

    // Block attributes only for inserted node
    applyBlockAttributesPass(
      editor: editor, pendingEditorState: pendingEditorState, affectedKeys: [addedKey],
      treatAllNodesAsDirty: false)

    // Selection reconcile mirrors other fast paths
    let prevSelection = currentEditorState.selection
    let nextSelection = pendingEditorState.selection
    var selectionsAreDifferent = false
    if let nextSelection, let prevSelection { selectionsAreDifferent = !nextSelection.isSelection(prevSelection) }
    let needsUpdate = editor.dirtyType != .noDirtyNodes
    if shouldReconcileSelection && (needsUpdate || nextSelection == nil || selectionsAreDifferent) {
      try reconcileSelection(prevSelection: prevSelection, nextSelection: nextSelection, editor: editor)
    }

    if let metrics = editor.metricsContainer {
      let metric = ReconcilerMetric(
        duration: 0, dirtyNodes: editor.dirtyNodes.count, rangesAdded: 0, rangesDeleted: 0,
        treatedAllNodesAsDirty: false, pathLabel: "insert-block", planningDuration: 0,
        applyDuration: stats.duration, deleteCount: stats.deletes, insertCount: stats.inserts,
        setAttributesCount: stats.sets, fixAttributesCount: stats.fixes)
      metrics.record(.reconcilerRun(metric))
    }
    if editor.featureFlags.useReconcilerShadowCompare {
      print("🔥 OPTIMIZED RECONCILER: insert-block fast path (parent=\(parentKey), at=\(insertIndex))")
    }
    return true
  }

  // Find first key whose cached location is >= targetLocation
  @MainActor
  private static func firstKey(afterOrAt targetLocation: Int, in cache: [NodeKey: RangeCacheItem]) -> NodeKey? {
    // Build ordered list once and binary search by location
    let ordered = cache.map { ($0.key, $0.value.location) }.sorted { $0.1 < $1.1 }
    guard !ordered.isEmpty else { return nil }
    var lo = 0, hi = ordered.count - 1
    var ans: NodeKey? = nil
    while lo <= hi {
      let mid = (lo + hi) / 2
      let loc = ordered[mid].1
      if loc >= targetLocation {
        ans = ordered[mid].0
        if mid == 0 { break }
        hi = mid - 1
      } else {
        lo = mid + 1
      }
    }
    return ans
  }

  // Multi-text changes in one pass (central aggregation only)
  @MainActor
  private static func fastPath_TextOnly_Multi(
    currentEditorState: EditorState,
    pendingEditorState: EditorState,
    editor: Editor,
    fenwickAggregatedDeltas: inout [NodeKey: Int]
  ) throws -> Bool {
    guard editor.featureFlags.useReconcilerFenwickDelta && editor.featureFlags.useReconcilerFenwickCentralAggregation else { return false }
    // Collect all TextNodes whose text changed
    let candidates: [NodeKey] = editor.dirtyNodes.keys.compactMap { key in
      guard let prev = currentEditorState.nodeMap[key] as? TextNode,
            let next = pendingEditorState.nodeMap[key] as? TextNode,
            let prevRange = editor.rangeCache[key] else { return nil }
      let oldText = prev.getTextPart()
      let newText = next.getTextPart()
      if oldText == newText { return nil }
      // Ensure children and pre/post unchanged
      if prevRange.preambleLength != next.getPreamble().lengthAsNSString() { return nil }
      if prevRange.postambleLength != next.getPostamble().lengthAsNSString() { return nil }
      return key
    }
    if candidates.isEmpty { return false }

    // Build instructions across all candidates based on previous ranges
    var instructions: [Instruction] = []
    var affected: Set<NodeKey> = []
    for key in candidates {
      guard let prev = currentEditorState.nodeMap[key] as? TextNode,
            let next = pendingEditorState.nodeMap[key] as? TextNode,
            let prevRange = editor.rangeCache[key] else { continue }
      let oldText = prev.getTextPart(); let newText = next.getTextPart()
      if oldText == newText { continue }
      let theme = editor.getTheme()
      let textStart = prevRange.location + prevRange.preambleLength + prevRange.childrenLength
      let deleteRange = NSRange(location: textStart, length: oldText.lengthAsNSString())
      if deleteRange.length > 0 { instructions.append(.delete(range: deleteRange)) }
      let attr = AttributeUtils.attributedStringByAddingStyles(NSAttributedString(string: newText), from: next, state: pendingEditorState, theme: theme)
      if attr.length > 0 { instructions.append(.insert(location: textStart, attrString: attr)) }

      let delta = newText.lengthAsNSString() - oldText.lengthAsNSString()
      // Update lengths and parents immediately
      if var item = editor.rangeCache[key] { item.textLength = newText.lengthAsNSString(); editor.rangeCache[key] = item }
      let parents = next.getParents().map { $0.getKey() }
      for pk in parents { if var it = editor.rangeCache[pk] { it.childrenLength += delta; editor.rangeCache[pk] = it } }
      fenwickAggregatedDeltas[key, default: 0] += delta
      affected.insert(key); for p in parents { affected.insert(p) }
    }
    if instructions.isEmpty { return false }
    let stats = applyInstructions(instructions, editor: editor)

    // Update decorator positions after location rebuild at end (done in caller)
    // Apply block-level attributes scoped to affected nodes
    applyBlockAttributesPass(editor: editor, pendingEditorState: pendingEditorState, affectedKeys: affected, treatAllNodesAsDirty: false)

    if let metrics = editor.metricsContainer {
      let metric = ReconcilerMetric(duration: 0, dirtyNodes: editor.dirtyNodes.count, rangesAdded: 0, rangesDeleted: 0, treatedAllNodesAsDirty: false, pathLabel: "text-only-multi", planningDuration: 0, applyDuration: stats.duration, deleteCount: 0, insertCount: 0, setAttributesCount: 0, fixAttributesCount: 1)
      metrics.record(.reconcilerRun(metric))
    }
    return true
  }

  // Multi pre/post changes in one pass (central aggregation only)
  @MainActor
  private static func fastPath_PreamblePostambleOnly_Multi(
    currentEditorState: EditorState,
    pendingEditorState: EditorState,
    editor: Editor,
    fenwickAggregatedDeltas: inout [NodeKey: Int]
  ) throws -> Bool {
    guard editor.featureFlags.useReconcilerFenwickDelta && editor.featureFlags.useReconcilerFenwickCentralAggregation else { return false }
    var targets: [NodeKey] = []
    for key in editor.dirtyNodes.keys {
      guard let next = pendingEditorState.nodeMap[key], let prevRange = editor.rangeCache[key] else { continue }
      // children/text unchanged
      if next.getTextPart().lengthAsNSString() != prevRange.textLength { continue }
      var computedChildrenLen = 0
      if let el = next as? ElementNode { for c in el.getChildrenKeys() { computedChildrenLen += subtreeTotalLength(nodeKey: c, state: pendingEditorState) } }
      if computedChildrenLen != prevRange.childrenLength { continue }
      let np = next.getPreamble().lengthAsNSString(); let npo = next.getPostamble().lengthAsNSString()
      if np != prevRange.preambleLength || npo != prevRange.postambleLength { targets.append(key) }
    }
    if targets.isEmpty { return false }
    var instructions: [Instruction] = []
    var affected: Set<NodeKey> = []
    let theme = editor.getTheme()
    for key in targets {
      guard let next = pendingEditorState.nodeMap[key], let prevRange = editor.rangeCache[key] else { continue }
      let np = next.getPreamble(); let npo = next.getPostamble()
      let nextPreLen = np.lengthAsNSString(); let nextPostLen = npo.lengthAsNSString()
      if nextPostLen != prevRange.postambleLength {
        let postLoc = prevRange.location + prevRange.preambleLength + prevRange.childrenLength + prevRange.textLength
        let oldR = NSRange(location: postLoc, length: prevRange.postambleLength)
        instructions.append(.delete(range: oldR))
        let postAttr = AttributeUtils.attributedStringByAddingStyles(NSAttributedString(string: npo), from: next, state: pendingEditorState, theme: theme)
        if postAttr.length > 0 { instructions.append(.insert(location: postLoc, attrString: postAttr)) }
        let delta = nextPostLen - prevRange.postambleLength
        if var item = editor.rangeCache[key] { item.postambleLength = nextPostLen; editor.rangeCache[key] = item }
        if let n = pendingEditorState.nodeMap[key] { let parents = n.getParents().map { $0.getKey() }; for pk in parents { if var it = editor.rangeCache[pk] { it.childrenLength += delta; editor.rangeCache[pk] = it } } ; for p in parents { affected.insert(p) } }
        fenwickAggregatedDeltas[key, default: 0] += delta
      } else if nextPostLen > 0 { // same length: prefer attributes-only update
        let postLoc = prevRange.location + prevRange.preambleLength + prevRange.childrenLength + prevRange.textLength
        let rng = NSRange(location: postLoc, length: nextPostLen)
        let postAttr = AttributeUtils.attributedStringByAddingStyles(NSAttributedString(string: npo), from: next, state: pendingEditorState, theme: theme)
        let attrs = postAttr.attributes(at: 0, effectiveRange: nil)
        instructions.append(.setAttributes(range: rng, attributes: attrs))
      }
      if nextPreLen != prevRange.preambleLength {
        let preLoc = prevRange.location
        let oldR = NSRange(location: preLoc, length: prevRange.preambleLength)
        instructions.append(.delete(range: oldR))
        let preAttr = AttributeUtils.attributedStringByAddingStyles(NSAttributedString(string: np), from: next, state: pendingEditorState, theme: theme)
        if preAttr.length > 0 { instructions.append(.insert(location: preLoc, attrString: preAttr)) }
        let delta = nextPreLen - prevRange.preambleLength
        let preSpecial = np.lengthAsNSString(includingCharacters: ["\u{200B}"])
        if var item = editor.rangeCache[key] { item.preambleLength = nextPreLen; item.preambleSpecialCharacterLength = preSpecial; editor.rangeCache[key] = item }
        if let n = pendingEditorState.nodeMap[key] { let parents = n.getParents().map { $0.getKey() }; for pk in parents { if var it = editor.rangeCache[pk] { it.childrenLength += delta; editor.rangeCache[pk] = it } } ; for p in parents { affected.insert(p) } }
        fenwickAggregatedDeltas[key, default: 0] += delta
      } else if nextPreLen > 0 {
        let preLoc = prevRange.location
        let rng = NSRange(location: preLoc, length: nextPreLen)
        let preAttr = AttributeUtils.attributedStringByAddingStyles(NSAttributedString(string: np), from: next, state: pendingEditorState, theme: theme)
        let attrs = preAttr.attributes(at: 0, effectiveRange: nil)
        instructions.append(.setAttributes(range: rng, attributes: attrs))
      }
      affected.insert(key)
    }
    if instructions.isEmpty { return false }
    let stats = applyInstructions(instructions, editor: editor)
    applyBlockAttributesPass(editor: editor, pendingEditorState: pendingEditorState, affectedKeys: affected, treatAllNodesAsDirty: false)
    if let metrics = editor.metricsContainer {
      let metric = ReconcilerMetric(duration: 0, dirtyNodes: editor.dirtyNodes.count, rangesAdded: 0, rangesDeleted: 0, treatedAllNodesAsDirty: false, pathLabel: "prepost-only-multi", planningDuration: 0, applyDuration: stats.duration, deleteCount: 0, insertCount: 0, setAttributesCount: 0, fixAttributesCount: 1)
      metrics.record(.reconcilerRun(metric))
    }
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
    if editor.featureFlags.useReconcilerShadowCompare { print("🔥 OPTIMIZED RECONCILER: reorder candidates parent=\(parentKey) total=\(nextChildren.count) stable=\(stableSet.count)") }

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
    // Heuristic: prefer minimal moves when the total bytes moved is small relative to the region,
    // otherwise rebuild the region in one replace.
    let movedByteSum: Int = nextChildren.reduce(0) { acc, k in
      if !stableSet.contains(k), let item = editor.rangeCache[k] { return acc + item.range.length } else { return acc }
    }
    let regionBytes = childrenRange.length
    let movedRatio = regionBytes > 0 ? Double(movedByteSum) / Double(regionBytes) : 0.0
    // Base on both moved count vs total and moved byte ratio; lean to minimal for small fractions
    let preferMinimalMoves = (movedCount <= max(2, nextChildren.count / 6)) || (movedRatio <= 0.35)
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

      let stats = applyInstructions(instructions, editor: editor)
      if let metrics = editor.metricsContainer {
        let metric = ReconcilerMetric(
          duration: 0, dirtyNodes: editor.dirtyNodes.count, rangesAdded: 0, rangesDeleted: 0,
          treatedAllNodesAsDirty: false, pathLabel: "reorder-minimal", planningDuration: 0,
          applyDuration: stats.duration, deleteCount: stats.deletes, insertCount: stats.inserts,
          setAttributesCount: stats.sets, fixAttributesCount: stats.fixes, movedChildren: movedCount)
        metrics.record(.reconcilerRun(metric))
      }
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
      if let metrics = editor.metricsContainer {
        let metric = ReconcilerMetric(
          duration: 0, dirtyNodes: editor.dirtyNodes.count, rangesAdded: 0, rangesDeleted: 0,
          treatedAllNodesAsDirty: false, pathLabel: "reorder-rebuild", movedChildren: movedCount)
        metrics.record(.reconcilerRun(metric))
      }
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

    // Shift locations for each direct child subtree via Fenwick range adds
    var rangeShifts: [(NodeKey, NodeKey?, Int)] = []
    // Build DFS/location order indices from current cache
    let orderedKeys = sortedNodeKeysByLocation(rangeCache: editor.rangeCache)
    var indexOf: [NodeKey: Int] = [:]; indexOf.reserveCapacity(orderedKeys.count)
    for (i, k) in orderedKeys.enumerated() { indexOf[k] = i + 1 }

    for k in nextChildrenOrder {
      guard let oldStart = childOldStart[k], let newStart = childNewStart[k] else { continue }
      let deltaShift = newStart - oldStart
      if deltaShift == 0 { continue }
      // Determine subtree end (exclusive) in orderedKeys
      let subKeys = subtreeKeysDFS(rootKey: k, state: pendingEditorState)
      var maxIdx = 0
      for sk in subKeys { if let idx = indexOf[sk], idx > maxIdx { maxIdx = idx } }
      let endExclusive: NodeKey? = (maxIdx < orderedKeys.count) ? orderedKeys[maxIdx] : nil
      rangeShifts.append((k, endExclusive, deltaShift))
    }
    if !rangeShifts.isEmpty {
      editor.rangeCache = rebuildLocationsWithFenwickRanges(prev: editor.rangeCache, ranges: rangeShifts)
    }

    // Reconcile decorators within this subtree (moves preserve cache; dirty -> needsDecorating)
    reconcileDecoratorOpsForSubtree(ancestorKey: parentKey, prevState: currentEditorState, nextState: pendingEditorState, editor: editor)

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

      if editor.featureFlags.useReconcilerShadowCompare { print("🔥 OPTIMIZED RECONCILER: children reorder fast path applied (parent=\(parentKey), moved=\(movedCount), total=\(nextChildren.count))") }
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
    shouldReconcileSelection: Bool,
    fenwickAggregatedDeltas: inout [NodeKey: Int]
  ) throws -> Bool {
    guard editor.dirtyNodes.count == 1, let dirtyKey = editor.dirtyNodes.keys.first else {
      return false
    }
    guard let _ = currentEditorState.nodeMap[dirtyKey],
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
        if editor.featureFlags.useReconcilerFenwickCentralAggregation {
          fenwickAggregatedDeltas[dirtyKey, default: 0] += delta
        } else {
          editor.rangeCache = rebuildLocationsWithFenwick(prev: editor.rangeCache, deltas: [dirtyKey: delta])
        }
      } else {
        updateRangeCacheForNodePartChange(nodeKey: dirtyKey, part: .postamble, newPartLength: nextPostLen, delta: delta)
      }
    } else if nextPostLen == prevRange.postambleLength && nextPostLen > 0 {
      // Same length: update attributes only
      let postLoc = prevRange.location + prevRange.preambleLength + prevRange.childrenLength + prevRange.textLength
      let rng = NSRange(location: postLoc, length: nextPostLen)
      let postAttr = AttributeUtils.attributedStringByAddingStyles(
        NSAttributedString(string: nextNode.getPostamble()), from: nextNode, state: pendingEditorState,
        theme: theme)
      let attrs = postAttr.attributes(at: 0, effectiveRange: nil)
      applied.append(.setAttributes(range: rng, attributes: attrs))
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
        if editor.featureFlags.useReconcilerFenwickCentralAggregation {
          fenwickAggregatedDeltas[dirtyKey, default: 0] += delta
        } else {
          editor.rangeCache = rebuildLocationsWithFenwick(prev: editor.rangeCache, deltas: [dirtyKey: delta])
        }
      } else {
        updateRangeCacheForNodePartChange(nodeKey: dirtyKey, part: .preamble, newPartLength: nextPreLen, preambleSpecialCharacterLength: preSpecial, delta: delta)
      }
    } else if nextPreLen == prevRange.preambleLength && nextPreLen > 0 {
      // Same length: update attributes only
      let preLoc = prevRange.location
      let rng = NSRange(location: preLoc, length: nextPreLen)
      let preAttr = AttributeUtils.attributedStringByAddingStyles(
        NSAttributedString(string: nextNode.getPreamble()), from: nextNode, state: pendingEditorState,
        theme: theme)
      let attrs = preAttr.attributes(at: 0, effectiveRange: nil)
      applied.append(.setAttributes(range: rng, attributes: attrs))
    }
    let stats = applyInstructions(applied, editor: editor)

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

    if let metrics = editor.metricsContainer {
      let metric = ReconcilerMetric(
        duration: 0, dirtyNodes: editor.dirtyNodes.count, rangesAdded: 0, rangesDeleted: 0,
        treatedAllNodesAsDirty: false, pathLabel: "prepost-only", planningDuration: 0,
        applyDuration: stats.duration, deleteCount: stats.deletes, insertCount: stats.inserts,
        setAttributesCount: stats.sets, fixAttributesCount: stats.fixes)
      metrics.record(.reconcilerRun(metric))
    }
    if editor.featureFlags.useReconcilerShadowCompare { print("🔥 OPTIMIZED RECONCILER: pre/post fast path applied (key=\(dirtyKey))") }
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
    if let metrics = editor.metricsContainer {
      let metric = ReconcilerMetric(
        duration: 0, dirtyNodes: editor.dirtyNodes.count, rangesAdded: 0, rangesDeleted: 0,
        treatedAllNodesAsDirty: false, pathLabel: "composition-start")
      metrics.record(.reconcilerRun(metric))
    }
    if editor.featureFlags.useReconcilerShadowCompare { print("🔥 OPTIMIZED RECONCILER: composition fast path applied (len=\(markedAttr.length))") }
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
          let _ = currentEditorState.nodeMap[ancestorKey] as? ElementNode,
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

    // Metrics (planning timing and diff counts)
    if let metrics = editor.metricsContainer {
      let diffs = computePartDiffs(editor: editor, prevState: currentEditorState, nextState: pendingEditorState)
      let changed = diffs.count
      let metric = ReconcilerMetric(
        duration: 0, dirtyNodes: editor.dirtyNodes.count, rangesAdded: 1, rangesDeleted: 1,
        treatedAllNodesAsDirty: false, pathLabel: "coalesced-replace", planningDuration: 0,
        applyDuration: 0, deleteCount: 1, insertCount: 1, setAttributesCount: 0, fixAttributesCount: 1)
      metrics.record(.reconcilerRun(metric))
      _ = changed // placeholder for potential future thresholds
    }

    // Recompute the range cache for this subtree (locations and lengths) and reconcile decorators
    _ = recomputeRangeCacheSubtree(
      nodeKey: ancestorKey, state: pendingEditorState, startLocation: ancestorPrevRange.location,
      editor: editor)
    pruneRangeCacheUnderAncestor(ancestorKey: ancestorKey, prevState: currentEditorState, nextState: pendingEditorState, editor: editor)
    reconcileDecoratorOpsForSubtree(ancestorKey: ancestorKey, prevState: currentEditorState, nextState: pendingEditorState, editor: editor)

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

    if editor.featureFlags.useReconcilerShadowCompare { print("🔥 OPTIMIZED RECONCILER: coalesced contiguous region replace (ancestor=\(ancestorKey), dirty=\(editor.dirtyNodes.count))") }
    if let metrics = editor.metricsContainer {
      let metric = ReconcilerMetric(
        duration: 0, dirtyNodes: editor.dirtyNodes.count, rangesAdded: 0, rangesDeleted: 0,
        treatedAllNodesAsDirty: false, pathLabel: "coalesced-replace")
      metrics.record(.reconcilerRun(metric))
    }
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

  // MARK: - RangeCache pruning helpers
  @MainActor
  private static func pruneRangeCacheGlobally(nextState: EditorState, editor: Editor) {
    var attached = Set(subtreeKeysDFS(rootKey: kRootNodeKey, state: nextState))
    attached.insert(kRootNodeKey)
    editor.rangeCache = editor.rangeCache.filter { attached.contains($0.key) }
  }

  @MainActor
  private static func pruneRangeCacheUnderAncestor(
    ancestorKey: NodeKey, prevState: EditorState, nextState: EditorState, editor: Editor
  ) {
    // Compute keys previously under ancestor
    let prevKeys = Set(subtreeKeysDFS(rootKey: ancestorKey, state: prevState))
    let nextKeys = Set(subtreeKeysDFS(rootKey: ancestorKey, state: nextState))
    let toRemove = prevKeys.subtracting(nextKeys)
    if toRemove.isEmpty { return }
    editor.rangeCache = editor.rangeCache.filter { !toRemove.contains($0.key) }
  }

  // MARK: - Decorator reconciliation
  @MainActor
  private static func reconcileDecoratorOpsForSubtree(
    ancestorKey: NodeKey,
    prevState: EditorState,
    nextState: EditorState,
    editor: Editor
  ) {
    guard let textStorage = editor.textStorage else { return }

    func decoratorKeys(in state: EditorState, under root: NodeKey) -> Set<NodeKey> {
      let keys = subtreeKeysDFS(rootKey: root, state: state)
      var out: Set<NodeKey> = []
      for k in keys { if state.nodeMap[k] is DecoratorNode { out.insert(k) } }
      return out
    }

    let prevDecos = decoratorKeys(in: prevState, under: ancestorKey)
    let nextDecos = decoratorKeys(in: nextState, under: ancestorKey)

    // Removals: purge position + cache and destroy views
    let removed = prevDecos.subtracting(nextDecos)
    for k in removed {
      decoratorView(forKey: k, createIfNecessary: false)?.removeFromSuperview()
      destroyCachedDecoratorView(forKey: k)
      textStorage.decoratorPositionCache[k] = nil
    }

    // Additions: ensure cache entry exists and set position
    let added = nextDecos.subtracting(prevDecos)
    for k in added {
      if editor.decoratorCache[k] == nil { editor.decoratorCache[k] = .needsCreation }
      if let loc = editor.rangeCache[k]?.location { textStorage.decoratorPositionCache[k] = loc }
    }

    // Persist positions for all present decorators in next subtree and mark dirty ones for decorating
    for k in nextDecos {
      if let loc = editor.rangeCache[k]?.location { textStorage.decoratorPositionCache[k] = loc }
      if editor.dirtyNodes[k] != nil {
        if let cacheItem = editor.decoratorCache[k], let view = cacheItem.view {
          editor.decoratorCache[k] = .needsDecorating(view)
        }
      }
    }
  }
}
