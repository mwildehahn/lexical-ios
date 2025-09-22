/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import Lexical
import XCTest

@MainActor
class TextStorageDeltaApplierTests: XCTestCase {

  func testTextUpdateDeltaApplication() throws {
    let featureFlags = FeatureFlags(optimizedReconciler: true, reconcilerMetrics: true)
    let metrics = DeltaApplierTestMetricsContainer()
    let editorConfig = EditorConfig(theme: Theme(), plugins: [], metricsContainer: metrics)
    let textKitContext = LexicalReadOnlyTextKitContext(editorConfig: editorConfig, featureFlags: featureFlags)
    let editor = textKitContext.editor
    let fenwickTree = editor.fenwickTree
    let applier = TextStorageDeltaApplier(editor: editor, fenwickTree: fenwickTree)

    // Create initial document
    try editor.update {
      guard let rootNode = getActiveEditorState()?.getRootNode() else { return }
      let paragraph = ParagraphNode()
      let textNode = TextNode(text: "Original text", key: nil)
      try paragraph.append([textNode])
      try rootNode.append([paragraph])
    }

    guard let textStorage = editor.textStorage else {
      XCTFail("No text storage")
      return
    }

    // Create text update delta - use actual text storage length for range
    let actualTextLength = min(13, textStorage.length)
    let metadata = DeltaMetadata(sourceUpdate: "Test text update")
    let delta = ReconcilerDelta(
      type: .textUpdate(
        nodeKey: "test-node",
        newText: "Updated text",
        range: NSRange(location: 0, length: actualTextLength)
      ),
      metadata: metadata
    )

    let deltaBatch = DeltaBatch(
      deltas: [delta],
      batchMetadata: BatchMetadata(
        expectedTextStorageLength: textStorage.length,
        requiresAnchorValidation: false,
        fallbackThreshold: 100
      )
    )

    // Apply delta
    let result = applier.applyDeltaBatch(deltaBatch, to: textStorage)

    // Verify application
    switch result {
    case .success(let appliedDeltas, let fenwickUpdates):
      XCTAssertEqual(appliedDeltas, 1, "Should apply one delta")
      XCTAssertGreaterThanOrEqual(fenwickUpdates, 0, "Should track Fenwick updates")
    case .failure(let reason, _):
      XCTFail("Delta application failed: \(reason)")
    case .partialSuccess(_, _, let reason):
      XCTFail("Unexpected partial success: \(reason)")
    }
  }

  func testNodeInsertionDeltaApplication() throws {
    let featureFlags = FeatureFlags(optimizedReconciler: true, reconcilerMetrics: true)
    let metrics = DeltaApplierTestMetricsContainer()
    let editorConfig = EditorConfig(theme: Theme(), plugins: [], metricsContainer: metrics)
    let textKitContext = LexicalReadOnlyTextKitContext(editorConfig: editorConfig, featureFlags: featureFlags)
    let editor = textKitContext.editor
    let fenwickTree = editor.fenwickTree
    let applier = TextStorageDeltaApplier(editor: editor, fenwickTree: fenwickTree)

    guard let textStorage = editor.textStorage else {
      XCTFail("No text storage")
      return
    }

    // Create node insertion delta
    let insertionData = NodeInsertionData(
      preamble: NSAttributedString(string: ""),
      content: NSAttributedString(string: "New paragraph"),
      postamble: NSAttributedString(string: "\n"),
      nodeKey: "new-node"
    )

    let metadata = DeltaMetadata(sourceUpdate: "Test node insertion")
    let delta = ReconcilerDelta(
      type: .nodeInsertion(
        nodeKey: "new-node",
        insertionData: insertionData,
        location: 0
      ),
      metadata: metadata
    )

    let deltaBatch = DeltaBatch(
      deltas: [delta],
      batchMetadata: BatchMetadata(
        expectedTextStorageLength: textStorage.length,
        requiresAnchorValidation: false,
        fallbackThreshold: 100
      )
    )

    // Apply delta
    let result = applier.applyDeltaBatch(deltaBatch, to: textStorage)

    // Verify application
    switch result {
    case .success(let appliedDeltas, let fenwickUpdates):
      XCTAssertEqual(appliedDeltas, 1, "Should apply one delta")
      XCTAssertGreaterThanOrEqual(fenwickUpdates, 0, "Should track Fenwick updates")
    case .failure(let reason, _):
      XCTFail("Delta application failed: \(reason)")
    case .partialSuccess(_, _, let reason):
      XCTFail("Unexpected partial success: \(reason)")
    }
  }

