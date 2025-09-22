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

/// Validates delta operations before and after application to ensure correctness
@MainActor
internal class DeltaValidator {

  private let editor: Editor
  private let fenwickTree: FenwickTree

  // MARK: - Initialization

  init(editor: Editor, fenwickTree: FenwickTree) {
    self.editor = editor
    self.fenwickTree = fenwickTree
  }

  // MARK: - Pre-Application Validation

  /// Validate a batch of deltas before application
  func validateDeltaBatch(
    _ batch: DeltaBatch,
    against textStorage: NSTextStorage,
    rangeCache: [NodeKey: RangeCacheItem]
  ) -> ValidationResult {

    // Check batch-level constraints
    if let batchError = validateBatchConstraints(batch) {
      return .invalid(errors: [batchError])
    }

    var errors: [ValidationError] = []

    // Validate individual deltas
    for (index, delta) in batch.deltas.enumerated() {
      if let deltaErrors = validateSingleDelta(delta, index: index, textStorage: textStorage, rangeCache: rangeCache) {
        errors.append(contentsOf: deltaErrors)
      }
    }

    // Check for conflicts between deltas
    if let conflictErrors = validateDeltaConflicts(batch.deltas, textStorage: textStorage) {
      errors.append(contentsOf: conflictErrors)
    }

    return errors.isEmpty ? .valid : .invalid(errors: errors)
  }

  /// Validate a single delta
  private func validateSingleDelta(
    _ delta: ReconcilerDelta,
    index: Int,
    textStorage: NSTextStorage,
    rangeCache: [NodeKey: RangeCacheItem]
  ) -> [ValidationError]? {

    var errors: [ValidationError] = []

    // Validate metadata
    if let metadataError = validateDeltaMetadata(delta.metadata, deltaIndex: index) {
      errors.append(metadataError)
    }

    // Validate specific delta type
    switch delta.type {
    case .textUpdate(let nodeKey, let newText, let range):
      if let textErrors = validateTextUpdate(nodeKey: nodeKey, newText: newText, range: range, textStorage: textStorage, rangeCache: rangeCache) {
        errors.append(contentsOf: textErrors)
      }

    case .nodeInsertion(let nodeKey, let insertionData, let location):
      if let insertionErrors = validateNodeInsertion(nodeKey: nodeKey, insertionData: insertionData, location: location, textStorage: textStorage, rangeCache: rangeCache) {
        errors.append(contentsOf: insertionErrors)
      }

    case .nodeDeletion(let nodeKey, let range):
      if let deletionErrors = validateNodeDeletion(nodeKey: nodeKey, range: range, textStorage: textStorage, rangeCache: rangeCache) {
        errors.append(contentsOf: deletionErrors)
      }

    case .attributeChange(let nodeKey, let attributes, let range):
      if let attributeErrors = validateAttributeChange(nodeKey: nodeKey, attributes: attributes, range: range, textStorage: textStorage, rangeCache: rangeCache) {
        errors.append(contentsOf: attributeErrors)
      }

    }

    return errors.isEmpty ? nil : errors
  }

  // MARK: - Post-Application Validation

  /// Validate TextStorage state after delta application
  func validatePostApplication(
    textStorage: NSTextStorage,
    appliedDeltas: [ReconcilerDelta],
    rangeCache: [NodeKey: RangeCacheItem]
  ) -> ValidationResult {

    var errors: [ValidationError] = []

    // Validate TextStorage integrity
    if let integrityErrors = validateTextStorageIntegrity(textStorage) {
      errors.append(contentsOf: integrityErrors)
    }

    // Validate range cache consistency
    if let rangeCacheErrors = validateRangeCacheConsistency(rangeCache, textStorage: textStorage) {
      errors.append(contentsOf: rangeCacheErrors)
    }


    // Validate FenwickTree consistency
    if let fenwickErrors = validateFenwickTreeConsistency(rangeCache) {
      errors.append(contentsOf: fenwickErrors)
    }

    return errors.isEmpty ? .valid : .invalid(errors: errors)
  }

  // MARK: - Specific Validation Methods

  private func validateBatchConstraints(_ batch: DeltaBatch) -> ValidationError? {
    // Check batch size
    if batch.deltas.count > 1000 {
      return ValidationError.batchTooLarge(batch.deltas.count)
    }

    // Check batch age
    let maxAge: TimeInterval = 10.0 // 10 seconds
    if Date().timeIntervalSince(batch.batchMetadata.timestamp) > maxAge {
      return ValidationError.batchTooOld(batch.batchMetadata.timestamp)
    }

    return nil
  }

  private func validateDeltaMetadata(_ metadata: DeltaMetadata, deltaIndex: Int) -> ValidationError? {
    // Check timestamp
    if metadata.timestamp > Date() {
      return ValidationError.futureTimestamp(metadata.timestamp, deltaIndex: deltaIndex)
    }

    // Check source description
    if metadata.sourceUpdate.isEmpty {
      return ValidationError.missingSourceDescription(deltaIndex: deltaIndex)
    }

    return nil
  }

