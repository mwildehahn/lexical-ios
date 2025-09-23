/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Represents different types of changes that can be applied to TextStorage
public enum ReconcilerDeltaType {
  case textUpdate(nodeKey: NodeKey, newText: String, range: NSRange)
  case nodeInsertion(nodeKey: NodeKey, insertionData: NodeInsertionData, location: Int)
  case nodeDeletion(nodeKey: NodeKey, range: NSRange)
  case attributeChange(nodeKey: NodeKey, attributes: [NSAttributedString.Key: Any], range: NSRange)
}

/// Data needed to insert a node
public struct NodeInsertionData {
  let preamble: NSAttributedString
  let content: NSAttributedString
  let postamble: NSAttributedString
  let nodeKey: NodeKey

  public init(preamble: NSAttributedString, content: NSAttributedString, postamble: NSAttributedString, nodeKey: NodeKey) {
    self.preamble = preamble
    self.content = content
    self.postamble = postamble
    self.nodeKey = nodeKey
  }
}

/// A delta representing a specific change to be applied to TextStorage
public struct ReconcilerDelta {
  let type: ReconcilerDeltaType
  let metadata: DeltaMetadata

  public init(type: ReconcilerDeltaType, metadata: DeltaMetadata) {
    self.type = type
    self.metadata = metadata
  }
}

/// Metadata associated with a delta for validation and debugging
public struct DeltaMetadata {
  let timestamp: Date
  let sourceUpdate: String // Description of what caused this delta
  let fenwickTreeIndex: Int? // Index in FenwickTree if applicable
  let originalRange: NSRange? // Original range before transformation

  public init(
    timestamp: Date = Date(),
    sourceUpdate: String,
    fenwickTreeIndex: Int? = nil,
    originalRange: NSRange? = nil
  ) {
    self.timestamp = timestamp
    self.sourceUpdate = sourceUpdate
    self.fenwickTreeIndex = fenwickTreeIndex
    self.originalRange = originalRange
  }
}

/// Collection of deltas to be applied together
public struct DeltaBatch {
  let deltas: [ReconcilerDelta]
  let batchMetadata: BatchMetadata

  public init(deltas: [ReconcilerDelta], batchMetadata: BatchMetadata) {
    self.deltas = deltas
    self.batchMetadata = batchMetadata
  }
}

/// Metadata for a batch of deltas
public struct BatchMetadata {
  let batchId: String
  let timestamp: Date
  let expectedTextStorageLength: Int
  let isFreshDocument: Bool

  public init(
    batchId: String = UUID().uuidString,
    timestamp: Date = Date(),
    expectedTextStorageLength: Int,
    isFreshDocument: Bool = false
  ) {
    self.batchId = batchId
    self.timestamp = timestamp
    self.expectedTextStorageLength = expectedTextStorageLength
    self.isFreshDocument = isFreshDocument
  }
}

/// Result of applying a delta batch
public enum DeltaApplicationResult {
  case success(appliedDeltas: Int, fenwickTreeUpdates: Int)
  case partialSuccess(appliedDeltas: Int, failedDeltas: [ReconcilerDelta], reason: String)
  case failure(reason: String)
}