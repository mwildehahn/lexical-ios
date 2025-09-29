/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import UIKit
import QuartzCore

// Optimized reconciler entry point. Initially a thin wrapper so we can land
// the feature flag, metrics, and supporting data structures incrementally.

internal enum OptimizedReconciler {
  struct InstructionApplyStats { let deletes: Int; let inserts: Int; let sets: Int; let fixes: Int; let duration: TimeInterval }
  @MainActor
  private static func fenwickOrderAndIndex(editor: Editor) -> ([NodeKey], [NodeKey: Int]) {
    let order = editor.cachedDFSOrder()
    var index: [NodeKey: Int] = [:]
    index.reserveCapacity(order.count)
    for (i, key) in order.enumerated() { index[key] = i + 1 }
    return (order, index)
  }
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

  // Planner: collect text-only multi instructions without applying
  @MainActor
  private static func plan_TextOnly_Multi(
    currentEditorState: EditorState,
    pendingEditorState: EditorState,
    editor: Editor
  ) throws -> (instructions: [Instruction], lengthChanges: [(nodeKey: NodeKey, part: NodePart, delta: Int)], affected: Set<NodeKey>)? {
    guard editor.featureFlags.useReconcilerFenwickDelta && editor.featureFlags.useReconcilerFenwickCentralAggregation else { return nil }
    let candidates: [NodeKey] = editor.dirtyNodes.keys.compactMap { key in
      guard let prev = currentEditorState.nodeMap[key] as? TextNode,
            let next = pendingEditorState.nodeMap[key] as? TextNode,
            let prevRange = editor.rangeCache[key] else { return nil }
      let oldText = prev.getTextPart(); let newText = next.getTextPart()
      if oldText == newText { return nil }
      if prevRange.preambleLength != next.getPreamble().lengthAsNSString() { return nil }
      if prevRange.postambleLength != next.getPostamble().lengthAsNSString() { return nil }
      return key
    }
    if candidates.isEmpty { return nil }
    var instructions: [Instruction] = []
    var affected: Set<NodeKey> = []
    var lengthChanges: [(nodeKey: NodeKey, part: NodePart, delta: Int)] = []
    let theme = editor.getTheme()
    for key in candidates {
      guard let prev = currentEditorState.nodeMap[key] as? TextNode,
            let next = pendingEditorState.nodeMap[key] as? TextNode,
            let prevRange = editor.rangeCache[key] else { continue }
      let oldText = prev.getTextPart(); let newText = next.getTextPart()
      if oldText == newText { continue }
      let textStart = prevRange.location + prevRange.preambleLength + prevRange.childrenLength
      let deleteRange = NSRange(location: textStart, length: oldText.lengthAsNSString())
      if deleteRange.length > 0 { instructions.append(.delete(range: deleteRange)) }
      let attr = AttributeUtils.attributedStringByAddingStyles(NSAttributedString(string: newText), from: next, state: pendingEditorState, theme: theme)
      if attr.length > 0 { instructions.append(.insert(location: textStart, attrString: attr)) }
      let delta = newText.lengthAsNSString() - oldText.lengthAsNSString()
      lengthChanges.append((nodeKey: key, part: .text, delta: delta))
      affected.insert(key)
      for p in next.getParents() { affected.insert(p.getKey()) }
    }
    return instructions.isEmpty ? nil : (instructions, lengthChanges, affected)
  }

  // Planner: collect pre/post-only multi instructions without applying
  @MainActor
  private static func plan_PreamblePostambleOnly_Multi(
    currentEditorState: EditorState,
    pendingEditorState: EditorState,
    editor: Editor
  ) throws -> (instructions: [Instruction], lengthChanges: [(nodeKey: NodeKey, part: NodePart, delta: Int)], affected: Set<NodeKey>)? {
    guard editor.featureFlags.useReconcilerFenwickDelta && editor.featureFlags.useReconcilerFenwickCentralAggregation else { return nil }
    var targets: [NodeKey] = []
    for key in editor.dirtyNodes.keys {
      guard let next = pendingEditorState.nodeMap[key], let prevRange = editor.rangeCache[key] else { continue }
      if next.getTextPart().lengthAsNSString() != prevRange.textLength { continue }
      var computedChildrenLen = 0
      if let el = next as? ElementNode { for c in el.getChildrenKeys() { computedChildrenLen += subtreeTotalLength(nodeKey: c, state: pendingEditorState) } }
      if computedChildrenLen != prevRange.childrenLength { continue }
      let np = next.getPreamble().lengthAsNSString(); let npo = next.getPostamble().lengthAsNSString()
      if np == prevRange.preambleLength && npo == prevRange.postambleLength && (np > 0 || npo > 0) { targets.append(key) }
    }
    if targets.isEmpty { return nil }
    var instructions: [Instruction] = []
    var affected: Set<NodeKey> = []
    // attributes-only variant: no lengthChanges aggregation
    let theme = editor.getTheme()
    for key in targets {
      guard let next = pendingEditorState.nodeMap[key], let prevRange = editor.rangeCache[key] else { continue }
      let np = next.getPreamble(); let npo = next.getPostamble()
      let nextPreLen = np.lengthAsNSString(); let nextPostLen = npo.lengthAsNSString()
      if nextPostLen > 0 {
        let postLoc = prevRange.location + prevRange.preambleLength + prevRange.childrenLength + prevRange.textLength
        let rng = NSRange(location: postLoc, length: nextPostLen)
        let postAttr = AttributeUtils.attributedStringByAddingStyles(NSAttributedString(string: npo), from: next, state: pendingEditorState, theme: theme)
        let attrs = postAttr.attributes(at: 0, effectiveRange: nil)
        instructions.append(.setAttributes(range: rng, attributes: attrs))
      }
      if nextPreLen > 0 {
        let preLoc = prevRange.location
        let rng = NSRange(location: preLoc, length: nextPreLen)
        let preAttr = AttributeUtils.attributedStringByAddingStyles(NSAttributedString(string: np), from: next, state: pendingEditorState, theme: theme)
        let attrs = preAttr.attributes(at: 0, effectiveRange: nil)
        instructions.append(.setAttributes(range: rng, attributes: attrs))
      }
      affected.insert(key)
    }
    let lengthChanges: [(nodeKey: NodeKey, part: NodePart, delta: Int)] = []
    return instructions.isEmpty ? nil : (instructions, lengthChanges, affected)
  }
  
  // MARK: - Modern TextKit Optimizations (iOS 16+)
  
