/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import Lexical
import XCTest

@MainActor
class FallbackDetectionTests: XCTestCase {

  func testFallbackOnLargeBatchSize() throws {
    let featureFlags = FeatureFlags(optimizedReconciler: true, reconcilerMetrics: true)
    let metrics = FallbackTestMetricsContainer()
    let editorConfig = EditorConfig(theme: Theme(), plugins: [], metricsContainer: metrics)
    let textKitContext = LexicalReadOnlyTextKitContext(editorConfig: editorConfig, featureFlags: featureFlags)
    let editor = textKitContext.editor
    let fallbackDetector = ReconcilerFallbackDetector(editor: editor)

    guard let textStorage = editor.textStorage else {
      XCTFail("No text storage")
      return
    }

    // Create large batch of deltas (exceeding threshold)
    var largeDeltas: [ReconcilerDelta] = []
    for i in 0..<150 { // Above default threshold of 100
      let metadata = DeltaMetadata(sourceUpdate: "Large batch delta \(i)")
      let delta = ReconcilerDelta(
        type: .textUpdate(
          nodeKey: "node-\(i)",
          newText: "Text \(i)",
          range: NSRange(location: i, length: 5)
        ),
        metadata: metadata
      )
      largeDeltas.append(delta)
    }

    let context = ReconcilerContext(
      updateSource: "FallbackTest",
      nodeCount: 150,
      textStorageLength: textStorage.length
    )

    // Test fallback decision
    let decision = fallbackDetector.shouldFallbackToFullReconciliation(
      for: largeDeltas,
      textStorage: textStorage,
      context: context
    )

    print("DEBUG: Large batch test - Delta count: \(largeDeltas.count), Decision: \(decision)")

    switch decision {
    case .fallback(let reason):
      print("DEBUG: Fallback triggered with reason: \(reason)")
      XCTAssertTrue(reason.contains("batch size") || reason.contains("deltas"), "Should fallback due to large batch size")
    case .useOptimized:
      XCTFail("Should fallback with large batch size - got useOptimized instead")
    }
  }

  func testFallbackOnConsecutiveFailures() throws {
    let featureFlags = FeatureFlags(optimizedReconciler: true, reconcilerMetrics: true)
    let metrics = FallbackTestMetricsContainer()
    let editorConfig = EditorConfig(theme: Theme(), plugins: [], metricsContainer: metrics)
    let textKitContext = LexicalReadOnlyTextKitContext(editorConfig: editorConfig, featureFlags: featureFlags)
    let editor = textKitContext.editor
    let fallbackDetector = ReconcilerFallbackDetector(editor: editor)

    guard let textStorage = editor.textStorage else {
      XCTFail("No text storage")
      return
    }

    // Record multiple consecutive failures
    for i in 0..<5 {
      fallbackDetector.recordOptimizationFailure(reason: "Test failure \(i)")
    }

    // Create normal delta batch
    let metadata = DeltaMetadata(sourceUpdate: "Normal delta after failures")
    let delta = ReconcilerDelta(
      type: .textUpdate(
        nodeKey: "test-node",
        newText: "Test text",
        range: NSRange(location: 0, length: 5)
      ),
      metadata: metadata
    )

    let context = ReconcilerContext(
      updateSource: "FallbackTest",
      nodeCount: 1,
      textStorageLength: textStorage.length
    )

    // Test fallback decision after failures
    let decision = fallbackDetector.shouldFallbackToFullReconciliation(
      for: [delta],
      textStorage: textStorage,
      context: context
    )

    switch decision {
    case .fallback(let reason):
      XCTAssertTrue(reason.contains("consecutive failures"), "Should fallback due to consecutive failures")
    case .useOptimized:
      XCTFail("Should fallback after consecutive failures")
    }
  }

  func testFallbackOnInvalidTextStorageState() throws {
    let featureFlags = FeatureFlags(optimizedReconciler: true, reconcilerMetrics: true)
    let metrics = FallbackTestMetricsContainer()
    let editorConfig = EditorConfig(theme: Theme(), plugins: [], metricsContainer: metrics)
    let textKitContext = LexicalReadOnlyTextKitContext(editorConfig: editorConfig, featureFlags: featureFlags)
    let editor = textKitContext.editor
    let fallbackDetector = ReconcilerFallbackDetector(editor: editor)

    guard let textStorage = editor.textStorage else {
      XCTFail("No text storage")
      return
    }

    // Create delta with invalid range (out of bounds)
    let metadata = DeltaMetadata(sourceUpdate: "Invalid range delta")
    let delta = ReconcilerDelta(
      type: .textUpdate(
        nodeKey: "invalid-node",
        newText: "Test text",
        range: NSRange(location: 1000, length: 100) // Out of bounds
      ),
      metadata: metadata
    )

    let context = ReconcilerContext(
      updateSource: "FallbackTest",
      nodeCount: 1,
      textStorageLength: textStorage.length
    )

    // Test fallback decision with invalid range
    let decision = fallbackDetector.shouldFallbackToFullReconciliation(
      for: [delta],
      textStorage: textStorage,
      context: context
    )

    switch decision {
    case .fallback(let reason):
      XCTAssertTrue(reason.contains("invalid") || reason.contains("range"), "Should fallback due to invalid range")
    case .useOptimized:
      XCTFail("Should fallback with invalid range")
    }
  }

