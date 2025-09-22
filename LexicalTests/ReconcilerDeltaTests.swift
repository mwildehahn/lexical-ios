/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import Lexical
import XCTest

@MainActor
class ReconcilerDeltaTests: XCTestCase {

  // MARK: - Delta Type Tests

  func testTextUpdateDelta() {
    let nodeKey = "test-node-1"
    let newText = "Updated text content"
    let range = NSRange(location: 10, length: 5)

    let metadata = DeltaMetadata(sourceUpdate: "User edit")
    let deltaType = ReconcilerDeltaType.textUpdate(nodeKey: nodeKey, newText: newText, range: range)
    let delta = ReconcilerDelta(type: deltaType, metadata: metadata)

    // Verify delta properties
    if case .textUpdate(let key, let text, let deltaRange) = delta.type {
      XCTAssertEqual(key, nodeKey)
      XCTAssertEqual(text, newText)
      XCTAssertEqual(deltaRange, range)
    } else {
      XCTFail("Delta type should be textUpdate")
    }

    XCTAssertEqual(delta.metadata.sourceUpdate, "User edit")
  }

  func testNodeInsertionDelta() {
    let nodeKey = "new-node-1"
    let insertionData = NodeInsertionData(
      preamble: NSAttributedString(string: "<p>"),
      content: NSAttributedString(string: "New paragraph"),
      postamble: NSAttributedString(string: "</p>"),
      nodeKey: nodeKey
    )
    let location = 20

    let metadata = DeltaMetadata(sourceUpdate: "Node insertion")
    let deltaType = ReconcilerDeltaType.nodeInsertion(nodeKey: nodeKey, insertionData: insertionData, location: location)
    let delta = ReconcilerDelta(type: deltaType, metadata: metadata)

    // Verify delta properties
    if case .nodeInsertion(let key, let data, let loc) = delta.type {
      XCTAssertEqual(key, nodeKey)
      XCTAssertEqual(data.nodeKey, nodeKey)
      XCTAssertEqual(data.content.string, "New paragraph")
      XCTAssertEqual(loc, location)
    } else {
      XCTFail("Delta type should be nodeInsertion")
    }
  }

  func testNodeDeletionDelta() {
    let nodeKey = "delete-node-1"
    let range = NSRange(location: 50, length: 25)

    let metadata = DeltaMetadata(sourceUpdate: "Node deletion")
    let deltaType = ReconcilerDeltaType.nodeDeletion(nodeKey: nodeKey, range: range)
    let delta = ReconcilerDelta(type: deltaType, metadata: metadata)

    // Verify delta properties
    if case .nodeDeletion(let key, let deltaRange) = delta.type {
      XCTAssertEqual(key, nodeKey)
      XCTAssertEqual(deltaRange, range)
    } else {
      XCTFail("Delta type should be nodeDeletion")
    }
  }

  func testAttributeChangeDelta() {
    let nodeKey = "attr-node-1"
    let attributes: [NSAttributedString.Key: Any] = [
      .font: UIFont.boldSystemFont(ofSize: 16),
      .foregroundColor: UIColor.red
    ]
    let range = NSRange(location: 30, length: 10)

    let metadata = DeltaMetadata(sourceUpdate: "Style change")
    let deltaType = ReconcilerDeltaType.attributeChange(nodeKey: nodeKey, attributes: attributes, range: range)
    let delta = ReconcilerDelta(type: deltaType, metadata: metadata)

    // Verify delta properties
    if case .attributeChange(let key, let attrs, let deltaRange) = delta.type {
      XCTAssertEqual(key, nodeKey)
      XCTAssertEqual(attrs.count, 2)
      XCTAssertEqual(deltaRange, range)
    } else {
      XCTFail("Delta type should be attributeChange")
    }
  }

  func testAnchorUpdateDelta() {
    let nodeKey = "anchor-node-1"
    let preambleLocation = 15
    let postambleLocation = 45

    let metadata = DeltaMetadata(sourceUpdate: "Anchor update")
    let deltaType = ReconcilerDeltaType.anchorUpdate(nodeKey: nodeKey, preambleLocation: preambleLocation, postambleLocation: postambleLocation)
    let delta = ReconcilerDelta(type: deltaType, metadata: metadata)

    // Verify delta properties
    if case .anchorUpdate(let key, let preamble, let postamble) = delta.type {
      XCTAssertEqual(key, nodeKey)
      XCTAssertEqual(preamble, preambleLocation)
      XCTAssertEqual(postamble, postambleLocation)
    } else {
      XCTFail("Delta type should be anchorUpdate")
    }
  }

  // MARK: - Delta Batch Tests

  func testDeltaBatchCreation() {
    let deltas = [
      ReconcilerDelta(
        type: .textUpdate(nodeKey: "node1", newText: "text", range: NSRange(location: 0, length: 4)),
        metadata: DeltaMetadata(sourceUpdate: "edit1")
      ),
      ReconcilerDelta(
        type: .nodeInsertion(
          nodeKey: "node2",
          insertionData: NodeInsertionData(
            preamble: NSAttributedString(string: ""),
            content: NSAttributedString(string: "new"),
            postamble: NSAttributedString(string: ""),
            nodeKey: "node2"
          ),
          location: 10
        ),
        metadata: DeltaMetadata(sourceUpdate: "insertion1")
      )
    ]

    let batchMetadata = BatchMetadata(
      expectedTextStorageLength: 100,
      requiresAnchorValidation: true,
      fallbackThreshold: 50
    )

    let batch = DeltaBatch(deltas: deltas, batchMetadata: batchMetadata)

    XCTAssertEqual(batch.deltas.count, 2)
    XCTAssertEqual(batch.batchMetadata.expectedTextStorageLength, 100)
    XCTAssertTrue(batch.batchMetadata.requiresAnchorValidation)
    XCTAssertEqual(batch.batchMetadata.fallbackThreshold, 50)
  }

