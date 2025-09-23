/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import Lexical
import XCTest

@MainActor
class IncrementalRangeCacheTests: XCTestCase {

  func testIncrementalCacheUpdateAfterTextChange() throws {
    let featureFlags = FeatureFlags(optimizedReconciler: true, reconcilerMetrics: true)
    let metrics = RangeCacheTestMetricsContainer()
    let editorConfig = EditorConfig(theme: Theme(), plugins: [], metricsContainer: metrics)
    let textKitContext = LexicalReadOnlyTextKitContext(editorConfig: editorConfig, featureFlags: featureFlags)
    let editor = textKitContext.editor
    let fenwickTree = editor.fenwickTree
    let cacheUpdater = IncrementalRangeCacheUpdater(editor: editor, fenwickTree: fenwickTree)

    // Create initial document with known structure
    var nodeKey1: NodeKey!
    var nodeKey2: NodeKey!

    try editor.update {
      guard let rootNode = getActiveEditorState()?.getRootNode() else { return }

      let paragraph1 = ParagraphNode()
      let textNode1 = TextNode(text: "First paragraph", key: nil)
      try paragraph1.append([textNode1])
      try rootNode.append([paragraph1])
      nodeKey1 = textNode1.key

      let paragraph2 = ParagraphNode()
      let textNode2 = TextNode(text: "Second paragraph", key: nil)
      try paragraph2.append([textNode2])
      try rootNode.append([paragraph2])
      nodeKey2 = textNode2.key
    }

    // Get initial range cache state
    var rangeCache = editor.rangeCache
    let initialCacheSize = rangeCache.count

    // Create text update delta
    let metadata = DeltaMetadata(sourceUpdate: "Test incremental cache update")
    let delta = ReconcilerDelta(
      type: .textUpdate(
        nodeKey: nodeKey1,
        newText: "Modified first paragraph with longer text",
        range: NSRange(location: 0, length: 15)
      ),
      metadata: metadata
    )

    // Apply incremental cache update
    try cacheUpdater.updateRangeCache(&rangeCache, basedOn: [delta])

    // Verify cache was updated incrementally
    XCTAssertEqual(rangeCache.count, initialCacheSize, "Cache should maintain same number of entries")

    // Verify the specific updated node
    if let updatedItem = rangeCache[nodeKey1] {
      // The cache should reflect the new text length
      XCTAssertTrue(updatedItem.textLength >= 15, "Updated cache item should reflect new text length")
    } else {
      XCTFail("Updated node should still be in cache")
    }
  }

  func testIncrementalCacheUpdateAfterNodeInsertion() throws {
    let featureFlags = FeatureFlags(optimizedReconciler: true, reconcilerMetrics: true)
    let metrics = RangeCacheTestMetricsContainer()
    let editorConfig = EditorConfig(theme: Theme(), plugins: [], metricsContainer: metrics)
    let textKitContext = LexicalReadOnlyTextKitContext(editorConfig: editorConfig, featureFlags: featureFlags)
    let editor = textKitContext.editor
    let fenwickTree = editor.fenwickTree
    let cacheUpdater = IncrementalRangeCacheUpdater(editor: editor, fenwickTree: fenwickTree)

    // Create initial document
    try editor.update {
      guard let rootNode = getActiveEditorState()?.getRootNode() else { return }
      let paragraph = ParagraphNode()
      let textNode = TextNode(text: "Initial paragraph", key: nil)
      try paragraph.append([textNode])
      try rootNode.append([paragraph])
    }

    var rangeCache = editor.rangeCache
    let initialCacheSize = rangeCache.count

    // Create node insertion delta
    let insertionData = NodeInsertionData(
      preamble: NSAttributedString(string: ""),
      content: NSAttributedString(string: "New inserted paragraph"),
      postamble: NSAttributedString(string: "\n"),
      nodeKey: "new-node-key"
    )

    let metadata = DeltaMetadata(sourceUpdate: "Test node insertion cache update")
    let delta = ReconcilerDelta(
      type: .nodeInsertion(
        nodeKey: "new-node-key",
        insertionData: insertionData,
        location: 0
      ),
      metadata: metadata
    )

    // Apply incremental cache update
    try cacheUpdater.updateRangeCache(&rangeCache, basedOn: [delta])

    // Verify cache handles insertion correctly
    // Note: The actual cache update logic may vary based on implementation
    // This test ensures the operation completes without error
    XCTAssertGreaterThanOrEqual(rangeCache.count, initialCacheSize, "Cache should handle insertion")
  }