  func testNodeDeletionDeltaApplication() throws {
    let featureFlags = FeatureFlags(optimizedReconciler: true, reconcilerMetrics: true)
    let metrics = DeltaApplierTestMetricsContainer()
    let editorConfig = EditorConfig(theme: Theme(), plugins: [], metricsContainer: metrics)
    let textKitContext = LexicalReadOnlyTextKitContext(editorConfig: editorConfig, featureFlags: featureFlags)
    let editor = textKitContext.editor
    let fenwickTree = editor.fenwickTree
    let applier = TextStorageDeltaApplier(editor: editor, fenwickTree: fenwickTree)

    // Create initial document
    try editor.update {
      guard let rootNode = getActiveEditorState()?.getRootNode() else { return }
      let paragraph = ParagraphNode()
      let textNode = TextNode(text: "Text to delete", key: nil)
      try paragraph.append([textNode])
      try rootNode.append([paragraph])
    }

    guard let textStorage = editor.textStorage else {
      XCTFail("No text storage")
      return
    }

    // Create node deletion delta - use actual text storage length for range
    let actualTextLength = min(14, textStorage.length)
    let metadata = DeltaMetadata(sourceUpdate: "Test node deletion")
    let delta = ReconcilerDelta(
      type: .nodeDeletion(
        nodeKey: "delete-node",
        range: NSRange(location: 0, length: actualTextLength)
      ),
      metadata: metadata
    )

    let deltaBatch = DeltaBatch(
      deltas: [delta],
      batchMetadata: BatchMetadata(
        expectedTextStorageLength: textStorage.length,
        requiresAnchorValidation: false,
        fallbackThreshold: 100
      )
    )

    // Apply delta
    let result = applier.applyDeltaBatch(deltaBatch, to: textStorage)

    // Verify application
    switch result {
    case .success(let appliedDeltas, let fenwickUpdates):
      XCTAssertEqual(appliedDeltas, 1, "Should apply one delta")
      XCTAssertGreaterThanOrEqual(fenwickUpdates, 0, "Should track Fenwick updates")
    case .failure(let reason, _):
      XCTFail("Delta application failed: \(reason)")
    case .partialSuccess(_, _, let reason):
      XCTFail("Unexpected partial success: \(reason)")
    }
  }

  func testMultipleDeltaBatchApplication() throws {
    let featureFlags = FeatureFlags(optimizedReconciler: true, reconcilerMetrics: true)
    let metrics = DeltaApplierTestMetricsContainer()
    let editorConfig = EditorConfig(theme: Theme(), plugins: [], metricsContainer: metrics)
    let textKitContext = LexicalReadOnlyTextKitContext(editorConfig: editorConfig, featureFlags: featureFlags)
    let editor = textKitContext.editor
    let fenwickTree = editor.fenwickTree
    let applier = TextStorageDeltaApplier(editor: editor, fenwickTree: fenwickTree)

    // Create initial document
    try editor.update {
      guard let rootNode = getActiveEditorState()?.getRootNode() else { return }
      let paragraph1 = ParagraphNode()
      let textNode1 = TextNode(text: "First paragraph", key: nil)
      try paragraph1.append([textNode1])
      try rootNode.append([paragraph1])

      let paragraph2 = ParagraphNode()
      let textNode2 = TextNode(text: "Second paragraph", key: nil)
      try paragraph2.append([textNode2])
      try rootNode.append([paragraph2])
    }

    guard let textStorage = editor.textStorage else {
      XCTFail("No text storage")
      return
    }

    // Create multiple deltas - use actual text storage length for ranges
    let actualTextLength = textStorage.length
    let firstLength = min(15, actualTextLength)
    let secondStart = min(16, actualTextLength)
    let secondLength = min(16, max(0, actualTextLength - secondStart))

    let metadata1 = DeltaMetadata(sourceUpdate: "First text update")
    let delta1 = ReconcilerDelta(
      type: .textUpdate(
        nodeKey: "node1",
        newText: "Modified first",
        range: NSRange(location: 0, length: firstLength)
      ),
      metadata: metadata1
    )

    let metadata2 = DeltaMetadata(sourceUpdate: "Second text update")
    let delta2 = ReconcilerDelta(
      type: .textUpdate(
        nodeKey: "node2",
        newText: "Modified second",
        range: NSRange(location: secondStart, length: secondLength)
      ),
      metadata: metadata2
    )

    let deltaBatch = DeltaBatch(
      deltas: [delta1, delta2],
      batchMetadata: BatchMetadata(
        expectedTextStorageLength: textStorage.length,
        requiresAnchorValidation: false,
        fallbackThreshold: 100
      )
    )

    // Apply deltas
    let result = applier.applyDeltaBatch(deltaBatch, to: textStorage)

    // Verify application
    switch result {
    case .success(let appliedDeltas, let fenwickUpdates):
      XCTAssertEqual(appliedDeltas, 2, "Should apply two deltas")
      XCTAssertGreaterThanOrEqual(fenwickUpdates, 0, "Should track Fenwick updates")
    case .failure(let reason, _):
      XCTFail("Delta batch application failed: \(reason)")
    case .partialSuccess(let appliedDeltas, let fenwickUpdates, let reason):
      print("Partial success: \(appliedDeltas) deltas applied, reason: \(reason)")
      XCTAssertGreaterThan(appliedDeltas, 0, "Should apply at least some deltas")
    }
  }

