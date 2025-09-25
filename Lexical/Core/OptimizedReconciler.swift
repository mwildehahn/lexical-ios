/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Main entry point for optimized delta-based reconciliation
@MainActor
internal enum OptimizedReconciler {

  /// Performs optimized reconciliation
  static func reconcile(
    currentEditorState: EditorState,
    pendingEditorState: EditorState,
    editor: Editor,
    shouldReconcileSelection: Bool,
    markedTextOperation: MarkedTextOperation?
  ) throws {

    // Marked text operations are supported; special handling occurs after delta application.

    guard let textStorage = editor.textStorage else {
      throw LexicalError.invariantViolation("TextStorage not available")
    }

    // Track metrics for this reconciliation
    let startTime = Date()
    let nodeCount = pendingEditorState.nodeMap.count
    let textStorageLength = textStorage.length

    // Initialize components
    let deltaGenerator = DeltaGenerator(editor: editor)
    let deltaApplier = TextStorageDeltaApplier(editor: editor, fenwickTree: editor.fenwickTree)

    // Generate deltas from the state differences
    let deltaBatch = try deltaGenerator.generateDeltaBatch(
      from: currentEditorState,
      to: pendingEditorState,
      rangeCache: editor.rangeCache,
      dirtyNodes: editor.dirtyNodes
    )

    // Assign stable Fenwick indices for newly inserted nodes in string order BEFORE applying deltas.
    // This guarantees that Fenwick indices increase with document position, so
    // locationFromFenwick() yields correct absolute locations regardless of delta
    // application order (reverse-sorted for non-fresh batches).
    do {
      // Collect inserted nodes and their intended start locations
      var inserted: [(key: NodeKey, location: Int)] = []
      for d in deltaBatch.deltas {
        if case let .nodeInsertion(nodeKey, _, location) = d.type {
          inserted.append((nodeKey, location))
        }
      }
      if !inserted.isEmpty {
        // Helper: ancestor check in pending state
        func isAncestor(_ a: NodeKey, of b: NodeKey) -> Bool {
          var cur: NodeKey? = b
          while let k = cur, k != kRootNodeKey {
            if k == a { return true }
            guard let n = pendingEditorState.nodeMap[k] else { break }
            cur = n.parent
          }
          return false
        }

        // Sort order depends on debug mode:
        // - Default (full suite expectations): ancestor-first, then by ascending location.
        // - Parity diagnostics (selectionParityDebug=true): descendant-first to aid postamble-before-child analyses.
        inserted.sort { lhs, rhs in
          let l = lhs.key, r = rhs.key
          if editor.featureFlags.selectionParityDebug {
            if isAncestor(l, of: r) { return false }
            if isAncestor(r, of: l) { return true }
          } else {
            if isAncestor(l, of: r) { return true }
            if isAncestor(r, of: l) { return false }
          }
          if lhs.location != rhs.location { return lhs.location < rhs.location }
          return l < r
        }
        if editor.featureFlags.diagnostics.verboseLogs {
          print("🔥 OPT RECON: inserted order=\(inserted)")
        }
        for (key, _) in inserted {
          if editor.fenwickIndexMap[key] == nil {
            let idx = editor.nextFenwickIndex
            editor.nextFenwickIndex += 1
            editor.fenwickIndexMap[key] = idx
            _ = editor.fenwickTree.ensureCapacity(for: idx)
          }
        }
      }
    }

    // Log delta count for debugging
    editor.log(.reconciler, .message, "Generated \(deltaBatch.deltas.count) deltas")

    // Debug: Log what deltas we actually generated
    for (index, delta) in deltaBatch.deltas.enumerated() {
      switch delta.type {
      case .nodeInsertion(let nodeKey, let insertionData, let location):
        if editor.featureFlags.diagnostics.verboseLogs {
          print("🔥 DELTA GEN: [\(index)] INSERT key=\(nodeKey) loc=\(location) pre=\(insertionData.preamble.length) tx=\(insertionData.content.length) post=\(insertionData.postamble.length)")
        }
      case .textUpdate(let nodeKey, let newText, let range):
        if editor.featureFlags.diagnostics.verboseLogs {
          print("🔥 DELTA GEN: [\(index)] UPDATE key=\(nodeKey) range=\(NSStringFromRange(range)) new='\(String(newText.prefix(20)))'")
        }
      case .nodeDeletion(let nodeKey, let range):
        if editor.featureFlags.diagnostics.verboseLogs {
          print("🔥 DELTA GEN: [\(index)] DELETE key=\(nodeKey) range=\(NSStringFromRange(range))")
        }
      case .attributeChange(let nodeKey, _, let range):
        if editor.featureFlags.diagnostics.verboseLogs {
          print("🔥 DELTA GEN: [\(index)] ATTR key=\(nodeKey) range=\(NSStringFromRange(range))")
        }
      }
    }

    if editor.featureFlags.diagnostics.verboseLogs {
      print("🔥 OPTIMIZED RECONCILER: textStorage length before apply: \(textStorage.length)")
    }

    let previousMode = textStorage.mode
    textStorage.mode = .controllerMode
    textStorage.beginEditing()
    defer {
      textStorage.endEditing()
      textStorage.mode = previousMode
    }

    // Capture pre-apply decorator positions (string locations) for movement detection
    let oldDecoratorPositions: [NodeKey: Int] = {
      var map: [NodeKey: Int] = [:]
      for (key, node) in currentEditorState.nodeMap where node is DecoratorNode {
        if let cacheItem = editor.rangeCache[key] {
          map[key] = cacheItem.locationFromFenwick(using: editor.fenwickTree)
        }
      }
      return map
    }()

    // Apply deltas
    let applicationResult = deltaApplier.applyDeltaBatch(deltaBatch, to: textStorage)

    if editor.featureFlags.diagnostics.verboseLogs {
      print("🔥 OPTIMIZED RECONCILER: textStorage length after apply: \(textStorage.length)")
    }

    switch applicationResult {
    case .success(let appliedDeltas, let fenwickUpdates):
      if editor.featureFlags.diagnostics.verboseLogs {
        print("🔥 OPTIMIZED RECONCILER: delta application success (applied=\(appliedDeltas), fenwick=\(fenwickUpdates))")
      }
      // Update range cache incrementally
      let cacheUpdater = IncrementalRangeCacheUpdater(editor: editor, fenwickTree: editor.fenwickTree)
      try cacheUpdater.updateRangeCache(
        &editor.rangeCache,
        basedOn: deltaBatch.deltas
      )

      // Apply block-level attributes (parity with legacy reconciler)
      if let textStorage = editor.textStorage {
        applyBlockLevelAttributes(
          editor: editor,
          pendingState: pendingEditorState,
          dirtyNodes: editor.dirtyNodes,
          textStorage: textStorage
        )
      }

      // Prune stale range cache entries for nodes that no longer exist in pending state
      do {
        let currentKeys = Set(currentEditorState.nodeMap.keys)
        let pendingKeys = Set(pendingEditorState.nodeMap.keys)
        let removedKeys = currentKeys.subtracting(pendingKeys)
        if !removedKeys.isEmpty { for k in removedKeys { editor.rangeCache.removeValue(forKey: k) } }
        // Also prune keys that exist but are detached in pending state
        var toPrune: [NodeKey] = []
        for (k, _) in editor.rangeCache {
          if pendingEditorState.nodeMap[k] != nil && !isAttachedInState(k, state: pendingEditorState) {
            toPrune.append(k)
          }
        }
        for k in toPrune { editor.rangeCache.removeValue(forKey: k) }
      }

      // Update decorator lifecycle and position cache (parity with legacy: create/decorate/remove + moved)
      updateDecoratorLifecycle(
        editor: editor,
        currentState: currentEditorState,
        pendingState: pendingEditorState,
        oldPositions: oldDecoratorPositions,
        appliedDeltas: deltaBatch.deltas
      )
      updateDecoratorPositions(editor: editor, pendingState: pendingEditorState)

      // Handle marked text (IME/composition) if requested
      if let op = markedTextOperation, op.createMarkedText, let frontend = editor.frontend, let textStorage = editor.textStorage {
        let length = op.markedTextString.lengthAsNSString()
        // Find starting Point using updated range cache
        let startPoint = try? pointAtStringLocation(
          op.selectionRangeToReplace.location,
          searchDirection: .forward,
          rangeCache: editor.rangeCache
        )

        if let startPoint {
          let endPoint = Point(key: startPoint.key, offset: startPoint.offset + length, type: .text)
          let selection = RangeSelection(anchor: startPoint, focus: endPoint, format: TextFormat())
          // Update native selection to cover the marked text region
          try frontend.updateNativeSelection(from: selection)
          // Resolve absolute range from selection to fetch attributed substring with styles
          let nativeSel = try createNativeSelection(from: selection, editor: editor)
          if let absRange = nativeSel.range {
            let safeLen = min(length, max(0, textStorage.length - absRange.location))
            let attributedSubstring = textStorage.attributedSubstring(
              from: NSRange(location: absRange.location, length: safeLen)
            )
            // Tell the text view to convert this inserted text into a marked-text session
            frontend.setMarkedTextFromReconciler(attributedSubstring, selectedRange: op.markedTextInternalSelection)
            // Skip any further selection reconciliation like legacy does
            editor.log(.reconciler, .message, "Handled marked text via optimized reconciler")
          } else {
            editor.log(.reconciler, .warning, "Native selection did not produce a numeric range; skipping marked-text handling")
          }
        } else {
          editor.log(.reconciler, .warning, "Failed to resolve startPoint for marked text; skipping marked-text handling")
        }
      }

      // Optional metrics snapshot dump for Playground debugging
      if editor.featureFlags.reconcilerMetrics, let mc = editor.metricsContainer {
        let snap = mc.snapshot
        print("🔥 METRICS SNAPSHOT: \(snap)")
      }

      // Record metrics if enabled
      if editor.featureFlags.reconcilerMetrics {
        recordOptimizedReconciliationMetrics(
          editor: editor,
          appliedDeltas: appliedDeltas,
          fenwickUpdates: fenwickUpdates,
          startTime: startTime,
          nodeCount: nodeCount,
          textStorageLength: textStorageLength
        )
      }

      editor.log(.reconciler, .message, "Optimized reconciliation successful: \(appliedDeltas) deltas applied")

      // Optional invariants validation for debug builds
      if editor.featureFlags.reconcilerSanityCheck {
        let report = validateEditorInvariants(editor: editor)
        if !report.isClean {
          for issue in report.issues {
            editor.log(.reconciler, .warning, "Invariant failed: \(issue)")
          }
        } else {
          editor.log(.reconciler, .verbose, "Invariants OK")
        }
      }

    case .partialSuccess(let appliedDeltas, let failedDeltas, let reason):
      // Log but continue - we applied what we could
      editor.log(.reconciler, .warning, "Partial delta application: \(appliedDeltas) applied, \(failedDeltas.count) failed: \(reason)")
      if editor.featureFlags.diagnostics.verboseLogs {
        print("🔥 OPTIMIZED RECONCILER: delta application partial (applied=\(appliedDeltas), failed=\(failedDeltas.count)) reason=\(reason)")
      }

    case .failure(let reason):
      // This is a real failure - throw an error
      throw LexicalError.invariantViolation("Delta application failed: \(reason)")
    }
  }