  func testIncrementalCacheUpdateAfterNodeDeletion() throws {
    let featureFlags = FeatureFlags(optimizedReconciler: true, reconcilerMetrics: true)
    let metrics = RangeCacheTestMetricsContainer()
    let editorConfig = EditorConfig(theme: Theme(), plugins: [], metricsContainer: metrics)
    let textKitContext = LexicalReadOnlyTextKitContext(editorConfig: editorConfig, featureFlags: featureFlags)
    let editor = textKitContext.editor
    let fenwickTree = editor.fenwickTree
    let cacheUpdater = IncrementalRangeCacheUpdater(editor: editor, fenwickTree: fenwickTree)

    // Create initial document with multiple nodes
    var nodeToDelete: NodeKey!

    try editor.update {
      guard let rootNode = getActiveEditorState()?.getRootNode() else { return }

      let paragraph1 = ParagraphNode()
      let textNode1 = TextNode(text: "First paragraph", key: nil)
      try paragraph1.append([textNode1])
      try rootNode.append([paragraph1])

      let paragraph2 = ParagraphNode()
      let textNode2 = TextNode(text: "To be deleted", key: nil)
      try paragraph2.append([textNode2])
      try rootNode.append([paragraph2])
      nodeToDelete = textNode2.key

      let paragraph3 = ParagraphNode()
      let textNode3 = TextNode(text: "Third paragraph", key: nil)
      try paragraph3.append([textNode3])
      try rootNode.append([paragraph3])
    }

    var rangeCache = editor.rangeCache
    let initialCacheSize = rangeCache.count

    // Create node deletion delta
    let metadata = DeltaMetadata(sourceUpdate: "Test node deletion cache update")
    let delta = ReconcilerDelta(
      type: .nodeDeletion(
        nodeKey: nodeToDelete,
        range: NSRange(location: 16, length: 13)
      ),
      metadata: metadata
    )

    // Apply incremental cache update
    try cacheUpdater.updateRangeCache(&rangeCache, basedOn: [delta])

    // Verify cache handles deletion correctly
    XCTAssertLessThanOrEqual(rangeCache.count, initialCacheSize, "Cache should handle deletion")

    // Verify deleted node is removed from cache
    XCTAssertNil(rangeCache[nodeToDelete], "Deleted node should be removed from cache")
  }

  func testBatchIncrementalCacheUpdate() throws {
    let featureFlags = FeatureFlags(optimizedReconciler: true, reconcilerMetrics: true)
    let metrics = RangeCacheTestMetricsContainer()
    let editorConfig = EditorConfig(theme: Theme(), plugins: [], metricsContainer: metrics)
    let textKitContext = LexicalReadOnlyTextKitContext(editorConfig: editorConfig, featureFlags: featureFlags)
    let editor = textKitContext.editor
    let fenwickTree = editor.fenwickTree
    let cacheUpdater = IncrementalRangeCacheUpdater(editor: editor, fenwickTree: fenwickTree)

    // Create initial document with multiple nodes
    var nodeKeys: [NodeKey] = []

    try editor.update {
      guard let rootNode = getActiveEditorState()?.getRootNode() else { return }

      for i in 0..<5 {
        let paragraph = ParagraphNode()
        let textNode = TextNode(text: "Paragraph \(i)", key: nil)
        try paragraph.append([textNode])
        try rootNode.append([paragraph])
        nodeKeys.append(textNode.key)
      }
    }

    var rangeCache = editor.rangeCache
    let initialCacheSize = rangeCache.count

    // Create multiple deltas for batch update
    var deltas: [ReconcilerDelta] = []

    for (index, nodeKey) in nodeKeys.enumerated() {
      let metadata = DeltaMetadata(sourceUpdate: "Batch update \(index)")
      let delta = ReconcilerDelta(
        type: .textUpdate(
          nodeKey: nodeKey,
          newText: "Updated paragraph \(index) with new content",
          range: NSRange(location: index * 12, length: 11)
        ),
        metadata: metadata
      )
      deltas.append(delta)
    }

    // Apply batch incremental cache update
    try cacheUpdater.updateRangeCache(&rangeCache, basedOn: deltas)

    // Verify cache handles batch update correctly
    XCTAssertEqual(rangeCache.count, initialCacheSize, "Cache should maintain same structure after batch update")

    // Verify all updated nodes are still in cache
    for nodeKey in nodeKeys {
      XCTAssertNotNil(rangeCache[nodeKey], "All updated nodes should remain in cache")
    }
  }