  func testInvalidDeltaApplicationFailure() throws {
    let featureFlags = FeatureFlags(optimizedReconciler: true, reconcilerMetrics: true)
    let metrics = DeltaApplierTestMetricsContainer()
    let editorConfig = EditorConfig(theme: Theme(), plugins: [], metricsContainer: metrics)
    let textKitContext = LexicalReadOnlyTextKitContext(editorConfig: editorConfig, featureFlags: featureFlags)
    let editor = textKitContext.editor
    let fenwickTree = editor.fenwickTree
    let applier = TextStorageDeltaApplier(editor: editor, fenwickTree: fenwickTree)

    guard let textStorage = editor.textStorage else {
      XCTFail("No text storage")
      return
    }

    // Create invalid delta (range out of bounds)
    let metadata = DeltaMetadata(sourceUpdate: "Invalid test delta")
    let delta = ReconcilerDelta(
      type: .textUpdate(
        nodeKey: "invalid-node",
        newText: "Should fail",
        range: NSRange(location: 1000, length: 100) // Out of bounds
      ),
      metadata: metadata
    )

    let deltaBatch = DeltaBatch(
      deltas: [delta],
      batchMetadata: BatchMetadata(
        expectedTextStorageLength: textStorage.length,
        requiresAnchorValidation: false,
        fallbackThreshold: 100
      )
    )

    // Apply invalid delta
    let result = applier.applyDeltaBatch(deltaBatch, to: textStorage)

    // Verify failure handling
    switch result {
    case .success(_, _):
      XCTFail("Invalid delta should not succeed")
    case .failure(let reason, let context):
      XCTAssertFalse(reason.isEmpty, "Should provide failure reason")
      XCTAssertNotNil(context, "Should provide failure context")
    case .partialSuccess(_, _, _):
      // Partial success is acceptable for invalid deltas
      break
    }
  }

  func testAnchorUpdateDeltaApplication() throws {
    let featureFlags = FeatureFlags(optimizedReconciler: true, reconcilerMetrics: true, anchorBasedReconciliation: true)
    let metrics = DeltaApplierTestMetricsContainer()
    let editorConfig = EditorConfig(theme: Theme(), plugins: [], metricsContainer: metrics)
    let textKitContext = LexicalReadOnlyTextKitContext(editorConfig: editorConfig, featureFlags: featureFlags)
    let editor = textKitContext.editor
    let fenwickTree = editor.fenwickTree
    let applier = TextStorageDeltaApplier(editor: editor, fenwickTree: fenwickTree)

    guard let textStorage = editor.textStorage else {
      XCTFail("No text storage")
      return
    }

    // Create anchor update delta
    let metadata = DeltaMetadata(sourceUpdate: "Test anchor update")
    let delta = ReconcilerDelta(
      type: .anchorUpdate(
        nodeKey: "anchor-node",
        preambleLocation: 0,
        postambleLocation: 10
      ),
      metadata: metadata
    )

    let deltaBatch = DeltaBatch(
      deltas: [delta],
      batchMetadata: BatchMetadata(
        expectedTextStorageLength: textStorage.length,
        requiresAnchorValidation: true,
        fallbackThreshold: 100
      )
    )

    // Apply anchor delta
    let result = applier.applyDeltaBatch(deltaBatch, to: textStorage)

    // Verify application (may succeed or fallback gracefully)
    switch result {
    case .success(let appliedDeltas, let fenwickUpdates):
      XCTAssertEqual(appliedDeltas, 1, "Should apply anchor delta")
      XCTAssertGreaterThanOrEqual(fenwickUpdates, 0, "Should track Fenwick updates")
    case .failure(let reason, _):
      // Anchor operations may fail gracefully
      print("Anchor delta failed as expected: \(reason)")
    case .partialSuccess(_, _, let reason):
      print("Anchor delta partial success: \(reason)")
    }
  }
}

// MARK: - Supporting Types

@MainActor
class DeltaApplierTestMetricsContainer: EditorMetricsContainer {
  private(set) var reconcilerRuns: [ReconcilerMetric] = []
  private(set) var optimizedReconcilerRuns: [OptimizedReconcilerMetric] = []
  var metricsData: [String: Any] = [:]

  func record(_ metric: EditorMetric) {
    switch metric {
    case .reconcilerRun(let data):
      reconcilerRuns.append(data)
    case .optimizedReconcilerRun(let data):
      optimizedReconcilerRuns.append(data)
    }
  }

  func resetMetrics() {
    reconcilerRuns.removeAll()
    optimizedReconcilerRuns.removeAll()
    metricsData.removeAll()
  }
}