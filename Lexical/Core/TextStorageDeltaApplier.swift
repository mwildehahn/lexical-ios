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

    // For fresh documents, keep generation order; otherwise sort by location (reverse) to avoid index shifting
    let sortedDeltas = batch.batchMetadata.isFreshDocument ? batch.deltas : sortDeltasForApplication(batch.deltas)

    // Metrics helpers
    func inc(_ key: String) {
      guard let mc = editor.metricsContainer else { return }
      let current = (mc.metricsData[key] as? Int) ?? 0
      mc.metricsData[key] = current + 1
    }

    func typeKey(_ delta: ReconcilerDelta) -> String {
      switch delta.type {
      case .textUpdate: return "textUpdate"
      case .nodeInsertion: return "nodeInsertion"
      case .nodeDeletion: return "nodeDeletion"
      case .attributeChange: return "attributeChange"
      }
    }

    for delta in sortedDeltas {
      do {
        let result = try applySingleDelta(delta, to: textStorage)
        appliedDeltas += 1
        fenwickUpdates += result.fenwickUpdates

        // Update metrics if enabled
        if editor.featureFlags.reconcilerMetrics {
          recordDeltaMetrics(delta: delta, result: result)
          inc("optimized.delta.applied.total")
          inc("optimized.delta.applied.\(typeKey(delta))")
        }

      } catch {
        failedDeltas.append(delta)
        if editor.featureFlags.reconcilerMetrics {
          inc("optimized.delta.failed.total")
          inc("optimized.delta.failed.\(typeKey(delta))")
        }

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

    if editor.featureFlags.diagnostics.verboseLogs {
      print("🔥 DELTA APPLIER: handling delta \(delta.type)")
    }

    switch delta.type {
    case .textUpdate(let nodeKey, let newText, let range):
      if editor.featureFlags.diagnostics.verboseLogs {
        print("🔥 APPLY TEXT-UPDATE: key=\(nodeKey) range=\(NSStringFromRange(range)) new='\(newText.replacingOccurrences(of: "\n", with: "\\n"))'")
      }
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

    // Validate range strictly; align with attribute/deletion behaviour
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
      let fenwickIndex = getFenwickIndexForNode(nodeKey) ?? ensureFenwickIndex(for: nodeKey)
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
      if editor.featureFlags.diagnostics.verboseLogs {
        print("🔥 DELTA APPLIER: clamped insertion for node \(nodeKey) from \(location) to \(clampedLocation) (text length \(textStorage.length))")
      }
      if let mc = editor.metricsContainer {
        let key = "optimized.clampedInsertions"
        let current = (mc.metricsData[key] as? Int) ?? 0
        mc.metricsData[key] = current + 1
      }
    } else if editor.featureFlags.diagnostics.verboseLogs {
      print("🔥 DELTA APPLIER: inserting node \(nodeKey) at \(clampedLocation) (text length \(textStorage.length))")
    }

    // Build complete attributed string
    let completeString = NSMutableAttributedString()
    completeString.append(insertionData.preamble)
    completeString.append(insertionData.content)
    completeString.append(insertionData.postamble)

    // Insert into TextStorage
    textStorage.insert(completeString, at: clampedLocation)
    if editor.featureFlags.diagnostics.verboseLogs {
      print("🔥 DELTA APPLIER: post-insert text length \(textStorage.length)")
    }

    // Update FenwickTree only for nodes that contribute text content.
    var fenwickUpdates = 0
    if insertionData.content.length > 0 {
      let fenwickIndex = getFenwickIndexForNode(nodeKey) ?? ensureFenwickIndex(for: nodeKey)
      fenwickTree.update(index: fenwickIndex, delta: insertionData.content.length)
      fenwickUpdates = 1
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

    // Update FenwickTree only by the node's text contribution, not entire range
    var fenwickUpdates = 0
    if let fenwickIndex = getFenwickIndexForNode(nodeKey), let cacheItem = editor.rangeCache[nodeKey] {
      let textLen = cacheItem.textLength
      if textLen != 0 {
        fenwickTree.update(index: fenwickIndex, delta: -textLen)
        fenwickUpdates = 1
      }
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

    // Apply attributes; also synthesize a correct UIFont from bold/italic flags so rendering reflects changes.
    var attrsToApply = attributes
    if editor.featureFlags.diagnostics.verboseLogs {
      print("🔥 ATTR-CHANGE: range=\(NSStringFromRange(range)) keys=\(Array(attrsToApply.keys))")
    }
    let baseFont = (textStorage.attribute(.font, at: max(0, range.location - 1), effectiveRange: nil) as? UIFont) ?? LexicalConstants.defaultFont
    let desc = baseFont.fontDescriptor
    var traits = desc.symbolicTraits
    if let isBold = attributes[.bold] as? Bool {
      traits = isBold ? traits.union([.traitBold]) : traits.subtracting([.traitBold])
    }
    if let isItalic = attributes[.italic] as? Bool {
      traits = isItalic ? traits.union([.traitItalic]) : traits.subtracting([.traitItalic])
    }
    if let updatedDesc = desc.withSymbolicTraits(traits) {
      let newFont = UIFont(descriptor: updatedDesc, size: 0)
      attrsToApply[.font] = newFont
    }
    textStorage.addAttributes(attrsToApply, range: range)
    if editor.featureFlags.diagnostics.verboseLogs {
      let check = textStorage.attributes(at: range.location, effectiveRange: nil)
      print("🔥 ATTR-APPLIED: at=\(range.location) keys=\(Array(check.keys)) underline=\(String(describing: check[.underlineStyle]))")
    }

    // Attribute changes don't affect length or FenwickTree
    return DeltaApplicationSingleResult(fenwickUpdates: 0, lengthDelta: 0)
  }


  // MARK: - Helper Methods

  private func validateBatchPreconditions(_ batch: DeltaBatch, textStorage: NSTextStorage) -> Bool {
    // Check expected length
    if textStorage.length != batch.batchMetadata.expectedTextStorageLength {
      editor.log(.reconciler, .warning, "TextStorage length mismatch: expected \(batch.batchMetadata.expectedTextStorageLength), got \(textStorage.length)")
      if editor.featureFlags.diagnostics.verboseLogs {
        print("🔥 DELTA APPLIER: precondition fail (len expected=\(batch.batchMetadata.expectedTextStorageLength) actual=\(textStorage.length) fresh=\(batch.batchMetadata.isFreshDocument))")
      }
      return false
    }

    return true
  }

  private func sortDeltasForApplication(_ deltas: [ReconcilerDelta]) -> [ReconcilerDelta] {
    // Sort by location in reverse order to avoid index shifting issues.
    // When locations tie, apply later-generated deltas first to preserve
    // document order for siblings inserted at the same position.
    return deltas.sorted { d1, d2 in
      let l1 = getLocationFromDelta(d1)
      let l2 = getLocationFromDelta(d2)
      if l1 != l2 { return l1 > l2 }
      let o1 = d1.metadata.orderIndex ?? 0
      let o2 = d2.metadata.orderIndex ?? 0
      return o1 > o2
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

  // Ensure a stable Fenwick index exists for this node and return it
  private func ensureFenwickIndex(for nodeKey: NodeKey) -> Int {
    if let idx = editor.fenwickIndexMap[nodeKey] { return idx }
    let idx = editor.nextFenwickIndex
    editor.nextFenwickIndex += 1
    editor.fenwickIndexMap[nodeKey] = idx
    return idx
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