  /// Mirror legacy's block-level attributes pass
  private static func applyBlockLevelAttributes(
    editor: Editor,
    pendingState: EditorState,
    dirtyNodes: DirtyNodeMap,
    textStorage: TextStorage
  ) {
    let lastDescendentAttributes = getRoot()?.getLastChild()?.getAttributedStringAttributes(theme: editor.getTheme())

    var nodesToApply: Set<NodeKey> = []
    for (nodeKey, _) in dirtyNodes { nodesToApply.insert(nodeKey) }
    // Also include parents of dirty nodes (attributes can affect paragraph containers)
    for (nodeKey, _) in dirtyNodes {
      if let node = pendingState.nodeMap[nodeKey] { for p in node.getParentKeys() { nodesToApply.insert(p) } }
    }

    let rangeCache = editor.rangeCache
    for key in nodesToApply {
      guard let node = pendingState.nodeMap[key], node.isAttached(), let cacheItem = rangeCache[key] else { continue }
      if let attrs = node.getBlockLevelAttributes(theme: editor.getTheme()) {
        AttributeUtils.applyBlockLevelAttributes(
          attrs,
          cacheItem: cacheItem,
          textStorage: textStorage,
          nodeKey: key,
          lastDescendentAttributes: lastDescendentAttributes ?? [:],
          fenwickTree: editor.fenwickTree
        )
      }
    }
  }

