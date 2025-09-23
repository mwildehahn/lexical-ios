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
      // Update range cache incrementally
      let cacheUpdater = IncrementalRangeCacheUpdater(editor: editor, fenwickTree: editor.fenwickTree)
      try cacheUpdater.updateRangeCache(
        &editor.rangeCache,
        basedOn: deltaBatch.deltas
      )

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

    case .failure(let reason):
      // This is a real failure - throw an error
      throw LexicalError.invariantViolation("Delta application failed: \(reason)")
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

    // Generate deltas for each dirty node
    for (nodeKey, _) in dirtyNodes {
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
        let preambleContent = AttributeUtils.attributedStringByAddingStyles(
          NSAttributedString(string: pendingNode.getPreamble()),
          from: pendingNode,
          state: pendingState,
          theme: theme
        )
        let postambleContent = AttributeUtils.attributedStringByAddingStyles(
          NSAttributedString(string: pendingNode.getPostamble()),
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
        let insertionLocation = self.calculateInsertionLocation(for: nodeKey, in: pendingState, rangeCache: rangeCache, editor: editor)

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
        }
      }
    }

    // Create batch metadata
    let batchMetadata = BatchMetadata(
      expectedTextStorageLength: editor.textStorage?.length ?? 0
    )

    return DeltaBatch(deltas: deltas, batchMetadata: batchMetadata)
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

      let childrenKeys = elementParent.getChildrenKeys()
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
