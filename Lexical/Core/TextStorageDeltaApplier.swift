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

/// Applies delta changes to TextStorage incrementally using FenwickTree for offset management
@MainActor
internal class TextStorageDeltaApplier {

  private let editor: Editor
  private let fenwickTree: FenwickTree
  private let anchorManager: AnchorManager
  private var lastValidationTimestamp: Date = Date()

  // MARK: - Initialization

  init(editor: Editor, fenwickTree: FenwickTree) {
    self.editor = editor
    self.fenwickTree = fenwickTree
    self.anchorManager = editor.anchorManager
  }

  // MARK: - Delta Application

  /// Apply a batch of deltas to the TextStorage
  func applyDeltaBatch(
    _ batch: DeltaBatch,
    to textStorage: NSTextStorage
  ) -> DeltaApplicationResult {

    // Pre-flight checks
    guard validateBatchPreconditions(batch, textStorage: textStorage) else {
      return .failure(reason: "Batch precondition validation failed", shouldFallback: true)
    }

    // Check if we should fallback based on batch size
    if batch.deltas.count > batch.batchMetadata.fallbackThreshold {
      return .failure(
        reason: "Batch size (\(batch.deltas.count)) exceeds threshold (\(batch.batchMetadata.fallbackThreshold))",
        shouldFallback: true
      )
    }

    var appliedDeltas = 0
    var fenwickUpdates = 0
    var failedDeltas: [ReconcilerDelta] = []

    // Sort deltas by location (reverse order for safe application)
    let sortedDeltas = sortDeltasForApplication(batch.deltas)

    for delta in sortedDeltas {
      do {
        let result = try applySingleDelta(delta, to: textStorage)
        appliedDeltas += 1
        fenwickUpdates += result.fenwickUpdates

        // Update metrics if enabled
        if editor.featureFlags.reconcilerMetrics {
          recordDeltaMetrics(delta: delta, result: result)
        }

      } catch {
        failedDeltas.append(delta)

        // Decide whether to continue or abort
        if shouldAbortOnFailure(delta, error: error) {
          return .partialSuccess(
            appliedDeltas: appliedDeltas,
            failedDeltas: failedDeltas + Array(sortedDeltas.dropFirst(appliedDeltas + 1)),
            reason: "Critical delta failed: \(error.localizedDescription)"
          )
        }
      }
    }

    // Post-application validation
    if batch.batchMetadata.requiresAnchorValidation {
      let anchorValidation = validateAnchorsAfterApplication(textStorage)
      if !anchorValidation.isValid {
        return .failure(
          reason: "Anchor validation failed: \(anchorValidation.reason)",
          shouldFallback: true
        )
      }
    }

    // Return final result
    if failedDeltas.isEmpty {
      return .success(appliedDeltas: appliedDeltas, fenwickTreeUpdates: fenwickUpdates)
    } else {
      return .partialSuccess(
        appliedDeltas: appliedDeltas,
        failedDeltas: failedDeltas,
        reason: "Some deltas failed but batch completed"
      )
    }
  }

  // MARK: - Single Delta Application

  private func applySingleDelta(
    _ delta: ReconcilerDelta,
    to textStorage: NSTextStorage
  ) throws -> DeltaApplicationSingleResult {

    switch delta.type {
    case .textUpdate(let nodeKey, let newText, let range):
      return try applyTextUpdate(nodeKey: nodeKey, newText: newText, range: range, to: textStorage)

    case .nodeInsertion(let nodeKey, let insertionData, let location):
      return try applyNodeInsertion(nodeKey: nodeKey, insertionData: insertionData, location: location, to: textStorage)

    case .nodeDeletion(let nodeKey, let range):
      return try applyNodeDeletion(nodeKey: nodeKey, range: range, to: textStorage)

    case .attributeChange(let nodeKey, let attributes, let range):
      return try applyAttributeChange(nodeKey: nodeKey, attributes: attributes, range: range, to: textStorage)

    case .anchorUpdate(let nodeKey, let preambleLocation, let postambleLocation):
      return try applyAnchorUpdate(nodeKey: nodeKey, preambleLocation: preambleLocation, postambleLocation: postambleLocation, to: textStorage)
    }
  }

