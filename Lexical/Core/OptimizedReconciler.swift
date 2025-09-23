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

    // Marked text operations not yet supported in optimized path
    if markedTextOperation != nil {
      throw LexicalError.invariantViolation("Marked text operations not yet supported in optimized reconciliation")
    }

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

    // Log delta count for debugging
    editor.log(.reconciler, .message, "Generated \(deltaBatch.deltas.count) deltas")

    // Debug: Log what deltas we actually generated
    for (index, delta) in deltaBatch.deltas.enumerated() {
      switch delta.type {
      case .nodeInsertion(let nodeKey, let insertionData, let location):
        editor.log(.reconciler, .message, "Delta \(index): INSERT node \(nodeKey) at \(location), content length: \(insertionData.content.length)")
      case .textUpdate(let nodeKey, let newText, let range):
        editor.log(.reconciler, .message, "Delta \(index): UPDATE node \(nodeKey) text: '\(newText.prefix(20))...' at \(range)")
      case .nodeDeletion(let nodeKey, let range):
        editor.log(.reconciler, .message, "Delta \(index): DELETE node \(nodeKey) at \(range)")
      case .attributeChange(let nodeKey, _, let range):
        editor.log(.reconciler, .message, "Delta \(index): ATTR node \(nodeKey) at \(range)")
      }
    }

    print("🔥 OPTIMIZED RECONCILER: textStorage length before apply: \(textStorage.length)")

    let previousMode = textStorage.mode
    textStorage.mode = .controllerMode
    textStorage.beginEditing()
    defer {
      textStorage.endEditing()
      textStorage.mode = previousMode
    }

    // Apply deltas
    let applicationResult = deltaApplier.applyDeltaBatch(deltaBatch, to: textStorage)

    print("🔥 OPTIMIZED RECONCILER: textStorage length after apply: \(textStorage.length)")

    switch applicationResult {
    case .success(let appliedDeltas, let fenwickUpdates):
      print("🔥 OPTIMIZED RECONCILER: delta application success (applied=\(appliedDeltas), fenwick=\(fenwickUpdates))")
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

    case .partialSuccess(let appliedDeltas, let failedDeltas, let reason):
      // Log but continue - we applied what we could
      editor.log(.reconciler, .warning, "Partial delta application: \(appliedDeltas) applied, \(failedDeltas.count) failed: \(reason)")
      print("🔥 OPTIMIZED RECONCILER: delta application partial (applied=\(appliedDeltas), failed=\(failedDeltas.count)) reason=\(reason)")

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
          let metadata = DeltaMetadata(sourceUpdate: "Node deletion")
          let deltaType = ReconcilerDeltaType.nodeDeletion(nodeKey: nodeKey, range: rangeCacheItem.rangeFromFenwick(using: editor.fenwickTree))
          deltas.append(ReconcilerDelta(type: deltaType, metadata: metadata))
        }
        continue
      }

      // Node insertion
      if currentNode == nil, let pendingNode = pendingNode {
        // Generate an insertion delta for the new node with actual content
        let metadata = DeltaMetadata(sourceUpdate: "Node insertion")

        // Extract actual content from the pending node
        let theme = editor.getTheme()
        
        // For fresh documents with ElementNodes, adjust preamble/postamble handling
        // to ensure newlines appear between paragraph content, not before it
        var preambleString = pendingNode.getPreamble()
        var postambleString = pendingNode.getPostamble()
        
        if isFreshDocument, let elementNode = pendingNode as? ElementNode, !elementNode.isInline() {
          // For block-level elements in fresh documents:
          // Move postamble to preamble of next sibling to ensure newlines come after content
          if let nextSibling = elementNode.getNextSibling(),
             !nextSibling.isInline(),
             postambleString == "\n" {
            // Don't emit postamble here; the next block will get it as preamble
            postambleString = ""
          }
          // If we're a block after another block, add newline as preamble
          if let prevSibling = elementNode.getPreviousSibling() as? ElementNode,
             !prevSibling.isInline(),
             preambleString == "" {
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
        
        // For fresh documents, use sequential insertion
        if isFreshDocument {
          insertionLocation = runningOffset
          runningOffset += totalLength
        } else {
          // For incremental updates, calculate position based on document structure
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
          deltas.append(ReconcilerDelta(type: deltaType, metadata: metadata))
          print("🔥 OPTIMIZED RECONCILER: queued textUpdate for node \(nodeKey) range=\(textRange) old='\(currentTextNode.getText_dangerousPropertyAccess())' new='\(pendingTextNode.getText_dangerousPropertyAccess())'")
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
          deltas.append(ReconcilerDelta(type: deltaType, metadata: metadata))
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