  // MARK: - Metadata Tests

  func testDeltaMetadata() {
    let timestamp = Date()
    let sourceUpdate = "Test update"
    let fenwickIndex = 5
    let originalRange = NSRange(location: 20, length: 30)

    let metadata = DeltaMetadata(
      timestamp: timestamp,
      sourceUpdate: sourceUpdate,
      fenwickTreeIndex: fenwickIndex,
      originalRange: originalRange
    )

    XCTAssertEqual(metadata.timestamp, timestamp)
    XCTAssertEqual(metadata.sourceUpdate, sourceUpdate)
    XCTAssertEqual(metadata.fenwickTreeIndex, fenwickIndex)
    XCTAssertEqual(metadata.originalRange, originalRange)
  }

  func testBatchMetadata() {
    let batchId = "test-batch-123"
    let timestamp = Date()
    let expectedLength = 500
    let requiresValidation = false
    let threshold = 75

    let metadata = BatchMetadata(
      batchId: batchId,
      timestamp: timestamp,
      expectedTextStorageLength: expectedLength,
      requiresAnchorValidation: requiresValidation,
      fallbackThreshold: threshold
    )

    XCTAssertEqual(metadata.batchId, batchId)
    XCTAssertEqual(metadata.timestamp, timestamp)
    XCTAssertEqual(metadata.expectedTextStorageLength, expectedLength)
    XCTAssertFalse(metadata.requiresAnchorValidation)
    XCTAssertEqual(metadata.fallbackThreshold, threshold)
  }

  // MARK: - Application Result Tests

  func testDeltaApplicationResults() {
    // Test success result
    let successResult = DeltaApplicationResult.success(appliedDeltas: 5, fenwickTreeUpdates: 3)
    if case .success(let applied, let updates) = successResult {
      XCTAssertEqual(applied, 5)
      XCTAssertEqual(updates, 3)
    } else {
      XCTFail("Should be success result")
    }

    // Test partial success result
    let failedDelta = ReconcilerDelta(
      type: .textUpdate(nodeKey: "failed", newText: "fail", range: NSRange(location: 0, length: 4)),
      metadata: DeltaMetadata(sourceUpdate: "failed update")
    )
    let partialResult = DeltaApplicationResult.partialSuccess(
      appliedDeltas: 3,
      failedDeltas: [failedDelta],
      reason: "Some deltas failed"
    )

    if case .partialSuccess(let applied, let failed, let reason) = partialResult {
      XCTAssertEqual(applied, 3)
      XCTAssertEqual(failed.count, 1)
      XCTAssertEqual(reason, "Some deltas failed")
    } else {
      XCTFail("Should be partial success result")
    }

    // Test failure result
    let failureResult = DeltaApplicationResult.failure(reason: "Critical error", shouldFallback: true)
    if case .failure(let reason, let shouldFallback) = failureResult {
      XCTAssertEqual(reason, "Critical error")
      XCTAssertTrue(shouldFallback)
    } else {
      XCTFail("Should be failure result")
    }
  }

  // MARK: - NodeInsertionData Tests

  func testNodeInsertionData() {
    let nodeKey = "insertion-test"
    let preamble = NSAttributedString(string: "<div>")
    let content = NSAttributedString(string: "Content here")
    let postamble = NSAttributedString(string: "</div>")

    let insertionData = NodeInsertionData(
      preamble: preamble,
      content: content,
      postamble: postamble,
      nodeKey: nodeKey
    )

    XCTAssertEqual(insertionData.preamble.string, "<div>")
    XCTAssertEqual(insertionData.content.string, "Content here")
    XCTAssertEqual(insertionData.postamble.string, "</div>")
    XCTAssertEqual(insertionData.nodeKey, nodeKey)
  }

  // MARK: - Edge Case Tests

  func testEmptyDeltaBatch() {
    let batchMetadata = BatchMetadata(expectedTextStorageLength: 0)
    let batch = DeltaBatch(deltas: [], batchMetadata: batchMetadata)

    XCTAssertTrue(batch.deltas.isEmpty)
    XCTAssertEqual(batch.batchMetadata.expectedTextStorageLength, 0)
  }

  func testDeltaWithEmptyText() {
    let deltaType = ReconcilerDeltaType.textUpdate(
      nodeKey: "empty-text",
      newText: "",
      range: NSRange(location: 10, length: 5)
    )
    let metadata = DeltaMetadata(sourceUpdate: "Empty text update")
    let delta = ReconcilerDelta(type: deltaType, metadata: metadata)

    if case .textUpdate(_, let text, _) = delta.type {
      XCTAssertTrue(text.isEmpty)
    } else {
      XCTFail("Should be textUpdate delta")
    }
  }

  func testDeltaWithZeroRange() {
    let deltaType = ReconcilerDeltaType.textUpdate(
      nodeKey: "zero-range",
      newText: "inserted",
      range: NSRange(location: 20, length: 0)
    )
    let metadata = DeltaMetadata(sourceUpdate: "Text insertion")
    let delta = ReconcilerDelta(type: deltaType, metadata: metadata)

    if case .textUpdate(_, _, let range) = delta.type {
      XCTAssertEqual(range.length, 0)
      XCTAssertEqual(range.location, 20)
    } else {
      XCTFail("Should be textUpdate delta")
    }
  }
}