  private func validateTextUpdate(
    nodeKey: NodeKey,
    newText: String,
    range: NSRange,
    textStorage: NSTextStorage,
    rangeCache: [NodeKey: RangeCacheItem]
  ) -> [ValidationError]? {

    var errors: [ValidationError] = []

    // Validate range bounds
    if range.location < 0 || NSMaxRange(range) > textStorage.length {
      errors.append(ValidationError.rangeOutOfBounds(range, textStorageLength: textStorage.length))
    }

    // Validate node exists
    guard let node = getNodeByKey(key: nodeKey) else {
      errors.append(ValidationError.nodeNotFound(nodeKey))
      return errors
    }

    // Validate node is a text node
    guard node is TextNode else {
      errors.append(ValidationError.invalidNodeType(nodeKey, expected: "TextNode", actual: String(describing: type(of: node))))
      return errors
    }

    // Validate range corresponds to node's text content
    if let rangeCacheItem = rangeCache[nodeKey] {
      let expectedRange = NSRange(
        location: rangeCacheItem.location + rangeCacheItem.preambleLength,
        length: rangeCacheItem.textLength
      )
      if !NSEqualRanges(range, expectedRange) {
        errors.append(ValidationError.rangeMismatch(expected: expectedRange, actual: range, nodeKey: nodeKey))
      }
    }

    return errors.isEmpty ? nil : errors
  }

  private func validateNodeInsertion(
    nodeKey: NodeKey,
    insertionData: NodeInsertionData,
    location: Int,
    textStorage: NSTextStorage,
    rangeCache: [NodeKey: RangeCacheItem]
  ) -> [ValidationError]? {

    var errors: [ValidationError] = []

    // Validate location bounds
    if location < 0 || location > textStorage.length {
      errors.append(ValidationError.locationOutOfBounds(location, textStorageLength: textStorage.length))
    }

    // Validate node doesn't already exist in range cache
    if rangeCache[nodeKey] != nil {
      errors.append(ValidationError.nodeAlreadyExists(nodeKey))
    }

    // Validate insertion data
    if insertionData.nodeKey != nodeKey {
      errors.append(ValidationError.nodeKeyMismatch(expected: nodeKey, actual: insertionData.nodeKey))
    }

    return errors.isEmpty ? nil : errors
  }

  private func validateNodeDeletion(
    nodeKey: NodeKey,
    range: NSRange,
    textStorage: NSTextStorage,
    rangeCache: [NodeKey: RangeCacheItem]
  ) -> [ValidationError]? {

    var errors: [ValidationError] = []

    // Validate range bounds
    if range.location < 0 || NSMaxRange(range) > textStorage.length {
      errors.append(ValidationError.rangeOutOfBounds(range, textStorageLength: textStorage.length))
    }

    // Validate node exists in range cache
    guard let rangeCacheItem = rangeCache[nodeKey] else {
      errors.append(ValidationError.nodeNotInRangeCache(nodeKey))
      return errors
    }

    // Validate range matches node's range
    if !NSEqualRanges(range, rangeCacheItem.range) {
      errors.append(ValidationError.rangeMismatch(expected: rangeCacheItem.range, actual: range, nodeKey: nodeKey))
    }

    return errors.isEmpty ? nil : errors
  }

  private func validateAttributeChange(
    nodeKey: NodeKey,
    attributes: [NSAttributedString.Key: Any],
    range: NSRange,
    textStorage: NSTextStorage,
    rangeCache: [NodeKey: RangeCacheItem]
  ) -> [ValidationError]? {

    var errors: [ValidationError] = []

    // Validate range bounds
    if range.location < 0 || NSMaxRange(range) > textStorage.length {
      errors.append(ValidationError.rangeOutOfBounds(range, textStorageLength: textStorage.length))
    }

    // Validate attributes are safe
    for (key, value) in attributes {
      if !isSafeAttribute(key: key, value: value) {
        errors.append(ValidationError.unsafeAttribute(key, value: value))
      }
    }

    return errors.isEmpty ? nil : errors
  }


  private func validateDeltaConflicts(_ deltas: [ReconcilerDelta], textStorage: NSTextStorage) -> [ValidationError]? {
    var errors: [ValidationError] = []
    var affectedRanges: [NSRange] = []

    // Check for overlapping ranges
    for delta in deltas {
      let range = getRangeFromDelta(delta)

      for existingRange in affectedRanges {
        if NSIntersectionRange(range, existingRange).length > 0 {
          errors.append(ValidationError.overlappingDeltas(range1: range, range2: existingRange))
        }
      }

      affectedRanges.append(range)
    }

    return errors.isEmpty ? nil : errors
  }

  private func validateTextStorageIntegrity(_ textStorage: NSTextStorage) -> [ValidationError]? {
    var errors: [ValidationError] = []

    // Basic length check
    if textStorage.length < 0 {
      errors.append(ValidationError.invalidTextStorageLength(textStorage.length))
    }

    // Check for null characters or other problematic content
    let string = textStorage.string
    if string.contains("\0") {
      errors.append(ValidationError.textStorageContainsNullCharacter)
    }

    return errors.isEmpty ? nil : errors
  }

