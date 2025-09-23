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
  private var lastValidationTimestamp: Date = Date()

  // MARK: - Initialization

  init(editor: Editor, fenwickTree: FenwickTree) {
    self.editor = editor
    self.fenwickTree = fenwickTree
  }

  // MARK: - Delta Application

  /// Apply a batch of deltas to the TextStorage
  func applyDeltaBatch(
    _ batch: DeltaBatch,
    to textStorage: NSTextStorage
  ) -> DeltaApplicationResult {

    // Pre-flight checks
    guard validateBatchPreconditions(batch, textStorage: textStorage) else {
      return .failure(reason: "Batch precondition validation failed")
    }

    // Process any number of deltas - no arbitrary limits
    editor.log(.reconciler, .message, "Applying \(batch.deltas.count) deltas")

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

    // Post-application validation could go here if needed

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

    print("🔥 DELTA APPLIER: handling delta \(delta.type)")

    switch delta.type {
    case .textUpdate(let nodeKey, let newText, let range):
      return try applyTextUpdate(nodeKey: nodeKey, newText: newText, range: range, to: textStorage)

    case .nodeInsertion(let nodeKey, let insertionData, let location):
      return try applyNodeInsertion(nodeKey: nodeKey, insertionData: insertionData, location: location, to: textStorage)

    case .nodeDeletion(let nodeKey, let range):
      return try applyNodeDeletion(nodeKey: nodeKey, range: range, to: textStorage)

    case .attributeChange(let nodeKey, let attributes, let range):
      return try applyAttributeChange(nodeKey: nodeKey, attributes: attributes, range: range, to: textStorage)
    }
  }

  // MARK: - Specific Delta Implementations

  private func applyTextUpdate(
    nodeKey: NodeKey,
    newText: String,
    range: NSRange,
    to textStorage: NSTextStorage
  ) throws -> DeltaApplicationSingleResult {

    // Validate and clamp range to current storage bounds. In optimized mode
    // the Fenwick/range-cache can lag by a few characters within the same UI
    // turn; instead of aborting, align to TextKit expectations and continue.
    var safeLocation = max(0, min(range.location, textStorage.length))
    var safeMax = max(safeLocation, min(NSMaxRange(range), textStorage.length))
    var safeRange = NSRange(location: safeLocation, length: safeMax - safeLocation)
    if safeRange != range {
      editor.log(
        .reconciler,
        .warning,
        "Adjusted textUpdate range from \(NSStringFromRange(range)) to \(NSStringFromRange(safeRange)) for node \(nodeKey)"
      )
    }

    // Calculate length delta
    let oldLength = safeRange.length
    let newLength = (newText as NSString).length
    let lengthDelta = newLength - oldLength

    // Apply the text change
    textStorage.replaceCharacters(in: safeRange, with: newText)

    // Update FenwickTree if there's a length change
    var fenwickUpdates = 0
    if lengthDelta != 0 {
      let fenwickIndex = getFenwickIndexForNode(nodeKey) ?? fenwickIndex(forLocation: safeRange.location)
      fenwickTree.update(index: fenwickIndex, delta: lengthDelta)
      fenwickUpdates = 1
    }

    return DeltaApplicationSingleResult(fenwickUpdates: fenwickUpdates, lengthDelta: lengthDelta)
  }

  private func applyNodeInsertion(
    nodeKey: NodeKey,
    insertionData: NodeInsertionData,
    location: Int,
    to textStorage: NSTextStorage
  ) throws -> DeltaApplicationSingleResult {

    // Clamp the location to the valid text storage bounds. The legacy reconciler
    // performs its mutations while holding controller-mode editing on the text
    // storage, which effectively normalises insert positions. When we drive the
    // text storage directly through the optimized reconciler we need to emulate
    // the same behaviour; otherwise small discrepancies in the calculated
    // offsets (for example when inserting multiple new siblings whose range
    // cache entries have not been initialised yet) can leave us with targets
    // slightly beyond the current length. Rather than bailing out entirely,
    // align with TextKit by clamping into range and continue.
    let clampedLocation = min(max(location, 0), textStorage.length)

    if clampedLocation != location {
      print("🔥 DELTA APPLIER: clamped insertion for node \(nodeKey) from \(location) to \(clampedLocation) (text length \(textStorage.length))")
    } else {
      print("🔥 DELTA APPLIER: inserting node \(nodeKey) at \(clampedLocation) (text length \(textStorage.length))")
    }

    // Build complete attributed string
    let completeString = NSMutableAttributedString()
    completeString.append(insertionData.preamble)
    completeString.append(insertionData.content)
    completeString.append(insertionData.postamble)

    // Insert into TextStorage
    textStorage.insert(completeString, at: clampedLocation)
    print("🔥 DELTA APPLIER: post-insert text length \(textStorage.length)")

    // Update FenwickTree
    let fenwickIndex = getFenwickIndexForNode(nodeKey) ?? fenwickIndex(forLocation: clampedLocation)
    fenwickTree.update(index: fenwickIndex, delta: completeString.length)
    let fenwickUpdates = 1

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


  // MARK: - Helper Methods

  private func validateBatchPreconditions(_ batch: DeltaBatch, textStorage: NSTextStorage) -> Bool {
    // Check expected length
    if textStorage.length != batch.batchMetadata.expectedTextStorageLength {
      editor.log(.reconciler, .warning, "TextStorage length mismatch: expected \(batch.batchMetadata.expectedTextStorageLength), got \(textStorage.length)")
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


  private func recordDeltaMetrics(delta: ReconcilerDelta, result: DeltaApplicationSingleResult) {
    // Record delta application metrics if metrics are enabled
    guard editor.featureFlags.reconcilerMetrics,
          let metricsContainer = editor.metricsContainer else { return }

    // Create a delta metric
    let deltaMetric = DeltaApplicationMetric(
      deltaType: String(describing: delta.type),
      fenwickOperations: result.fenwickUpdates,
      lengthDelta: result.lengthDelta,
      timestamp: Date()
    )

    // Record the metric
    metricsContainer.record(.deltaApplication(deltaMetric))

    // Log if in debug mode
    editor.log(.reconciler, .verbose, "Delta applied: type=\(deltaMetric.deltaType), fenwick=\(deltaMetric.fenwickOperations), lengthDelta=\(deltaMetric.lengthDelta)")
  }

  private func getFenwickIndexForNode(_ nodeKey: NodeKey) -> Int? {
    // Get the range cache item for this node
    guard let rangeCacheItem = editor.rangeCache[nodeKey] else { return nil }

    // Return the node's index in the Fenwick tree
    return rangeCacheItem.nodeIndex
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
  case fenwickTreeUpdateFailed(String)
}

private func fenwickIndex(forLocation location: Int) -> Int {
  return max(0, location / 100)
}