  /// Minimal parity for decorator positioning: update TextStorage.decoratorPositionCache
  private static func updateDecoratorPositions(
    editor: Editor,
    pendingState: EditorState
  ) {
    guard let textStorage = editor.textStorage else { return }
    var newCache: [NodeKey: Int] = [:]

    for (key, node) in pendingState.nodeMap {
      if node is DecoratorNode, isAttachedInState(key, state: pendingState), let cacheItem = editor.rangeCache[key] {
        let loc = cacheItem.locationFromFenwick(using: editor.fenwickTree)
        newCache[key] = loc
      }
    }

    textStorage.decoratorPositionCache = newCache
  }

  /// Decorator lifecycle parity: create/decorate/remove and reposition
  /// - We mark new decorators as .needsCreation
  /// - We mark staying decorators as .needsDecorating(view) if they are dirty or moved
  /// - We remove deleted decorators and clear caches
  private static func updateDecoratorLifecycle(
    editor: Editor,
    currentState: EditorState,
    pendingState: EditorState,
    oldPositions: [NodeKey: Int],
    appliedDeltas: [ReconcilerDelta]
  ) {
    guard let textStorage = editor.textStorage else { return }

    // Collect decorator keys in each state
    let currentDecorators: Set<NodeKey> = Set(
      currentState.nodeMap.compactMap { (k, v) in v is DecoratorNode ? k : nil }
    )
    let pendingDecorators: Set<NodeKey> = Set(
      pendingState.nodeMap.compactMap { (k, v) in v is DecoratorNode ? k : nil }
    )

    // Consider a decorator removed if it either no longer exists in pending state OR exists but is detached (GC happens later)
    var removed = Set<NodeKey>()
    for key in currentDecorators {
      if let _ = pendingState.nodeMap[key] {
        if !isAttachedInState(key, state: pendingState) { removed.insert(key) }
      } else {
        removed.insert(key)
      }
    }
    let added = pendingDecorators.subtracting(currentDecorators)
    var staying = currentDecorators.intersection(pendingDecorators)
    // Exclude detached/deleted keys from staying
    staying.subtract(removed)

    // Compute new positions after delta application and cache update
    var newPositions: [NodeKey: Int] = [:]
    for key in pendingDecorators where isAttachedInState(key, state: pendingState) {
      if let cacheItem = editor.rangeCache[key] {
        newPositions[key] = cacheItem.locationFromFenwick(using: editor.fenwickTree)
      }
    }
    
    // Detect movement of decorators present in both states
    var moved: Set<NodeKey> = []
    for key in staying {
      if let oldPos = oldPositions[key], let newPos = newPositions[key], oldPos != newPos {
        moved.insert(key)
      }
    }

    // Optional heuristic: redecorate decorators when siblings in the same parent changed
    let siblingTriggered: Set<NodeKey> = []

    // Handle removals: remove view if present, drop caches
    for key in removed {
      if let item = editor.decoratorCache[key], let view = item.view {
        view.removeFromSuperview()
      }
      destroyCachedDecoratorView(forKey: key)
      textStorage.decoratorPositionCache[key] = nil
    }

    // Handle additions: mark for creation and set initial position
    for key in added {
      if editor.decoratorCache[key] == nil {
        editor.decoratorCache[key] = .needsCreation
      }
      if let cacheItem = editor.rangeCache[key] {
        textStorage.decoratorPositionCache[key] = cacheItem.locationFromFenwick(using: editor.fenwickTree)
      }
    }

    // Handle decorators that remain: mark for (re)decorate if dirty or moved; refresh position
    for key in staying {
      // Skip any keys that were removed/detached
      if removed.contains(key) { continue }

      let isDirty = editor.dirtyNodes[key] != nil || editor.dirtyType == .fullReconcile
      let shouldRedecorate = isDirty || moved.contains(key) || siblingTriggered.contains(key)

      if shouldRedecorate {
        if let cacheItem = editor.decoratorCache[key], let view = cacheItem.view {
          editor.decoratorCache[key] = .needsDecorating(view)
        } else if editor.decoratorCache[key] == nil {
          // No cache entry yet; ensure creation will occur
          editor.decoratorCache[key] = .needsCreation
        }
      }

      if let rc = editor.rangeCache[key] {
        textStorage.decoratorPositionCache[key] = rc.locationFromFenwick(using: editor.fenwickTree)
      }
    }
  }

