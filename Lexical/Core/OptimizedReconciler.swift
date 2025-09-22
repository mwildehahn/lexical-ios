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

  /// Attempts optimized reconciliation, falling back to full reconciliation if needed
  static func attemptOptimizedReconciliation(
    currentEditorState: EditorState,
    pendingEditorState: EditorState,
    editor: Editor,
    shouldReconcileSelection: Bool,
    markedTextOperation: MarkedTextOperation?
  ) throws -> Bool {

    // Early exit if optimized reconciler is disabled
    guard editor.featureFlags.optimizedReconciler else {
      return false
    }

    // Early exit for marked text operations (not yet supported in optimized path)
    if markedTextOperation != nil {
      editor.log(.reconciler, .warning, "Skipping optimized reconciliation: marked text operation")
      return false
    }

    guard let textStorage = editor.textStorage else {
      return false
    }

    // Create context for this reconciliation attempt
    let context = ReconcilerContext(
      updateSource: "OptimizedReconciler",
      nodeCount: pendingEditorState.nodeMap.count,
      textStorageLength: textStorage.length
    )

    // Initialize components
    let fallbackDetector = ReconcilerFallbackDetector(editor: editor)
    let deltaGenerator = DeltaGenerator(editor: editor)
    let deltaApplier = TextStorageDeltaApplier(editor: editor, fenwickTree: editor.fenwickTree)
    let validator = DeltaValidator(editor: editor, fenwickTree: editor.fenwickTree)

    do {
      // Generate deltas from the state differences
      let deltaBatch = try deltaGenerator.generateDeltaBatch(
        from: currentEditorState,
        to: pendingEditorState,
        rangeCache: editor.rangeCache,
        dirtyNodes: editor.dirtyNodes
      )

      // Check if we should fallback before attempting optimized reconciliation

      // Safeguard: If no deltas generated but we have dirty nodes, something's wrong
      if deltaBatch.deltas.isEmpty && !editor.dirtyNodes.isEmpty {
        let reason = "No deltas generated despite \(editor.dirtyNodes.count) dirty nodes - falling back for safety"
        editor.log(.reconciler, .warning, reason)
        fallbackDetector.recordOptimizationFailure(reason: reason)
        return false
      }

      // Safeguard: If no deltas generated but significant node count change, fallback
      if deltaBatch.deltas.isEmpty {
        let nodeCountDiff = abs(currentEditorState.nodeMap.count - pendingEditorState.nodeMap.count)
        if nodeCountDiff > 2 {
          let reason = "No deltas generated despite significant node count change (\(currentEditorState.nodeMap.count) -> \(pendingEditorState.nodeMap.count)) - falling back for safety"
          editor.log(.reconciler, .warning, reason)
          fallbackDetector.recordOptimizationFailure(reason: reason)
          return false
        }
      }

      // Additional safeguard: If no deltas generated but node count suggests major changes, fallback
      if deltaBatch.deltas.isEmpty && context.nodeCount > 100 {
        let reason = "No deltas generated for large document (\(context.nodeCount) nodes) - falling back for safety"
        editor.log(.reconciler, .warning, reason)
        fallbackDetector.recordOptimizationFailure(reason: reason)
        return false
      }

      let fallbackDecision = fallbackDetector.shouldFallbackToFullReconciliation(
        for: deltaBatch.deltas,
        textStorage: textStorage,
        context: context
      )

      if case .fallback(let reason) = fallbackDecision {
        editor.log(.reconciler, .warning, "Falling back to full reconciliation: \(reason)")
        fallbackDetector.recordOptimizationFailure(reason: reason)
        return false
      }

      // Validate deltas before application
      let validationResult = validator.validateDeltaBatch(
        deltaBatch,
        against: textStorage,
        rangeCache: editor.rangeCache
      )

      if case .invalid(let errors) = validationResult {
        let reason = "Delta validation failed: \(errors.count) errors"
        editor.log(.reconciler, .warning, reason)
        fallbackDetector.recordOptimizationFailure(reason: reason)
        return false
      }

      // Apply deltas optimistically
      let applicationResult = deltaApplier.applyDeltaBatch(deltaBatch, to: textStorage)

      switch applicationResult {
      case .success(let appliedDeltas, let fenwickUpdates):
        // Update range cache incrementally
        let cacheUpdater = IncrementalRangeCacheUpdater(editor: editor, fenwickTree: editor.fenwickTree)
        try cacheUpdater.updateRangeCache(
          &editor.rangeCache,
          basedOn: deltaBatch.deltas
        )

        // Post-application validation
        let postValidation = validator.validatePostApplication(
          textStorage: textStorage,
          appliedDeltas: deltaBatch.deltas,
          rangeCache: editor.rangeCache
        )

        if case .invalid(let errors) = postValidation {
          let reason = "Post-application validation failed: \(errors.count) errors"
          editor.log(.reconciler, .error, reason)
          fallbackDetector.recordOptimizationFailure(reason: reason)
          return false
        }

        // Success! Record metrics and reset fallback state
        fallbackDetector.resetFallbackState()

        if editor.featureFlags.reconcilerMetrics {
          recordOptimizedReconciliationMetrics(
            editor: editor,
            appliedDeltas: appliedDeltas,
            fenwickUpdates: fenwickUpdates,
            context: context
          )
        }

        editor.log(.reconciler, .warning, "Optimized reconciliation successful: \(appliedDeltas) deltas applied")
        return true

      case .partialSuccess(_, _, let reason):
        editor.log(.reconciler, .warning, "Partial success in optimized reconciliation: \(reason)")
        fallbackDetector.recordOptimizationFailure(reason: "Partial success: \(reason)")
        return false

      case .failure(let reason, _):
        editor.log(.reconciler, .warning, "Optimized reconciliation failed: \(reason)")
        fallbackDetector.recordOptimizationFailure(reason: reason)
        return false
      }

    } catch {
      let reason = "Exception during optimized reconciliation: \(error.localizedDescription)"
      editor.log(.reconciler, .error, reason)
      fallbackDetector.recordOptimizationFailure(reason: reason)
      return false
    }
  }

  /// Records metrics for successful optimized reconciliation
  private static func recordOptimizedReconciliationMetrics(
    editor: Editor,
    appliedDeltas: Int,
    fenwickUpdates: Int,
    context: ReconcilerContext
  ) {
    let duration = Date().timeIntervalSince(context.timestamp)
    let metric = OptimizedReconcilerMetric(
      deltaCount: appliedDeltas,
      fenwickOperations: fenwickUpdates,
      nodeCount: context.nodeCount,
      textStorageLength: context.textStorageLength,
      timestamp: context.timestamp,
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
          let deltaType = ReconcilerDeltaType.nodeDeletion(nodeKey: nodeKey, range: rangeCacheItem.range)
          deltas.append(ReconcilerDelta(type: deltaType, metadata: metadata))
        }
        continue
      }

      // Node insertion
      if currentNode == nil && pendingNode != nil {
        // For now, we'll generate a placeholder insertion delta
        // Full implementation would determine the insertion location
        let metadata = DeltaMetadata(sourceUpdate: "Node insertion")
        let insertionData = NodeInsertionData(
          preamble: NSAttributedString(string: ""),
          content: NSAttributedString(string: ""),
          postamble: NSAttributedString(string: ""),
          nodeKey: nodeKey
        )
        let deltaType = ReconcilerDeltaType.nodeInsertion(nodeKey: nodeKey, insertionData: insertionData, location: 0)
        deltas.append(ReconcilerDelta(type: deltaType, metadata: metadata))
        continue
      }

      // Node modification
      if let currentNode = currentNode, let pendingNode = pendingNode {
        if let currentTextNode = currentNode as? TextNode,
           let pendingTextNode = pendingNode as? TextNode,
           currentTextNode.getTextPart() != pendingTextNode.getTextPart(),
           let rangeCacheItem = rangeCache[nodeKey] {

          let textRange = NSRange(
            location: rangeCacheItem.location + rangeCacheItem.preambleLength,
            length: rangeCacheItem.textLength
          )

          let metadata = DeltaMetadata(sourceUpdate: "Text update")
          let deltaType = ReconcilerDeltaType.textUpdate(
            nodeKey: nodeKey,
            newText: pendingTextNode.getTextPart(),
            range: textRange
          )
          deltas.append(ReconcilerDelta(type: deltaType, metadata: metadata))
        }
      }
    }

    // Create batch metadata
    let batchMetadata = BatchMetadata(
      expectedTextStorageLength: editor.textStorage?.length ?? 0,
      requiresAnchorValidation: editor.featureFlags.anchorBasedReconciliation,
      fallbackThreshold: 100
    )

    return DeltaBatch(deltas: deltas, batchMetadata: batchMetadata)
  }
}