  // MARK: - Specific Delta Implementations

  private func applyTextUpdate(
    nodeKey: NodeKey,
    newText: String,
    range: NSRange,
    to textStorage: NSTextStorage
  ) throws -> DeltaApplicationSingleResult {

    // Validate range
    guard range.location >= 0 && NSMaxRange(range) <= textStorage.length else {
      throw DeltaApplicationError.invalidRange(range, textStorageLength: textStorage.length)
    }

    // Calculate length delta
    let oldLength = range.length
    let newLength = (newText as NSString).length
    let lengthDelta = newLength - oldLength

    // Apply the text change
    textStorage.replaceCharacters(in: range, with: newText)

    // Update FenwickTree if there's a length change
    var fenwickUpdates = 0
    if lengthDelta != 0 {
      // Find the FenwickTree index for this node
      if let fenwickIndex = getFenwickIndexForNode(nodeKey) {
        fenwickTree.update(index: fenwickIndex, delta: lengthDelta)
        fenwickUpdates = 1
      } else {
        // For now, if we can't find the node in range cache, we'll still succeed
        // In a real implementation, this might require different handling
        fenwickUpdates = 0
      }
    }

    return DeltaApplicationSingleResult(fenwickUpdates: fenwickUpdates, lengthDelta: lengthDelta)
  }

  private func applyNodeInsertion(
    nodeKey: NodeKey,
    insertionData: NodeInsertionData,
    location: Int,
    to textStorage: NSTextStorage
  ) throws -> DeltaApplicationSingleResult {

    // Validate location
    guard location >= 0 && location <= textStorage.length else {
      throw DeltaApplicationError.invalidLocation(location, textStorageLength: textStorage.length)
    }

    // Build complete attributed string with anchors if enabled
    let completeString = NSMutableAttributedString()

    if editor.featureFlags.anchorBasedReconciliation {
      // Add preamble anchor
      if let preambleAnchor = anchorManager.generateAnchorAttributedString(
        for: nodeKey,
        type: .preamble,
        theme: editor.getTheme()
      ) {
        completeString.append(preambleAnchor)
      }
    }

    // Add node content
    completeString.append(insertionData.preamble)
    completeString.append(insertionData.content)
    completeString.append(insertionData.postamble)

    if editor.featureFlags.anchorBasedReconciliation {
      // Add postamble anchor
      if let postambleAnchor = anchorManager.generateAnchorAttributedString(
        for: nodeKey,
        type: .postamble,
        theme: editor.getTheme()
      ) {
        completeString.append(postambleAnchor)
      }
    }

    // Insert into TextStorage
    textStorage.insert(completeString, at: location)

    // Update FenwickTree
    var fenwickUpdates = 0
    if let fenwickIndex = getFenwickIndexForNode(nodeKey) {
      fenwickTree.update(index: fenwickIndex, delta: completeString.length)
      fenwickUpdates = 1
    } else {
      // For new nodes, we might not have a range cache entry yet
      fenwickUpdates = 0
    }

    return DeltaApplicationSingleResult(fenwickUpdates: fenwickUpdates, lengthDelta: completeString.length)
  }

  private func applyNodeDeletion(
    nodeKey: NodeKey,
    range: NSRange,
    to textStorage: NSTextStorage
  ) throws -> DeltaApplicationSingleResult {

    // Validate range
    guard range.location >= 0 && NSMaxRange(range) <= textStorage.length else {
      throw DeltaApplicationError.invalidRange(range, textStorageLength: textStorage.length)
    }

    let deletedLength = range.length

    // Remove from TextStorage
    textStorage.deleteCharacters(in: range)

    // Update FenwickTree
    var fenwickUpdates = 0
    if let fenwickIndex = getFenwickIndexForNode(nodeKey) {
      fenwickTree.update(index: fenwickIndex, delta: -deletedLength)
      fenwickUpdates = 1
    } else {
      // For nodes being deleted, we might not find them in range cache
      fenwickUpdates = 0
    }

    return DeltaApplicationSingleResult(fenwickUpdates: fenwickUpdates, lengthDelta: -deletedLength)
  }