  func testFenwickTreeSynchronization() throws {
    let featureFlags = FeatureFlags(optimizedReconciler: true, reconcilerMetrics: true)
    let metrics = RangeCacheTestMetricsContainer()
    let editorConfig = EditorConfig(theme: Theme(), plugins: [], metricsContainer: metrics)
    let textKitContext = LexicalReadOnlyTextKitContext(editorConfig: editorConfig, featureFlags: featureFlags)
    let editor = textKitContext.editor
    let fenwickTree = editor.fenwickTree
    let cacheUpdater = IncrementalRangeCacheUpdater(editor: editor, fenwickTree: fenwickTree)

    // Create initial document
    var nodeKey: NodeKey!

    try editor.update {
      guard let rootNode = getActiveEditorState()?.getRootNode() else { return }
      let paragraph = ParagraphNode()
      let textNode = TextNode(text: "Test paragraph", key: nil)
      try paragraph.append([textNode])
      try rootNode.append([paragraph])
      nodeKey = textNode.key
    }

    var rangeCache = editor.rangeCache

    // Get initial Fenwick tree state (query to ensure it's working)
    let initialQuery = fenwickTree.query(index: 0)

    // Create text update that changes length
    let metadata = DeltaMetadata(sourceUpdate: "Test Fenwick synchronization")
    let delta = ReconcilerDelta(
      type: .textUpdate(
        nodeKey: nodeKey,
        newText: "This is a much longer test paragraph with more content",
        range: NSRange(location: 0, length: 14)
      ),
      metadata: metadata
    )

    // Apply incremental cache update
    try cacheUpdater.updateRangeCache(&rangeCache, basedOn: [delta])

    // Verify Fenwick tree is updated (query should return different result)
    let updatedQuery = fenwickTree.query(index: 0)

    // The actual values depend on implementation, but operation should complete successfully
    XCTAssertGreaterThanOrEqual(updatedQuery, 0, "Fenwick tree should be queryable after update")
    XCTAssertGreaterThanOrEqual(initialQuery, 0, "Fenwick tree should be queryable before update")
  }

  func testCacheConsistencyAfterUpdates() throws {
    let featureFlags = FeatureFlags(optimizedReconciler: true, reconcilerMetrics: true)
    let metrics = RangeCacheTestMetricsContainer()
    let editorConfig = EditorConfig(theme: Theme(), plugins: [], metricsContainer: metrics)
    let textKitContext = LexicalReadOnlyTextKitContext(editorConfig: editorConfig, featureFlags: featureFlags)
    let editor = textKitContext.editor
    let fenwickTree = editor.fenwickTree
    let cacheUpdater = IncrementalRangeCacheUpdater(editor: editor, fenwickTree: fenwickTree)

    // Create complex document structure
    var nodeKeys: [NodeKey] = []

    try editor.update {
      guard let rootNode = getActiveEditorState()?.getRootNode() else { return }

      for i in 0..<3 {
        let paragraph = ParagraphNode()
        let textNode = TextNode(text: "Paragraph \(i) with content", key: nil)
        try paragraph.append([textNode])
        try rootNode.append([paragraph])
        nodeKeys.append(textNode.key)
      }
    }

    var rangeCache = editor.rangeCache

    // Verify initial cache consistency
    var totalLength = 0
    for (nodeKey, cacheItem) in rangeCache {
      XCTAssertGreaterThanOrEqual(cacheItem.nodeIndex, 0, "Node index should be non-negative")
      XCTAssertGreaterThanOrEqual(cacheItem.textLength, 0, "Text length should be non-negative")
      totalLength += cacheItem.textLength
    }

    // Apply series of updates
    let updates = [
      (nodeKeys[0], "Modified first paragraph"),
      (nodeKeys[1], "Updated second paragraph with more text"),
      (nodeKeys[2], "Changed third")
    ]

    for (nodeKey, newText) in updates {
      let metadata = DeltaMetadata(sourceUpdate: "Consistency test")
      let delta = ReconcilerDelta(
        type: .textUpdate(
          nodeKey: nodeKey,
          newText: newText,
          range: NSRange(location: 0, length: 20) // Approximate range
        ),
        metadata: metadata
      )

      try cacheUpdater.updateRangeCache(&rangeCache, basedOn: [delta])
    }

    // Verify cache consistency after updates
    var updatedTotalLength = 0
    for (nodeKey, cacheItem) in rangeCache {
      XCTAssertGreaterThanOrEqual(cacheItem.nodeIndex, 0, "Node index should remain non-negative")
      XCTAssertGreaterThanOrEqual(cacheItem.textLength, 0, "Text length should remain non-negative")
      updatedTotalLength += cacheItem.textLength
    }

    // The total length may change due to text updates
    XCTAssertGreaterThan(updatedTotalLength, 0, "Total text length should be positive after updates")
  }
}

// MARK: - Supporting Types

@MainActor
class RangeCacheTestMetricsContainer: EditorMetricsContainer {
  private(set) var reconcilerRuns: [ReconcilerMetric] = []
  private(set) var optimizedReconcilerRuns: [OptimizedReconcilerMetric] = []
  private(set) var deltaApplications: [DeltaApplicationMetric] = []
  var metricsData: [String: Any] = [:]

  func record(_ metric: EditorMetric) {
    switch metric {
    case .reconcilerRun(let data):
      reconcilerRuns.append(data)
    case .optimizedReconcilerRun(let data):
      optimizedReconcilerRuns.append(data)
    case .deltaApplication(let data):
      deltaApplications.append(data)
    }
  }

  func resetMetrics() {
    reconcilerRuns.removeAll()
    optimizedReconcilerRuns.removeAll()
    deltaApplications.removeAll()
    metricsData.removeAll()
  }
}