  @MainActor
  private static func applyInstructionsWithModernBatching(
    _ instructions: [Instruction],
    editor: Editor,
    fixAttributesEnabled: Bool = true
  ) -> InstructionApplyStats {
    guard let textStorage = editor.textStorage else {
      return InstructionApplyStats(deletes: 0, inserts: 0, sets: 0, fixes: 0, duration: 0)
    }
    
    let applyStart = CFAbsoluteTimeGetCurrent()
    
    // Step 1: Categorize all operations
    var deletes: [NSRange] = []
    var inserts: [(Int, NSAttributedString)] = []
    var sets: [(NSRange, [NSAttributedString.Key: Any])] = []
    var decoratorOps: [Instruction] = []
    var blockAttributeOps: [NodeKey] = []
    var fixCount = 0
    
    for inst in instructions {
      switch inst {
      case .delete(let r):
        deletes.append(r)
      case .insert(let loc, let s):
        inserts.append((loc, s))
      case .setAttributes(let r, let attrs):
        sets.append((r, attrs))
      case .fixAttributes:
        fixCount += 1
      case .decoratorAdd, .decoratorRemove, .decoratorDecorate:
        decoratorOps.append(inst)
      case .applyBlockAttributes(let key):
        blockAttributeOps.append(key)
      }
    }
    
    // Step 2: Optimize coalescing with Set-based deduplication
    let deletesCoalesced = optimizedBatchCoalesceDeletes(deletes)
    let insertsCoalesced = optimizedBatchCoalesceInserts(inserts)
    let setsCoalesced = optimizedBatchCoalesceAttributeSets(sets)
    
    // Step 3: Apply text changes in single batch transaction
    let previousMode = textStorage.mode
    textStorage.mode = .controllerMode
    
    // Wrap all operations in CATransaction for UI performance
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    defer {
      CATransaction.commit()
      textStorage.mode = previousMode
    }
    
    // Begin text storage editing batch
    textStorage.beginEditing()
    defer { textStorage.endEditing() }
    
    // Pre-calculate all safe ranges to minimize bounds checking
    var currentLength = textStorage.length
    var allModifiedRanges: [NSRange] = []
    allModifiedRanges.reserveCapacity(deletesCoalesced.count + insertsCoalesced.count + setsCoalesced.count)
    
    // Batch apply deletes (in reverse order for safety)
    if !deletesCoalesced.isEmpty {
      for r in deletesCoalesced where r.length > 0 {
        let safe = NSIntersectionRange(r, NSRange(location: 0, length: currentLength))
        if safe.length > 0 {
          textStorage.deleteCharacters(in: safe)
          allModifiedRanges.append(safe)
          currentLength -= safe.length
        }
      }
    }
    
    // Batch apply inserts with pre-allocated strings
    if !insertsCoalesced.isEmpty {
      for (loc, s) in insertsCoalesced where s.length > 0 {
        let safeLoc = max(0, min(loc, currentLength))
        textStorage.insert(s, at: safeLoc)
        allModifiedRanges.append(NSRange(location: safeLoc, length: s.length))
        currentLength += s.length
      }
    }
    
    // Batch apply attribute changes
    if !setsCoalesced.isEmpty {
      for (r, attrs) in setsCoalesced {
        let safe = NSIntersectionRange(r, NSRange(location: 0, length: currentLength))
        if safe.length > 0 {
          textStorage.setAttributes(attrs, range: safe)
          allModifiedRanges.append(safe)
        }
      }
    }
    
    // Step 4: Optimize fixAttributes with minimal range
    if fixAttributesEnabled && !allModifiedRanges.isEmpty {
      let cover = allModifiedRanges.reduce(allModifiedRanges[0]) { acc, r in
        NSRange(
          location: min(acc.location, r.location),
          length: max(NSMaxRange(acc), NSMaxRange(r)) - min(acc.location, r.location)
        )
      }
      textStorage.fixAttributes(in: cover)
    }
    
    // Step 5: Batch decorator operations without animations
    if !decoratorOps.isEmpty {
      UIView.performWithoutAnimation {
        for op in decoratorOps {
          switch op {
          case .decoratorAdd(let key):
            if let loc = editor.rangeCache[key]?.location {
              editor.textStorage?.decoratorPositionCache[key] = loc
            }
          case .decoratorRemove(let key):
            editor.textStorage?.decoratorPositionCache[key] = nil
          case .decoratorDecorate(let key):
            if let loc = editor.rangeCache[key]?.location {
              editor.textStorage?.decoratorPositionCache[key] = loc
            }
          default:
            break
          }
        }
      }
    }
    
    let applyDuration = CFAbsoluteTimeGetCurrent() - applyStart
    return InstructionApplyStats(
      deletes: deletesCoalesced.count,
      inserts: insertsCoalesced.count,
      sets: setsCoalesced.count,
      fixes: (fixCount > 0 ? 1 : 0),
      duration: applyDuration
    )
  }
  
  // MARK: - Optimized Batch Coalescing Functions
  
  @MainActor
  private static func optimizedBatchCoalesceDeletes(_ ranges: [NSRange]) -> [NSRange] {
    if ranges.isEmpty { return [] }
    
    // Use Set for O(1) deduplication
    var uniqueRanges = Set<NSRange>()
    for range in ranges {
      uniqueRanges.insert(range)
    }
    
    // Sort and merge overlapping/adjacent ranges
    let sorted = uniqueRanges.sorted { $0.location < $1.location }
    var merged: [NSRange] = []
    merged.reserveCapacity(sorted.count)
    
    var current = sorted[0]
    for r in sorted.dropFirst() {
      if NSMaxRange(current) >= r.location {
        // Merge overlapping or adjacent
        let end = max(NSMaxRange(current), NSMaxRange(r))
        current = NSRange(location: current.location, length: end - current.location)
      } else {
        merged.append(current)
        current = r
      }
    }
    merged.append(current)
    
    // Return in reverse order for safe deletion
    return merged.sorted { $0.location > $1.location }
  }
  
  @MainActor
  private static func optimizedBatchCoalesceInserts(_ ops: [(Int, NSAttributedString)]) -> [(Int, NSAttributedString)] {
    if ops.isEmpty { return [] }
    
    // Group by location with pre-allocated capacity
    let sorted = ops.sorted { $0.0 < $1.0 }
    var result: [(Int, NSMutableAttributedString)] = []
    result.reserveCapacity(ops.count)
    
    for (loc, s) in sorted {
      if let lastIndex = result.indices.last, result[lastIndex].0 == loc {
        // Batch concatenate at same location
        result[lastIndex].1.append(s)
      } else {
        // Pre-allocate mutable string with expected capacity
        let mutable = NSMutableAttributedString(attributedString: s)
        result.append((loc, mutable))
      }
    }
    
    // Convert to immutable for return
    return result.map { ($0.0, NSAttributedString(attributedString: $0.1)) }
  }
  