  /// Attachment check against a specific EditorState (do not rely on global active state)
  private static func isAttachedInState(_ nodeKey: NodeKey, state: EditorState) -> Bool {
    var key: NodeKey? = nodeKey
    while let k = key {
      if k == kRootNodeKey { return true }
      guard let node = state.nodeMap[k], let parent = node.parent else { break }
      key = parent
    }
    return false
  }

  /// Records metrics for successful optimized reconciliation
  private static func recordOptimizedReconciliationMetrics(
    editor: Editor,
    appliedDeltas: Int,
    fenwickUpdates: Int,
    startTime: Date,
    nodeCount: Int,
    textStorageLength: Int
  ) {
    let duration = Date().timeIntervalSince(startTime)
    let metric = OptimizedReconcilerMetric(
      deltaCount: appliedDeltas,
      fenwickOperations: fenwickUpdates,
      nodeCount: nodeCount,
      textStorageLength: textStorageLength,
      timestamp: startTime,
      duration: duration
    )

    editor.metricsContainer?.record(.optimizedReconcilerRun(metric))
  }
}

/// Generates deltas from editor state differences
@MainActor
private class DeltaGenerator {
  private let editor: Editor

  init(editor: Editor) {
    self.editor = editor
  }

  /// Generate a batch of deltas representing the changes between two editor states
  func generateDeltaBatch(
    from currentState: EditorState,
    to pendingState: EditorState,
    rangeCache: [NodeKey: RangeCacheItem],
    dirtyNodes: DirtyNodeMap
  ) throws -> DeltaBatch {

    var deltas: [ReconcilerDelta] = []
    var seq: Int = 0

    // Process nodes in document order so sibling insertions keep correct order.
    let orderedDirty = orderedDirtyNodes(in: pendingState, limitedTo: dirtyNodes)
    var processedInsertionLengths: [NodeKey: Int] = [:]
    var runningOffset = 0  // Track cumulative insertion offset
    
    // Detect if this is a fresh document creation or large bulk insertion
    // When most nodes are new insertions and the cache is mostly empty, use sequential positions
    let newInsertionCount = dirtyNodes.keys.filter { rangeCache[$0] == nil }.count
    let isFreshDocument = rangeCache.count < 5 && newInsertionCount > 10
    
    // Generate deltas for each dirty node
    for nodeKey in orderedDirty {
      let currentNode = currentState.nodeMap[nodeKey]
      let pendingNode = pendingState.nodeMap[nodeKey]

      // Node deletion
      if currentNode != nil && pendingNode == nil {
        if let rangeCacheItem = rangeCache[nodeKey] {
          let metadata = DeltaMetadata(sourceUpdate: "Node deletion", orderIndex: seq)
          seq += 1
          let deltaType = ReconcilerDeltaType.nodeDeletion(nodeKey: nodeKey, range: rangeCacheItem.rangeFromFenwick(using: editor.fenwickTree))
          deltas.append(ReconcilerDelta(type: deltaType, metadata: metadata))
        }
        continue
      }

      // Node insertion
      if currentNode == nil, let pendingNode = pendingNode {
        // Generate an insertion delta for the new node with actual content
        let metadata = DeltaMetadata(sourceUpdate: "Node insertion", orderIndex: seq)
        seq += 1

        // Extract actual content from the pending node
        let theme = editor.getTheme()
        
        // Use node-provided pre/post; for fresh docs, nudge newlines to match legacy serialized order with child insertions
        var preambleString = pendingNode.getPreamble()
        var postambleString = pendingNode.getPostamble()
        if isFreshDocument, let elementNode = pendingNode as? ElementNode, !elementNode.isInline() {
          if let _ = elementNode.getNextSibling(), postambleString == "\n" {
            // Defer the newline so child text lands before it; will be placed as preamble of the following block
            postambleString = ""
          }
          if let prev = elementNode.getPreviousSibling(), prev is ElementNode, preambleString.isEmpty {
            preambleString = "\n"
          }
        }
        
        let preambleContent = AttributeUtils.attributedStringByAddingStyles(
          NSAttributedString(string: preambleString),
          from: pendingNode,
          state: pendingState,
          theme: theme
        )
        let postambleContent = AttributeUtils.attributedStringByAddingStyles(
          NSAttributedString(string: postambleString),
          from: pendingNode,
          state: pendingState,
          theme: theme
        )

        // Get the text content based on node type
        var textContent = NSAttributedString(string: "")
        if let textNode = pendingNode as? TextNode {
          let textString = textNode.getText_dangerousPropertyAccess()
          textContent = AttributeUtils.attributedStringByAddingStyles(
            NSAttributedString(string: textString),
            from: pendingNode,
            state: pendingState,
            theme: theme
          )
        } else if let elementNode = pendingNode as? ElementNode {
          // Element nodes may contribute text via pre/post content; their own content is empty.
          textContent = AttributeUtils.attributedStringByAddingStyles(
            NSAttributedString(string: ""),
            from: elementNode,
            state: pendingState,
            theme: theme
          )
        }

        let insertionData = NodeInsertionData(
          preamble: preambleContent,
          content: textContent,
          postamble: postambleContent,
          nodeKey: nodeKey
        )

        // Calculate insertion location based on document structure
        let insertionLocation: Int
        let totalLength = insertionData.preamble.length + insertionData.content.length + insertionData.postamble.length
        
        // For fresh documents, use sequential insertion to match serialized order; otherwise compute structure-based position
        if isFreshDocument {
          insertionLocation = runningOffset
          runningOffset += totalLength
        } else {
          insertionLocation = self.calculateInsertionLocationOrdered(
            for: nodeKey,
            in: pendingState,
            rangeCache: rangeCache,
            processedInsertionLengths: processedInsertionLengths,
            runningOffset: &runningOffset,
            editor: editor)
        }
        
        // Track length for subsequent siblings
        processedInsertionLengths[nodeKey] = totalLength

          let deltaType = ReconcilerDeltaType.nodeInsertion(nodeKey: nodeKey, insertionData: insertionData, location: insertionLocation)
          deltas.append(ReconcilerDelta(type: deltaType, metadata: metadata))
          continue
      }

      // Node modification
      if let currentNode = currentNode, let pendingNode = pendingNode {
        if let currentTextNode = currentNode as? TextNode,
           let pendingTextNode = pendingNode as? TextNode,
           currentTextNode.getText_dangerousPropertyAccess() != pendingTextNode.getText_dangerousPropertyAccess(),
           let rangeCacheItem = rangeCache[nodeKey] {

          let textRange = NSRange(
            location: rangeCacheItem.locationFromFenwick(using: editor.fenwickTree) + rangeCacheItem.preambleLength,
            length: rangeCacheItem.textLength
          )

          let metadata = DeltaMetadata(sourceUpdate: "Text update")
          let deltaType = ReconcilerDeltaType.textUpdate(
            nodeKey: nodeKey,
            newText: pendingTextNode.getText_dangerousPropertyAccess(),
            range: textRange
          )
          deltas.append(ReconcilerDelta(type: deltaType, metadata: DeltaMetadata(sourceUpdate: metadata.sourceUpdate, fenwickTreeIndex: metadata.fenwickTreeIndex, originalRange: metadata.originalRange, orderIndex: seq)))
          seq += 1
          if editor.featureFlags.diagnostics.verboseLogs {
            print("🔥 OPTIMIZED RECONCILER: queued textUpdate for node \(nodeKey) range=\(textRange) old='\(currentTextNode.getText_dangerousPropertyAccess())' new='\(pendingTextNode.getText_dangerousPropertyAccess())'")
          }
        }

        // Inline attribute (format) changes without text change
        if let currentTextNode = currentNode as? TextNode,
           let pendingTextNode = pendingNode as? TextNode,
           currentTextNode.getText_dangerousPropertyAccess() == pendingTextNode.getText_dangerousPropertyAccess(),
           currentTextNode.getFormat() != pendingTextNode.getFormat(),
           let rangeCacheItem = rangeCache[nodeKey] {

          let textRange = NSRange(
            location: rangeCacheItem.locationFromFenwick(using: editor.fenwickTree) + rangeCacheItem.preambleLength,
            length: rangeCacheItem.textLength
          )
          let attrs = pendingTextNode.getAttributedStringAttributes(theme: editor.getTheme())
          let metadata = DeltaMetadata(sourceUpdate: "Inline attribute update")
          let deltaType = ReconcilerDeltaType.attributeChange(
            nodeKey: nodeKey,
            attributes: attrs,
            range: textRange
          )
          deltas.append(ReconcilerDelta(type: deltaType, metadata: DeltaMetadata(sourceUpdate: metadata.sourceUpdate, fenwickTreeIndex: metadata.fenwickTreeIndex, originalRange: metadata.originalRange, orderIndex: seq)))
          seq += 1
        }
      }
    }

    // Create batch metadata
    let batchMetadata = BatchMetadata(
      expectedTextStorageLength: editor.textStorage?.length ?? 0,
      isFreshDocument: isFreshDocument
    )

    return DeltaBatch(deltas: deltas, batchMetadata: batchMetadata)
  }