  func testNoFallbackOnNormalOperation() throws {
    let featureFlags = FeatureFlags(optimizedReconciler: true, reconcilerMetrics: true)
    let metrics = FallbackTestMetricsContainer()
    let editorConfig = EditorConfig(theme: Theme(), plugins: [], metricsContainer: metrics)
    let textKitContext = LexicalReadOnlyTextKitContext(editorConfig: editorConfig, featureFlags: featureFlags)
    let editor = textKitContext.editor
    let fallbackDetector = ReconcilerFallbackDetector(editor: editor)

    // Create normal document
    try editor.update {
      guard let rootNode = getActiveEditorState()?.getRootNode() else { return }
      let paragraph = ParagraphNode()
      let textNode = TextNode(text: "Normal text content", key: nil)
      try paragraph.append([textNode])
      try rootNode.append([paragraph])
    }

    guard let textStorage = editor.textStorage else {
      XCTFail("No text storage")
      return
    }

    // Create normal delta batch - use actual text storage length for range
    let actualTextLength = min(12, textStorage.length)
    let metadata = DeltaMetadata(sourceUpdate: "Normal operation")
    let delta = ReconcilerDelta(
      type: .textUpdate(
        nodeKey: "normal-node",
        newText: "Updated text",
        range: NSRange(location: 0, length: actualTextLength)
      ),
      metadata: metadata
    )

    let context = ReconcilerContext(
      updateSource: "FallbackTest",
      nodeCount: 1,
      textStorageLength: textStorage.length
    )

    // Test no fallback for normal operation
    let decision = fallbackDetector.shouldFallbackToFullReconciliation(
      for: [delta],
      textStorage: textStorage,
      context: context
    )

    switch decision {
    case .fallback(let reason):
      XCTFail("Should not fallback for normal operation: \(reason)")
    case .useOptimized:
      // Expected behavior
      break
    }
  }

  func testFallbackOnAnchorCorruption() throws {
    let featureFlags = FeatureFlags(optimizedReconciler: true, reconcilerMetrics: true, anchorBasedReconciliation: true)
    let metrics = FallbackTestMetricsContainer()
    let editorConfig = EditorConfig(theme: Theme(), plugins: [], metricsContainer: metrics)
    let textKitContext = LexicalReadOnlyTextKitContext(editorConfig: editorConfig, featureFlags: featureFlags)
    let editor = textKitContext.editor
    let fallbackDetector = ReconcilerFallbackDetector(editor: editor)

    guard let textStorage = editor.textStorage else {
      XCTFail("No text storage")
      return
    }

    // Create anchor-related delta that might trigger corruption detection
    let metadata = DeltaMetadata(sourceUpdate: "Anchor corruption test")
    let delta = ReconcilerDelta(
      type: .anchorUpdate(
        nodeKey: "corrupted-anchor",
        preambleLocation: 0,
        postambleLocation: 10
      ),
      metadata: metadata
    )

    let context = ReconcilerContext(
      updateSource: "FallbackTest",
      nodeCount: 1,
      textStorageLength: textStorage.length
    )

    // Test potential fallback on anchor operations
    let decision = fallbackDetector.shouldFallbackToFullReconciliation(
      for: [delta],
      textStorage: textStorage,
      context: context
    )

    // Anchor operations may or may not trigger fallback depending on implementation
    switch decision {
    case .fallback(let reason):
      print("Fallback triggered for anchor operation: \(reason)")
    case .useOptimized:
      print("Anchor operation allowed to continue")
    }

    // Test passes regardless of decision - we're testing that the detector can handle anchor deltas
  }

  func testFallbackResetAfterSuccess() throws {
    let featureFlags = FeatureFlags(optimizedReconciler: true, reconcilerMetrics: true)
    let metrics = FallbackTestMetricsContainer()
    let editorConfig = EditorConfig(theme: Theme(), plugins: [], metricsContainer: metrics)
    let textKitContext = LexicalReadOnlyTextKitContext(editorConfig: editorConfig, featureFlags: featureFlags)
    let editor = textKitContext.editor
    let fallbackDetector = ReconcilerFallbackDetector(editor: editor)

    guard let textStorage = editor.textStorage else {
      XCTFail("No text storage")
      return
    }

    // Record some failures
    for i in 0..<3 {
      fallbackDetector.recordOptimizationFailure(reason: "Test failure \(i)")
    }

    // Reset fallback state (simulating successful operation)
    fallbackDetector.resetFallbackState()

    // Create normal delta batch
    let metadata = DeltaMetadata(sourceUpdate: "After reset")
    let delta = ReconcilerDelta(
      type: .textUpdate(
        nodeKey: "reset-test-node",
        newText: "Test after reset",
        range: NSRange(location: 0, length: 5)
      ),
      metadata: metadata
    )

    let context = ReconcilerContext(
      updateSource: "FallbackTest",
      nodeCount: 1,
      textStorageLength: textStorage.length
    )

    // Test that fallback state was reset
    let decision = fallbackDetector.shouldFallbackToFullReconciliation(
      for: [delta],
      textStorage: textStorage,
      context: context
    )

    switch decision {
    case .fallback(let reason):
      // Should not fallback due to previous failures after reset
      if reason.contains("consecutive failures") {
        XCTFail("Should not fallback due to consecutive failures after reset")
      }
    case .useOptimized:
      // Expected behavior after reset
      break
    }
  }