  @MainActor
  private static func optimizedBatchCoalesceAttributeSets(
    _ sets: [(NSRange, [NSAttributedString.Key: Any])]
  ) -> [(NSRange, [NSAttributedString.Key: Any])] {
    if sets.isEmpty { return [] }
    
    // Group overlapping ranges with same attributes
    var grouped: [NSRange: [NSAttributedString.Key: Any]] = [:]
    
    for (range, attrs) in sets {
      var merged = false
      for (existingRange, existingAttrs) in grouped {
        // Check if ranges overlap and attributes are compatible
        if NSIntersectionRange(range, existingRange).length > 0 {
          // Merge ranges
          let newStart = min(range.location, existingRange.location)
          let newEnd = max(NSMaxRange(range), NSMaxRange(existingRange))
          let mergedRange = NSRange(location: newStart, length: newEnd - newStart)
          
          // Merge attributes (last one wins for conflicts)
          var mergedAttrs = existingAttrs
          for (key, value) in attrs {
            mergedAttrs[key] = value
          }
          
          grouped.removeValue(forKey: existingRange)
          grouped[mergedRange] = mergedAttrs
          merged = true
          break
        }
      }
      
      if !merged {
        grouped[range] = attrs
      }
    }
    
    return Array(grouped)
  }
  
  // MARK: - Batch Range Cache Updates
  
  @MainActor
  private static func batchUpdateRangeCache(
    editor: Editor,
    pendingEditorState: EditorState,
    changes: [(nodeKey: NodeKey, part: NodePart, delta: Int)]
  ) {
    if changes.isEmpty { return }
    
    // Pre-allocate collections
    var nodeDeltas: [NodeKey: Int] = [:]
    nodeDeltas.reserveCapacity(changes.count)
    
    var parentDeltas: [NodeKey: Int] = [:]
    
    // Batch calculate deltas
    for (nodeKey, part, delta) in changes {
      guard let node = pendingEditorState.nodeMap[nodeKey] else { continue }
      
      // Update node's own cache
      if var item = editor.rangeCache[nodeKey] {
        switch part {
        case .text:
          item.textLength += delta
        case .preamble:
          item.preambleLength += delta
        case .postamble:
          item.postambleLength += delta
        }
        editor.rangeCache[nodeKey] = item
      }
      
      // Accumulate parent deltas for childrenLength updates
      for parent in node.getParents() {
        let parentKey = parent.getKey()
        parentDeltas[parentKey, default: 0] += delta
      }
      
      nodeDeltas[nodeKey, default: 0] += delta
    }
    
    // Batch apply parent updates (children length changes)
    for (parentKey, totalDelta) in parentDeltas {
      if var parentItem = editor.rangeCache[parentKey] {
        parentItem.childrenLength += totalDelta
        editor.rangeCache[parentKey] = parentItem
      }
    }
  }
  
  // MARK: - Batch Decorator Position Updates
  
  @MainActor
  private static func batchUpdateDecoratorPositions(editor: Editor) {
    guard let textStorage = editor.textStorage else { return }
    
    // Batch update all decorator positions at once
    var updates: [(NodeKey, Int)] = []
    updates.reserveCapacity(textStorage.decoratorPositionCache.count)
    
    for (key, _) in textStorage.decoratorPositionCache {
      if let newLocation = editor.rangeCache[key]?.location {
        updates.append((key, newLocation))
      }
    }
    
    // Apply all updates in single pass without animations
    UIView.performWithoutAnimation {
      for (key, location) in updates {
        textStorage.decoratorPositionCache[key] = location
      }
    }
  }
  