  /// Traverse the pending state's tree in document order and return the dirty keys in that order.
  private func orderedDirtyNodes(in pendingState: EditorState, limitedTo dirty: DirtyNodeMap) -> [NodeKey] {
    var result: [NodeKey] = []
    func visit(_ key: NodeKey) {
      if dirty[key] != nil { result.append(key) }
      if let node = pendingState.nodeMap[key] as? ElementNode {
        // Use fromLatest: false since we're working with pendingState nodes
        for child in node.getChildrenKeys(fromLatest: false) { visit(child) }
      }
    }
    if let root = pendingState.nodeMap[kRootNodeKey] { visit(root.getKey()) }
    // Fallback: if some dirty nodes were not reachable (shouldn't happen), append them
    for (k, _) in dirty where !result.contains(k) { result.append(k) }
    if getActiveEditor()?.featureFlags.diagnostics.verboseLogs == true {
      print("🔥 OPT RECON: ordered dirty=\(result)")
    }
    return result
  }

  /// Calculate insertion using cache first; if previous sibling not in cache, use processedInsertionLengths.
  private func calculateInsertionLocationOrdered(
    for nodeKey: NodeKey,
    in editorState: EditorState,
    rangeCache: [NodeKey: RangeCacheItem],
    processedInsertionLengths: [NodeKey: Int],
    runningOffset: inout Int,
    editor: Editor
  ) -> Int {
    guard let node = editorState.nodeMap[nodeKey] else { return runningOffset }
    guard let parentKey = node.parent,
          let parentNode = editorState.nodeMap[parentKey] as? ElementNode else { return runningOffset }

    // Use fromLatest: false since parentNode is from editorState, not active state
    let children = parentNode.getChildrenKeys(fromLatest: false)
    guard let idx = children.firstIndex(of: nodeKey) else { return runningOffset }

    if idx == 0 {
      // First child: start at parent's content start
      if let parentCache = rangeCache[parentKey] {
        let loc = editor.featureFlags.optimizedReconciler
          ? parentCache.locationFromFenwick(using: editor.fenwickTree)
          : parentCache.location
        return loc + parentCache.preambleLength
      }
      // Parent is root or also newly inserted - use running offset
      return runningOffset
    }

    let prevKey = children[idx - 1]
    if let prevCache = rangeCache[prevKey] {
      let prevLoc = editor.featureFlags.optimizedReconciler
        ? prevCache.locationFromFenwick(using: editor.fenwickTree)
        : prevCache.location
      return prevLoc + prevCache.preambleLength + prevCache.childrenLength + prevCache.textLength + prevCache.postambleLength
    }
    // Previous sibling also inserted in this batch; use its processed length if available.
    if processedInsertionLengths[prevKey] != nil,
       let parentCache = rangeCache[parentKey] {
      let parentLoc = editor.featureFlags.optimizedReconciler
        ? parentCache.locationFromFenwick(using: editor.fenwickTree)
        : parentCache.location
      // Start of parent's content plus sum of already processed sibling lengths up to prev
      var loc = parentLoc + parentCache.preambleLength
      // Accumulate lengths of siblings up to prev that are in processedInsertionLengths
      for k in children.prefix(idx) {
        if let l = processedInsertionLengths[k] { loc += l }
        else if let c = rangeCache[k] {
          loc += c.preambleLength + c.childrenLength + c.textLength + c.postambleLength
        }
      }
      return loc
    }
    // No cache info available - use running offset for sequential insertions
    return runningOffset
  }