  private func applyAttributeChange(
    nodeKey: NodeKey,
    attributes: [NSAttributedString.Key: Any],
    range: NSRange,
    to textStorage: NSTextStorage
  ) throws -> DeltaApplicationSingleResult {

    // Validate range
    guard range.location >= 0 && NSMaxRange(range) <= textStorage.length else {
      throw DeltaApplicationError.invalidRange(range, textStorageLength: textStorage.length)
    }

    // Apply attributes
    textStorage.addAttributes(attributes, range: range)

    // Attribute changes don't affect length or FenwickTree
    return DeltaApplicationSingleResult(fenwickUpdates: 0, lengthDelta: 0)
  }

  private func applyAnchorUpdate(
    nodeKey: NodeKey,
    preambleLocation: Int?,
    postambleLocation: Int?,
    to textStorage: NSTextStorage
  ) throws -> DeltaApplicationSingleResult {

    // This is mainly for updating anchor tracking, not the actual TextStorage
    // The actual anchors are managed by AnchorManager

    // TODO: Update internal anchor tracking if needed

    return DeltaApplicationSingleResult(fenwickUpdates: 0, lengthDelta: 0)
  }

  // MARK: - Helper Methods

  private func validateBatchPreconditions(_ batch: DeltaBatch, textStorage: NSTextStorage) -> Bool {
    // Check expected length
    if textStorage.length != batch.batchMetadata.expectedTextStorageLength {
      return false
    }

    // Validate timestamp (not too old)
    let maxAge: TimeInterval = 5.0 // 5 seconds
    if Date().timeIntervalSince(batch.batchMetadata.timestamp) > maxAge {
      return false
    }

    return true
  }

  private func sortDeltasForApplication(_ deltas: [ReconcilerDelta]) -> [ReconcilerDelta] {
    // Sort by location in reverse order to avoid index shifting issues
    return deltas.sorted { delta1, delta2 in
      let location1 = getLocationFromDelta(delta1)
      let location2 = getLocationFromDelta(delta2)
      return location1 > location2
    }
  }

  private func getLocationFromDelta(_ delta: ReconcilerDelta) -> Int {
    switch delta.type {
    case .textUpdate(_, _, let range):
      return range.location
    case .nodeInsertion(_, _, let location):
      return location
    case .nodeDeletion(_, let range):
      return range.location
    case .attributeChange(_, _, let range):
      return range.location
    case .anchorUpdate:
      return 0 // Anchor updates don't have a specific location
    }
  }

  private func shouldAbortOnFailure(_ delta: ReconcilerDelta, error: Error) -> Bool {
    // Critical errors that should abort the batch
    if case DeltaApplicationError.invalidRange = error {
      return true
    }
    if case DeltaApplicationError.invalidLocation = error {
      return true
    }
    return false
  }

  private func validateAnchorsAfterApplication(_ textStorage: NSTextStorage) -> (isValid: Bool, reason: String) {
    guard editor.featureFlags.anchorBasedReconciliation else {
      return (true, "Anchor validation skipped - feature disabled")
    }

    let isValid = anchorManager.validateAnchors(in: textStorage)
    return (isValid, isValid ? "Anchors valid" : "Anchor validation failed")
  }

  private func recordDeltaMetrics(delta: ReconcilerDelta, result: DeltaApplicationSingleResult) {
    // TODO: Record metrics for performance monitoring
  }

  private func getFenwickIndexForNode(_ nodeKey: NodeKey) -> Int? {
    // Get the range cache item for this node
    guard let rangeCacheItem = editor.rangeCache[nodeKey] else { return nil }

    // For now, use a simple mapping based on the node's location in the document
    // This would be improved with a proper node-to-index mapping system
    let nodeLocation = rangeCacheItem.location

    // Calculate fenwick index based on location (simplified approach)
    // In a real implementation, this would be based on the tree structure
    return max(0, nodeLocation / 100) // Group every ~100 characters into one fenwick index
  }
}

// MARK: - Supporting Types

private struct DeltaApplicationSingleResult {
  let fenwickUpdates: Int
  let lengthDelta: Int
}

private enum DeltaApplicationError: Error {
  case invalidRange(NSRange, textStorageLength: Int)
  case invalidLocation(Int, textStorageLength: Int)
  case anchorValidationFailed(String)
  case fenwickTreeUpdateFailed(String)
}