  // MARK: - Instruction application & coalescing
  @MainActor
  private static func applyInstructions(_ instructions: [Instruction], editor: Editor, fixAttributesEnabled: Bool = true) -> InstructionApplyStats {
    // Use modern optimizations if enabled
    if editor.featureFlags.useOptimizedReconciler && editor.featureFlags.useModernTextKitOptimizations {
      let stats = applyInstructionsWithModernBatching(instructions, editor: editor, fixAttributesEnabled: fixAttributesEnabled)
      if editor.featureFlags.verboseLogging {
        print("🔥 APPLY (modern): del=\(stats.deletes) ins=\(stats.inserts) set=\(stats.sets) fix=\(stats.fixes) dur=\(String(format: "%.2f", stats.duration*1000))ms")
      }
      return stats
    }
    
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
    // Apply deletes safely in descending order; clamp to current length to avoid out-of-bounds
    var currentLength = textStorage.length
    for r in deletesCoalesced where r.length > 0 {
      let safe = NSIntersectionRange(r, NSRange(location: 0, length: currentLength))
      if safe.length > 0 {
        textStorage.deleteCharacters(in: safe)
        modifiedRanges.append(safe)
        currentLength -= safe.length
      }
    }
    // Apply inserts; clamp location into [0, currentLength]
    for (loc, s) in insertsCoalesced where s.length > 0 {
      let safeLoc = max(0, min(loc, currentLength))
      textStorage.insert(s, at: safeLoc)
      modifiedRanges.append(NSRange(location: safeLoc, length: s.length))
      currentLength += s.length
    }
    // Apply attribute sets; intersect with current string length
    for (r, attrs) in sets {
      let safe = NSIntersectionRange(r, NSRange(location: 0, length: currentLength))
      if safe.length > 0 {
        textStorage.setAttributes(attrs, range: safe)
        modifiedRanges.append(safe)
      }
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
    if editor.featureFlags.verboseLogging {
      print("🔥 APPLY: del=\(deletesCoalesced.count) ins=\(insertsCoalesced.count) set=\(sets.count) fix=\(fixCount>0 ? 1:0) dur=\(String(format: "%.2f", applyDuration*1000))ms")
    }
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
    let __updateStart = CFAbsoluteTimeGetCurrent()
    defer {
      if editor.featureFlags.verboseLogging {
        let total = CFAbsoluteTimeGetCurrent() - __updateStart
        print("🔥 UPDATE: dirty=\(editor.dirtyNodes.count) type=\(editor.dirtyType) total=\(String(format: "%.2f", total*1000))ms")
      }
    }
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

    // Fresh-document fast hydration: build full string + cache in one pass
    if shouldHydrateFreshDocument(pendingState: pendingEditorState, editor: editor) {
      try hydrateFreshDocumentFully(pendingState: pendingEditorState, editor: editor)
      return
    }

    // Try optimized fast paths before falling back (even if fullReconcile)
    // Optional central aggregation of Fenwick deltas across paths
    var fenwickAggregatedDeltas: [NodeKey: Int] = [:]
    // Pre-compute part diffs (used by some paths and metrics)
    if editor.featureFlags.verboseLogging {
      let t0 = CFAbsoluteTimeGetCurrent()
      _ = computePartDiffs(editor: editor, prevState: currentEditorState, nextState: pendingEditorState)
      let dt = CFAbsoluteTimeGetCurrent() - t0
      print("🔥 PLAN-DIFF: computed in \(String(format: "%.2f", dt*1000))ms")
    } else {
      _ = computePartDiffs(editor: editor, prevState: currentEditorState, nextState: pendingEditorState)
    }
    // Structural insert fast path (before reorder)
    var didInsertFastPath = false
    if try fastPath_InsertBlock(
      currentEditorState: currentEditorState,
      pendingEditorState: pendingEditorState,
      editor: editor,
      shouldReconcileSelection: shouldReconcileSelection,
      fenwickAggregatedDeltas: &fenwickAggregatedDeltas
    ) {
      didInsertFastPath = true
      if editor.featureFlags.verboseLogging {
        print("🔥 INSERT-FAST: took insert-block path (fenwick=\(editor.featureFlags.useReconcilerInsertBlockFenwick))")
      }
    }
    if editor.dirtyType != .noDirtyNodes { editor.invalidateDFSOrderCache() }
    // If insert-block consumed and central aggregation collected deltas, apply them once
    if editor.featureFlags.useReconcilerFenwickDelta && editor.featureFlags.useReconcilerFenwickCentralAggregation && !fenwickAggregatedDeltas.isEmpty {
      let (order, positions) = fenwickOrderAndIndex(editor: editor)
      let ranges = fenwickAggregatedDeltas.map { (k, d) in (startKey: k, endKeyExclusive: Optional<NodeKey>.none, delta: d) }
      if editor.featureFlags.verboseLogging {
        let t0 = CFAbsoluteTimeGetCurrent()
        applyIncrementalLocationShifts(rangeCache: &editor.rangeCache, ranges: ranges, order: order, indexOf: positions)
        let dt = CFAbsoluteTimeGetCurrent() - t0
        print("🔥 RANGE-CACHE: fenwick-range-shifts count=\(ranges.count) dur=\(String(format: "%.2f", dt*1000))ms")
      } else {
        applyIncrementalLocationShifts(rangeCache: &editor.rangeCache, ranges: ranges, order: order, indexOf: positions)
      }
      fenwickAggregatedDeltas.removeAll(keepingCapacity: true)
    }

    // Early-out optimization: if only a simple insert was handled and no further dirty work remains, return.
    if didInsertFastPath && editor.dirtyNodes.isEmpty {
      if editor.featureFlags.verboseLogging {
        print("🔥 INSERT-FAST: early-out (no further dirty)")
      }
      return
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
    // Central aggregation: collect both text and pre/post instructions, then apply once
    if editor.featureFlags.useReconcilerFenwickDelta && editor.featureFlags.useReconcilerFenwickCentralAggregation {
      var aggregatedInstructions: [Instruction] = []
      var aggregatedAffected: Set<NodeKey> = []
      var aggregatedLengthChanges: [(nodeKey: NodeKey, part: NodePart, delta: Int)] = []

      if let plan = try plan_TextOnly_Multi(currentEditorState: currentEditorState, pendingEditorState: pendingEditorState, editor: editor) {
        aggregatedInstructions.append(contentsOf: plan.instructions)
        aggregatedAffected.formUnion(plan.affected)
        aggregatedLengthChanges.append(contentsOf: plan.lengthChanges)
      }
      if editor.featureFlags.useReconcilerPrePostAttributesOnly,
         let plan = try plan_PreamblePostambleOnly_Multi(currentEditorState: currentEditorState, pendingEditorState: pendingEditorState, editor: editor) {
        aggregatedInstructions.append(contentsOf: plan.instructions)
        aggregatedAffected.formUnion(plan.affected)
        aggregatedLengthChanges.append(contentsOf: plan.lengthChanges)
      }
      if !aggregatedInstructions.isEmpty {
        // Wrap in CATransaction when modern optimizations enabled
        if editor.featureFlags.useOptimizedReconciler && editor.featureFlags.useModernTextKitOptimizations {
          CATransaction.begin()
          CATransaction.setDisableActions(true)
        }
        
        let stats = applyInstructions(aggregatedInstructions, editor: editor)
        if !aggregatedLengthChanges.isEmpty {
          if editor.featureFlags.useModernTextKitOptimizations {
            // Use batch update when enabled
            batchUpdateRangeCache(editor: editor, pendingEditorState: pendingEditorState, changes: aggregatedLengthChanges)
          } else {
            let shifts = applyLengthDeltasBatch(editor: editor, changes: aggregatedLengthChanges)
            for (k, d) in shifts where d != 0 { fenwickAggregatedDeltas[k, default: 0] &+= d }
          }
        }

        editor.invalidateDFSOrderCache()
        if !fenwickAggregatedDeltas.isEmpty {
          let (order, positions) = fenwickOrderAndIndex(editor: editor)
          let ranges = fenwickAggregatedDeltas.map { (k, d) in (startKey: k, endKeyExclusive: Optional<NodeKey>.none, delta: d) }
          applyIncrementalLocationShifts(rangeCache: &editor.rangeCache, ranges: ranges, order: order, indexOf: positions)
          fenwickAggregatedDeltas.removeAll(keepingCapacity: true)
        }
        // Update decorator positions
        if editor.featureFlags.useModernTextKitOptimizations {
          batchUpdateDecoratorPositions(editor: editor)
        } else {
          if let ts = editor.textStorage {
            for (key, _) in ts.decoratorPositionCache {
              if let loc = editor.rangeCache[key]?.location { ts.decoratorPositionCache[key] = loc }
            }
          }
        }
        
        if editor.featureFlags.useOptimizedReconciler && editor.featureFlags.useModernTextKitOptimizations {
          CATransaction.commit()
        }
        // One-time block attribute pass over affected keys
        applyBlockAttributesPass(editor: editor, pendingEditorState: pendingEditorState, affectedKeys: aggregatedAffected, treatAllNodesAsDirty: false)
        // One-time selection reconcile
        let prevSelection = currentEditorState.selection
        let nextSelection = pendingEditorState.selection
        var selectionsAreDifferent = false
        if let nextSelection, let prevSelection { selectionsAreDifferent = !nextSelection.isSelection(prevSelection) }
        let needsUpdate = editor.dirtyType != .noDirtyNodes
        if shouldReconcileSelection && (needsUpdate || nextSelection == nil || selectionsAreDifferent) {
          try reconcileSelection(prevSelection: prevSelection, nextSelection: nextSelection, editor: editor)
        }
        if let metrics = editor.metricsContainer {
          let label: String = aggregatedLengthChanges.contains(where: { $0.part == .text }) && aggregatedLengthChanges.contains(where: { $0.part != .text }) ? "text+prepost-multi" : (aggregatedLengthChanges.contains(where: { $0.part == .text }) ? "text-only-multi" : "prepost-only-multi")
          let metric = ReconcilerMetric(duration: stats.duration, dirtyNodes: editor.dirtyNodes.count, rangesAdded: 0, rangesDeleted: 0, treatedAllNodesAsDirty: false, pathLabel: label, planningDuration: 0, applyDuration: stats.duration, deleteCount: 0, insertCount: 0, setAttributesCount: 0, fixAttributesCount: 1)
          metrics.record(.reconcilerRun(metric))
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
      editor.invalidateDFSOrderCache()
      // If central aggregation is enabled, apply aggregated rebuild now
      if editor.featureFlags.useReconcilerFenwickDelta && editor.featureFlags.useReconcilerFenwickCentralAggregation && !fenwickAggregatedDeltas.isEmpty {
        let (order, positions) = fenwickOrderAndIndex(editor: editor)
        let ranges = fenwickAggregatedDeltas.map { (k, d) in (startKey: k, endKeyExclusive: Optional<NodeKey>.none, delta: d) }
        applyIncrementalLocationShifts(rangeCache: &editor.rangeCache, ranges: ranges, order: order, indexOf: positions)
      }
      return
    }

    if editor.featureFlags.useReconcilerPrePostAttributesOnly,
       try fastPath_PreamblePostambleOnly(
      currentEditorState: currentEditorState,
      pendingEditorState: pendingEditorState,
      editor: editor,
      shouldReconcileSelection: shouldReconcileSelection,
      fenwickAggregatedDeltas: &fenwickAggregatedDeltas
    ) {
      editor.invalidateDFSOrderCache()
      if editor.featureFlags.useReconcilerFenwickDelta && editor.featureFlags.useReconcilerFenwickCentralAggregation && !fenwickAggregatedDeltas.isEmpty {
        let (order, positions) = fenwickOrderAndIndex(editor: editor)
        let ranges = fenwickAggregatedDeltas.map { (k, d) in (startKey: k, endKeyExclusive: Optional<NodeKey>.none, delta: d) }
        applyIncrementalLocationShifts(rangeCache: &editor.rangeCache, ranges: ranges, order: order, indexOf: positions)
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

  // MARK: - Fresh document hydration (one-pass build)
  @MainActor
  private static func shouldHydrateFreshDocument(pendingState: EditorState, editor: Editor) -> Bool {
    guard let ts = editor.textStorage else { return false }
    let storageEmpty = ts.length == 0
    guard storageEmpty else { return false }
    // Range cache has only root and it’s empty
    if editor.rangeCache.count == 1, let root = editor.rangeCache[kRootNodeKey] {
      if root.preambleLength == 0 && root.childrenLength == 0 && root.textLength == 0 && root.postambleLength == 0 {
        return true
      }
    }
    // Fallback: brand-new editor state (only root)
    return currentNodeCount(pendingState) <= 1
  }

  @MainActor
  private static func currentNodeCount(_ state: EditorState) -> Int { state.nodeMap.count }

  @MainActor
  internal static func hydrateFreshDocumentFully(pendingState: EditorState, editor: Editor) throws {
    guard let ts = editor.textStorage else { return }
    let prevMode = ts.mode
    ts.mode = .controllerMode
    ts.beginEditing()
    // Build full attributed content for root's children
    let theme = editor.getTheme()
    let built = NSMutableAttributedString()
    if let root = pendingState.getRootNode() {
      for child in root.getChildrenKeys() {
        built.append(buildAttributedSubtree(nodeKey: child, state: pendingState, theme: theme))
      }
    }
    // Replace
    ts.replaceCharacters(in: NSRange(location: 0, length: ts.length), with: built)
    ts.fixAttributes(in: NSRange(location: 0, length: built.length))
    ts.endEditing()
    ts.mode = prevMode

    // Recompute cache from root start 0
    _ = recomputeRangeCacheSubtree(nodeKey: kRootNodeKey, state: pendingState, startLocation: 0, editor: editor)

    // Apply block-level attributes for all nodes once
    applyBlockAttributesPass(editor: editor, pendingEditorState: pendingState, affectedKeys: nil, treatAllNodesAsDirty: true)

    // Decorator positions align with new locations
    for (key, _) in ts.decoratorPositionCache {
      if let loc = editor.rangeCache[key]?.location { ts.decoratorPositionCache[key] = loc }
    }
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
    // Capture prior state to detect no-op string rebuilds (e.g., decorator size-only changes)
    let prevString = textStorage.string
    let prevDecoratorPositions = textStorage.decoratorPositionCache
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

    // If the rebuilt string is identical, preserve existing decorator positions.
    // Size-only updates must not perturb position cache.
    if textStorage.string == prevString {
      textStorage.decoratorPositionCache = prevDecoratorPositions
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

    if editor.featureFlags.useReconcilerShadowCompare { print("🔥 OPTIMIZED RECONCILER: optimized slow path applied (full rebuild)") }
    if let metrics = editor.metricsContainer {
      // Approximate wall time for slow path as pure apply time for the full replace
      // (We don't separate planning here.)
      // Note: applyDuration was measured above implicitly by the editing block; recompute here conservatively
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
          let t0 = CFAbsoluteTimeGetCurrent()
          textStorage.beginEditing()
          textStorage.setAttributes(attributes, range: textRange)
          textStorage.fixAttributes(in: textRange)
          textStorage.endEditing()
          textStorage.mode = previousMode
          let applyDur = CFAbsoluteTimeGetCurrent() - t0

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
              duration: applyDur, dirtyNodes: editor.dirtyNodes.count, rangesAdded: 0, rangesDeleted: 0,
              treatedAllNodesAsDirty: false, pathLabel: "attr-only", planningDuration: 0,
              applyDuration: applyDur, deleteCount: 0, insertCount: 0, setAttributesCount: 1, fixAttributesCount: 1)
            metrics.record(.reconcilerRun(metric))
          }
          if editor.featureFlags.useReconcilerShadowCompare { print("🔥 OPTIMIZED RECONCILER: attribute-only fast path applied") }
          return true
        }
      }
      // Content changed but length kept → try pre/post part deltas for element siblings, else fallback
      return false
    }

    // Minimal replace algorithm (LCP/LCS): replace only the changed span
    guard let textStorage = editor.textStorage else { return false }
    let textStart = prevRange.location + prevRange.preambleLength + prevRange.childrenLength
    let textRange = NSRange(location: textStart, length: oldTextLen)
    guard textRange.upperBound <= textStorage.length else { return false }

    let oldStr = (textStorage.attributedSubstring(from: textRange).string as NSString)
    let newStr = (newText as NSString)
    let oldLen = oldStr.length
    let newLen = newStr.length
    let maxPref = min(oldLen, newLen)
    var lcp = 0
    while lcp < maxPref && oldStr.character(at: lcp) == newStr.character(at: lcp) { lcp += 1 }
    let oldRem = oldLen - lcp
    let newRem = newLen - lcp
    let maxSuf = min(oldRem, newRem)
    var lcs = 0
    while lcs < maxSuf && oldStr.character(at: oldLen - 1 - lcs) == newStr.character(at: newLen - 1 - lcs) { lcs += 1 }

    let changedOldLen = max(0, oldRem - lcs)
    let changedNewLen = max(0, newRem - lcs)
    let replaceLoc = textStart + lcp
    let replaceRange = NSRange(location: replaceLoc, length: changedOldLen)

    // Build styled replacement for changed segment
    let theme = editor.getTheme()
    let state = pendingEditorState
    let newSegment = changedNewLen > 0 ? newStr.substring(with: NSRange(location: lcp, length: changedNewLen)) : ""
    let styled = AttributeUtils.attributedStringByAddingStyles(NSAttributedString(string: newSegment), from: nextNode, state: state, theme: theme)

    let prevModeTS = textStorage.mode
    textStorage.mode = .controllerMode
    let t0 = CFAbsoluteTimeGetCurrent()
    textStorage.beginEditing()
    textStorage.replaceCharacters(in: replaceRange, with: styled)
    let fixLen = max(changedOldLen, styled.length)
    textStorage.fixAttributes(in: NSRange(location: replaceLoc, length: fixLen))
    textStorage.endEditing()
    textStorage.mode = prevModeTS
    let applyDur = CFAbsoluteTimeGetCurrent() - t0
    if editor.featureFlags.verboseLogging { print("🔥 TEXT-MIN-REPLACE: dur=\(String(format: "%.2f", applyDur*1000))ms") }

    // Update cache lengths and ancestors
    let delta = newLen - oldLen
    if var item = editor.rangeCache[dirtyKey] { item.textLength = newLen; editor.rangeCache[dirtyKey] = item }
    if delta != 0, let node = pendingEditorState.nodeMap[dirtyKey] {
      for p in node.getParents() { if var it = editor.rangeCache[p.getKey()] { it.childrenLength += delta; editor.rangeCache[p.getKey()] = it } }
    }

    // Location shifts
    if delta != 0 {
      if editor.featureFlags.useReconcilerFenwickDelta {
        let (order, positions) = fenwickOrderAndIndex(editor: editor)
        let ranges = [(startKey: dirtyKey, endKeyExclusive: Optional<NodeKey>.none, delta: delta)]
        if editor.featureFlags.verboseLogging {
          let t0 = CFAbsoluteTimeGetCurrent();
          applyIncrementalLocationShifts(rangeCache: &editor.rangeCache, ranges: ranges, order: order, indexOf: positions)
          let dt = CFAbsoluteTimeGetCurrent() - t0
          print("🔥 RANGE-CACHE: single-range-shift dur=\(String(format: "%.2f", dt*1000))ms delta=\(delta)")
        } else {
          applyIncrementalLocationShifts(rangeCache: &editor.rangeCache, ranges: ranges, order: order, indexOf: positions)
        }
      } else {
        if editor.featureFlags.verboseLogging {
          let t0 = CFAbsoluteTimeGetCurrent(); _ = applyLengthDeltasBatch(editor: editor, changes: [(dirtyKey, .text, delta)])
          let dt = CFAbsoluteTimeGetCurrent() - t0
          print("🔥 RANGE-CACHE: length-delta (single) dur=\(String(format: "%.2f", dt*1000))ms delta=\(delta)")
        } else {
          _ = applyLengthDeltasBatch(editor: editor, changes: [(dirtyKey, .text, delta)])
        }
      }
    }

    // Update decorator positions
    if let ts = editor.textStorage {
      for (key, _) in ts.decoratorPositionCache { if let loc = editor.rangeCache[key]?.location { ts.decoratorPositionCache[key] = loc } }
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

    if let metrics = editor.metricsContainer {
      let metric = ReconcilerMetric(
        duration: applyDur, dirtyNodes: editor.dirtyNodes.count, rangesAdded: 0, rangesDeleted: 0,
        treatedAllNodesAsDirty: false, pathLabel: "text-only-min-replace", planningDuration: 0,
        applyDuration: applyDur, deleteCount: 0, insertCount: 0, setAttributesCount: 0, fixAttributesCount: 1)
      metrics.record(.reconcilerRun(metric))
    }
    if editor.featureFlags.useReconcilerShadowCompare { print("🔥 OPTIMIZED RECONCILER: text-only minimal replace applied (Δ=\(delta))") }
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
    if editor.featureFlags.useReconcilerInsertBlockFenwick && insertIndex > 0 {
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

    var applyDuration: TimeInterval = 0
    if !editor.featureFlags.useReconcilerInsertBlockFenwick {
      guard let textStorage = editor.textStorage else { return false }
      let previousMode = textStorage.mode
      textStorage.mode = .controllerMode
      let t0 = CFAbsoluteTimeGetCurrent()
      textStorage.beginEditing()
      let theme2 = editor.getTheme()
      let builtParentChildren = NSMutableAttributedString()
      for child in nextChildren { builtParentChildren.append(buildAttributedSubtree(nodeKey: child, state: pendingEditorState, theme: theme2)) }
      let parentChildrenStart = parentPrevRange.location + parentPrevRange.preambleLength
      let parentChildrenRange = NSRange(location: parentChildrenStart, length: parentPrevRange.childrenLength)
      textStorage.replaceCharacters(in: parentChildrenRange, with: builtParentChildren)
      textStorage.fixAttributes(in: NSRange(location: parentChildrenStart, length: builtParentChildren.length))
      textStorage.endEditing()
      textStorage.mode = previousMode
      applyDuration = CFAbsoluteTimeGetCurrent() - t0
      _ = recomputeRangeCacheSubtree(nodeKey: parentKey, state: pendingEditorState, startLocation: parentPrevRange.location, editor: editor)
      reconcileDecoratorOpsForSubtree(ancestorKey: parentKey, prevState: currentEditorState, nextState: pendingEditorState, editor: editor)
    } else {
      // Fenwick variant: apply delete/insert instructions at computed locations
      let stats = applyInstructions(instructions, editor: editor, fixAttributesEnabled: false)
      applyDuration = stats.duration
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
        duration: applyDuration, dirtyNodes: editor.dirtyNodes.count, rangesAdded: 0, rangesDeleted: 0,
        treatedAllNodesAsDirty: false, pathLabel: "insert-block", planningDuration: 0, applyDuration: applyDuration)
      metrics.record(.reconcilerRun(metric))
    }
    // Assign a stable nodeIndex for future Fenwick-backed locations if missing.
    if var item = editor.rangeCache[addedKey] {
      if item.nodeIndex == 0 {
        item.nodeIndex = editor.nextFenwickNodeIndex
        editor.nextFenwickNodeIndex += 1
        editor.rangeCache[addedKey] = item
      }
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
    var lengthChanges: [(nodeKey: NodeKey, part: NodePart, delta: Int)] = []
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
      // Defer cache updates to a single batched pass
      lengthChanges.append((nodeKey: key, part: .text, delta: delta))
      affected.insert(key)
      for p in next.getParents() { affected.insert(p.getKey()) }
    }
    if instructions.isEmpty { return false }
    let stats = applyInstructions(instructions, editor: editor)

    // Single batched cache/ancestor updates; aggregate Fenwick start shifts
    if !lengthChanges.isEmpty {
      if editor.featureFlags.verboseLogging {
        let t0 = CFAbsoluteTimeGetCurrent()
        let shifts = applyLengthDeltasBatch(editor: editor, changes: lengthChanges)
        let dt = CFAbsoluteTimeGetCurrent() - t0
        let nonZero = shifts.values.filter { $0 != 0 }.count
        print("🔥 RANGE-CACHE: length-deltas changes=\(lengthChanges.count) nonzero-starts=\(nonZero) dur=\(String(format: "%.2f", dt*1000))ms")
        for (k, d) in shifts where d != 0 { fenwickAggregatedDeltas[k, default: 0] &+= d }
      } else {
        let shifts = applyLengthDeltasBatch(editor: editor, changes: lengthChanges)
        for (k, d) in shifts where d != 0 { fenwickAggregatedDeltas[k, default: 0] &+= d }
      }
    }

    // Update decorator positions after location rebuild at end (done in caller)
    // Apply block-level attributes scoped to affected nodes
    applyBlockAttributesPass(editor: editor, pendingEditorState: pendingEditorState, affectedKeys: affected, treatAllNodesAsDirty: false)

    if let metrics = editor.metricsContainer {
      let metric = ReconcilerMetric(duration: stats.duration, dirtyNodes: editor.dirtyNodes.count, rangesAdded: 0, rangesDeleted: 0, treatedAllNodesAsDirty: false, pathLabel: "text-only-multi", planningDuration: 0, applyDuration: stats.duration, deleteCount: 0, insertCount: 0, setAttributesCount: 0, fixAttributesCount: 1)
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
    if editor.featureFlags.verboseLogging {
      print("🔥 PREPOST-MULTI: candidates=\(targets.count) dirty=\(editor.dirtyNodes.count)")
    }
    var instructions: [Instruction] = []
    var affected: Set<NodeKey> = []
    var lengthChanges: [(nodeKey: NodeKey, part: NodePart, delta: Int)] = []
    let theme = editor.getTheme()
    for key in targets {
      guard let next = pendingEditorState.nodeMap[key], let prevRange = editor.rangeCache[key] else { continue }
      let np = next.getPreamble(); let npo = next.getPostamble()
      let nextPreLen = np.lengthAsNSString(); let nextPostLen = npo.lengthAsNSString()
      if nextPostLen > 0 {
        let postLoc = prevRange.location + prevRange.preambleLength + prevRange.childrenLength + prevRange.textLength
        let rng = NSRange(location: postLoc, length: nextPostLen)
        let postAttr = AttributeUtils.attributedStringByAddingStyles(NSAttributedString(string: npo), from: next, state: pendingEditorState, theme: theme)
        let attrs = postAttr.attributes(at: 0, effectiveRange: nil)
        instructions.append(.setAttributes(range: rng, attributes: attrs))
      }
      if nextPreLen > 0 {
        let preLoc = prevRange.location
        let rng = NSRange(location: preLoc, length: nextPreLen)
        let preAttr = AttributeUtils.attributedStringByAddingStyles(NSAttributedString(string: np), from: next, state: pendingEditorState, theme: theme)
        let attrs = preAttr.attributes(at: 0, effectiveRange: nil)
        instructions.append(.setAttributes(range: rng, attributes: attrs))
      }
      affected.insert(key)
    }
    if instructions.isEmpty { return false }
    if editor.featureFlags.verboseLogging {
      let setCount = instructions.reduce(0) { acc, inst in if case .setAttributes = inst { return acc + 1 } else { return acc } }
      print("🔥 PREPOST-MULTI: setOps=\(setCount) (pre/post attrs-only)")
    }
    let stats = applyInstructions(instructions, editor: editor)
    // No cache/ancestor shifts or block attributes in attributes-only variant
    if let metrics = editor.metricsContainer {
      let metric = ReconcilerMetric(duration: stats.duration, dirtyNodes: editor.dirtyNodes.count, rangesAdded: 0, rangesDeleted: 0, treatedAllNodesAsDirty: false, pathLabel: "prepost-attrs-only-multi", planningDuration: 0, applyDuration: stats.duration, deleteCount: 0, insertCount: 0, setAttributesCount: 0, fixAttributesCount: 1)
      metrics.record(.reconcilerRun(metric))
    }
    if editor.featureFlags.verboseLogging {
      print("🔥 PREPOST-MULTI: applied in \(String(format: "%.2f", stats.duration*1000))ms")
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

    // Decide whether to do minimal moves or full region rebuild.
    // For stability in suite-wide runs, prefer the simple region rebuild.
    let movedCount = nextChildren.filter { !stableSet.contains($0) }.count
    let preferMinimalMoves = false
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
          duration: stats.duration, dirtyNodes: editor.dirtyNodes.count, rangesAdded: 0, rangesDeleted: 0,
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
      let t0 = CFAbsoluteTimeGetCurrent()
      textStorage.beginEditing()
      textStorage.replaceCharacters(in: childrenRange, with: built)
      textStorage.fixAttributes(in: NSRange(location: childrenRange.location, length: built.length))
      textStorage.endEditing()
      textStorage.mode = previousMode
      if let metrics = editor.metricsContainer {
        let applyDur = CFAbsoluteTimeGetCurrent() - t0
        let metric = ReconcilerMetric(
          duration: applyDur, dirtyNodes: editor.dirtyNodes.count, rangesAdded: 0, rangesDeleted: 0,
          treatedAllNodesAsDirty: false, pathLabel: "reorder-rebuild", planningDuration: 0, applyDuration: applyDur, movedChildren: movedCount)
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
    if editor.featureFlags.useReconcilerInsertBlockFenwick {
      var rangeShifts: [(NodeKey, NodeKey?, Int)] = []
    let (orderedKeys, indexOf) = fenwickOrderAndIndex(editor: editor)
      for k in nextChildrenOrder {
        guard let oldStart = childOldStart[k], let newStart = childNewStart[k] else { continue }
        let deltaShift = newStart - oldStart
        if deltaShift == 0 { continue }
        let subKeys = subtreeKeysDFS(rootKey: k, state: pendingEditorState)
        var maxIdx = 0
        for sk in subKeys { if let idx = indexOf[sk], idx > maxIdx { maxIdx = idx } }
        let endExclusive: NodeKey? = (maxIdx < orderedKeys.count) ? orderedKeys[maxIdx] : nil
        rangeShifts.append((k, endExclusive, deltaShift))
      }
      if !rangeShifts.isEmpty {
        editor.rangeCache = rebuildLocationsWithFenwickRanges(
          prev: editor.rangeCache, ranges: rangeShifts, order: orderedKeys, indexOf: indexOf)
      }
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
    if item.nodeIndex == 0 { item.nodeIndex = editor.nextFenwickNodeIndex; editor.nextFenwickNodeIndex += 1 }
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
    let __t0 = CFAbsoluteTimeGetCurrent()
    guard let nextSelection else {
      if let prevSelection, !prevSelection.dirty {
        if editor.featureFlags.verboseLogging {
          let dt = CFAbsoluteTimeGetCurrent() - __t0
          print("🔥 SELECTION: no-op (prev clean, next nil) dur=\(String(format: "%.2f", dt*1000))ms")
        }
        return
      }
      editor.frontend?.resetSelectedRange()
      if editor.featureFlags.verboseLogging {
        let dt = CFAbsoluteTimeGetCurrent() - __t0
        print("🔥 SELECTION: resetNative dur=\(String(format: "%.2f", dt*1000))ms")
      }
      return
    }
    try editor.frontend?.updateNativeSelection(from: nextSelection)
    if editor.featureFlags.verboseLogging {
      let dt = CFAbsoluteTimeGetCurrent() - __t0
      print("🔥 SELECTION: updateNative dur=\(String(format: "%.2f", dt*1000))ms")
    }
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

    // Ensure children/text lengths unchanged (attributes-only path must not change lengths)
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
    // Attributes-only: strictly no length changes (safer; avoids re-dirty loops)
    guard nextPreLen == prevRange.preambleLength && nextPostLen == prevRange.postambleLength else { return false }
    if nextPreLen == 0 && nextPostLen == 0 { return false }

    let theme = editor.getTheme()
    var applied: [Instruction] = []
    if editor.featureFlags.verboseLogging {
      print("🔥 PREPOST-SINGLE: key=\(dirtyKey) preLen=\(nextPreLen) postLen=\(nextPostLen)")
    }

    // Postamble attributes only (higher location first)
    if nextPostLen > 0 {
      let postLoc = prevRange.location + prevRange.preambleLength + prevRange.childrenLength + prevRange.textLength
      let rng = NSRange(location: postLoc, length: nextPostLen)
      let postAttr = AttributeUtils.attributedStringByAddingStyles(
        NSAttributedString(string: nextNode.getPostamble()), from: nextNode, state: pendingEditorState,
        theme: theme)
      let attrs = postAttr.attributes(at: 0, effectiveRange: nil)
      applied.append(.setAttributes(range: rng, attributes: attrs))
    }

    // Apply preamble second (lower location)
    // Preamble attributes only
    if nextPreLen > 0 {
      let preLoc = prevRange.location
      let rng = NSRange(location: preLoc, length: nextPreLen)
      let preAttr = AttributeUtils.attributedStringByAddingStyles(
        NSAttributedString(string: nextNode.getPreamble()), from: nextNode, state: pendingEditorState,
        theme: theme)
      let attrs = preAttr.attributes(at: 0, effectiveRange: nil)
      applied.append(.setAttributes(range: rng, attributes: attrs))
    }
    let stats = applyInstructions(applied, editor: editor)
    if editor.featureFlags.verboseLogging {
      print("🔥 PREPOST-SINGLE: applied in \(String(format: "%.2f", stats.duration*1000))ms")
    }

    // Update decorators positions
    if let ts = editor.textStorage {
      for (key, _) in ts.decoratorPositionCache {
        if let loc = editor.rangeCache[key]?.location {
          ts.decoratorPositionCache[key] = loc
        }
      }
    }

    // No block-level attribute pass for attributes-only; keep changes local

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
        duration: stats.duration, dirtyNodes: editor.dirtyNodes.count, rangesAdded: 0, rangesDeleted: 0,
        treatedAllNodesAsDirty: false, pathLabel: "prepost-attrs-only", planningDuration: 0,
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
    let __t0 = CFAbsoluteTimeGetCurrent()
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
    if editor.featureFlags.verboseLogging {
      let dt = CFAbsoluteTimeGetCurrent() - __t0
      print("🔥 BLOCK-ATTR: nodes=\(nodesToApply.count) dur=\(String(format: "%.2f", dt*1000))ms allDirty=\(treatAllNodesAsDirty)")
    }
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