  /// Calculate the insertion location for a new node in the document
  private func calculateInsertionLocation(
    for nodeKey: NodeKey,
    in editorState: EditorState,
    rangeCache: [NodeKey: RangeCacheItem],
    editor: Editor
  ) -> Int {
    guard let node = editorState.nodeMap[nodeKey] else {
      return 0
    }

    // Find the insertion point based on the node's position in its parent
    if let parent = node.parent,
       let parentNode = editorState.nodeMap[parent],
       let elementParent = parentNode as? ElementNode {

      // Use fromLatest: false since elementParent is from editorState, not active state
      let childrenKeys = elementParent.getChildrenKeys(fromLatest: false)
      guard let nodeIndex = childrenKeys.firstIndex(of: nodeKey) else {
        return 0
      }

      // If this is the first child, insert at parent's content start
      if nodeIndex == 0 {
        if let parentCacheItem = rangeCache[parent] {
          let parentLocation = editor.featureFlags.optimizedReconciler
            ? parentCacheItem.locationFromFenwick(using: editor.fenwickTree)
            : parentCacheItem.location
          return parentLocation + parentCacheItem.preambleLength
        }
        return 0
      }

      // Otherwise, insert after the previous sibling
      let previousSiblingKey = childrenKeys[nodeIndex - 1]
      if let previousCacheItem = rangeCache[previousSiblingKey] {
        let siblingLocation = editor.featureFlags.optimizedReconciler
          ? previousCacheItem.locationFromFenwick(using: editor.fenwickTree)
          : previousCacheItem.location
        return siblingLocation + previousCacheItem.preambleLength + previousCacheItem.childrenLength + previousCacheItem.textLength + previousCacheItem.postambleLength
      }
    }

    return 0
  }
}