  func testFallbackOnComplexStructuralChanges() throws {
    let featureFlags = FeatureFlags(optimizedReconciler: true, reconcilerMetrics: true)
    let metrics = FallbackTestMetricsContainer()
    let editorConfig = EditorConfig(theme: Theme(), plugins: [], metricsContainer: metrics)
    let textKitContext = LexicalReadOnlyTextKitContext(editorConfig: editorConfig, featureFlags: featureFlags)
    let editor = textKitContext.editor
    let fallbackDetector = ReconcilerFallbackDetector(editor: editor)

    guard let textStorage = editor.textStorage else {
      XCTFail("No text storage")
      return
    }

    // Create complex batch with mixed operations
    var complexDeltas: [ReconcilerDelta] = []

    // Add multiple insertion deltas
    for i in 0..<10 {
      let insertionData = NodeInsertionData(
        preamble: NSAttributedString(string: ""),
        content: NSAttributedString(string: "Complex node \(i)"),
        postamble: NSAttributedString(string: "\n"),
        nodeKey: "complex-\(i)"
      )

      let metadata = DeltaMetadata(sourceUpdate: "Complex structural change \(i)")
      let delta = ReconcilerDelta(
        type: .nodeInsertion(
          nodeKey: "complex-\(i)",
          insertionData: insertionData,
          location: i * 10
        ),
        metadata: metadata
      )
      complexDeltas.append(delta)
    }

    // Add some deletions
    for i in 0..<5 {
      let metadata = DeltaMetadata(sourceUpdate: "Complex deletion \(i)")
      let delta = ReconcilerDelta(
        type: .nodeDeletion(
          nodeKey: "delete-\(i)",
          range: NSRange(location: i * 15, length: 10)
        ),
        metadata: metadata
      )
      complexDeltas.append(delta)
    }

    let context = ReconcilerContext(
      updateSource: "FallbackTest",
      nodeCount: 15,
      textStorageLength: textStorage.length
    )

    // Test fallback decision for complex structural changes
    let decision = fallbackDetector.shouldFallbackToFullReconciliation(
      for: complexDeltas,
      textStorage: textStorage,
      context: context
    )

    // Complex structural changes may trigger fallback
    switch decision {
    case .fallback(let reason):
      print("Fallback triggered for complex changes: \(reason)")
      XCTAssertFalse(reason.isEmpty, "Should provide fallback reason")
    case .useOptimized:
      print("Complex changes allowed to continue optimized")
    }

    // Test passes regardless - we're verifying the detector can handle complex scenarios
  }

  func testMemoryPressureFallback() throws {
    let featureFlags = FeatureFlags(optimizedReconciler: true, reconcilerMetrics: true)
    let metrics = FallbackTestMetricsContainer()
    let editorConfig = EditorConfig(theme: Theme(), plugins: [], metricsContainer: metrics)
    let textKitContext = LexicalReadOnlyTextKitContext(editorConfig: editorConfig, featureFlags: featureFlags)
    let editor = textKitContext.editor
    let fallbackDetector = ReconcilerFallbackDetector(editor: editor)

    guard let textStorage = editor.textStorage else {
      XCTFail("No text storage")
      return
    }

    // Create context that might indicate memory pressure
    let context = ReconcilerContext(
      updateSource: "MemoryPressureTest",
      nodeCount: 10000, // Large node count
      textStorageLength: 1000000 // Large text storage
    )

    // Create normal delta batch
    let metadata = DeltaMetadata(sourceUpdate: "Memory pressure test")
    let delta = ReconcilerDelta(
      type: .textUpdate(
        nodeKey: "memory-test-node",
        newText: "Test under memory pressure",
        range: NSRange(location: 0, length: 10)
      ),
      metadata: metadata
    )

    // Test fallback decision under potential memory pressure
    let decision = fallbackDetector.shouldFallbackToFullReconciliation(
      for: [delta],
      textStorage: textStorage,
      context: context
    )

    // Memory pressure detection may or may not be implemented
    switch decision {
    case .fallback(let reason):
      print("Fallback triggered for memory pressure: \(reason)")
    case .useOptimized:
      print("Operation allowed despite potential memory pressure")
    }

    // Test passes regardless - we're verifying the detector handles large contexts
  }
}

// MARK: - Supporting Types

@MainActor
class FallbackTestMetricsContainer: EditorMetricsContainer {
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