  private func validateRangeCacheConsistency(_ rangeCache: [NodeKey: RangeCacheItem], textStorage: NSTextStorage) -> [ValidationError]? {
    var errors: [ValidationError] = []

    for (nodeKey, item) in rangeCache {
      // Validate range bounds
      if item.location < 0 || NSMaxRange(item.range) > textStorage.length {
        errors.append(ValidationError.rangeCacheItemOutOfBounds(nodeKey, item: item, textStorageLength: textStorage.length))
      }

      // Validate lengths are non-negative
      if item.preambleLength < 0 || item.textLength < 0 || item.postambleLength < 0 || item.childrenLength < 0 {
        errors.append(ValidationError.negativeLengthInRangeCache(nodeKey, item: item))
      }
    }

    return errors.isEmpty ? nil : errors
  }


  private func validateFenwickTreeConsistency(_ rangeCache: [NodeKey: RangeCacheItem]) -> [ValidationError]? {
    var errors: [ValidationError] = []

    // Sort range cache items by location to validate sequential consistency
    let sortedItems = rangeCache.values.sorted { $0.location < $1.location }

    // Check that the fenwick tree cumulative lengths match actual positions
    var expectedCumulativeLength = 0
    for (index, item) in sortedItems.enumerated() {
      // Validate that locations are monotonically increasing
      if item.location < expectedCumulativeLength {
        errors.append(.rangeCacheInconsistency("Node at location \(item.location) overlaps with previous content ending at \(expectedCumulativeLength)"))
      }

      // Check fenwick tree consistency if we can map to an index
      let fenwickIndex = max(0, item.location / 100) // Same mapping as getFenwickIndexForNode
      let fenwickSum = fenwickTree.query(index: fenwickIndex)

      // The fenwick sum at this index should roughly correspond to the cumulative text up to this point
      // Allow some tolerance since we're grouping nodes
      let tolerance = 200 // Allow 200 character tolerance due to grouping
      if abs(fenwickSum - item.location) > tolerance && fenwickIndex > 0 {
        errors.append(.fenwickTreeInconsistency("Fenwick tree sum \(fenwickSum) doesn't match expected location \(item.location) at index \(fenwickIndex)"))
      }

      expectedCumulativeLength = item.location + item.range.length
    }

    // Validate total fenwick tree sum matches total text length
    if fenwickTree.treeSize > 0 {
      let totalFenwickSum = fenwickTree.query(index: fenwickTree.treeSize - 1)
      if abs(totalFenwickSum - expectedCumulativeLength) > 100 {
        errors.append(.fenwickTreeInconsistency("Total fenwick sum \(totalFenwickSum) doesn't match total text length \(expectedCumulativeLength)"))
      }
    }

    return errors.isEmpty ? nil : errors
  }

  // MARK: - Helper Methods

  private func getRangeFromDelta(_ delta: ReconcilerDelta) -> NSRange {
    switch delta.type {
    case .textUpdate(_, _, let range):
      return range
    case .nodeInsertion(_, _, let location):
      return NSRange(location: location, length: 0)
    case .nodeDeletion(_, let range):
      return range
    case .attributeChange(_, _, let range):
      return range
    }
  }

  private func isSafeAttribute(key: NSAttributedString.Key, value: Any) -> Bool {
    // Check for potentially unsafe attributes
    // This validates against a whitelist of known safe attributes

    // Allow common safe attributes
    let safeAttributes: Set<NSAttributedString.Key> = [
      .font, .foregroundColor, .backgroundColor, .paragraphStyle,
      .kern, .strikethroughStyle, .underlineStyle, .strokeColor,
      .strokeWidth, .shadow, .textEffect
    ]

    return safeAttributes.contains(key)
  }
}

// MARK: - Result Types

internal enum ValidationResult {
  case valid
  case invalid(errors: [ValidationError])
}

internal enum ValidationError {
  case batchTooLarge(Int)
  case batchTooOld(Date)
  case futureTimestamp(Date, deltaIndex: Int)
  case missingSourceDescription(deltaIndex: Int)
  case rangeOutOfBounds(NSRange, textStorageLength: Int)
  case locationOutOfBounds(Int, textStorageLength: Int)
  case nodeNotFound(NodeKey)
  case nodeAlreadyExists(NodeKey)
  case nodeNotInRangeCache(NodeKey)
  case invalidNodeType(NodeKey, expected: String, actual: String)
  case nodeKeyMismatch(expected: NodeKey, actual: NodeKey)
  case rangeMismatch(expected: NSRange, actual: NSRange, nodeKey: NodeKey)
  case unsafeAttribute(NSAttributedString.Key, value: Any)
  case overlappingDeltas(range1: NSRange, range2: NSRange)
  case invalidTextStorageLength(Int)
  case textStorageContainsNullCharacter
  case rangeCacheItemOutOfBounds(NodeKey, item: RangeCacheItem, textStorageLength: Int)
  case negativeLengthInRangeCache(NodeKey, item: RangeCacheItem)
  case rangeCacheInconsistency(String)
  case fenwickTreeInconsistency(String)
}