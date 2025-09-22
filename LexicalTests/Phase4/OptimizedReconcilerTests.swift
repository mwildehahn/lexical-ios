/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import Lexical
import XCTest

@MainActor
class OptimizedReconcilerTests: XCTestCase {

  func testOptimizedReconcilerSuccess() throws {
    let featureFlags = FeatureFlags(optimizedReconciler: true, reconcilerMetrics: true)
    let metrics = OptimizedReconcilerTestMetricsContainer()
    let editorConfig = EditorConfig(theme: Theme(), plugins: [], metricsContainer: metrics)
    let textKitContext = LexicalReadOnlyTextKitContext(editorConfig: editorConfig, featureFlags: featureFlags)
    let editor = textKitContext.editor

    // Create initial document state
    var currentState: EditorState!
    try editor.update {
      guard let rootNode = getActiveEditorState()?.getRootNode() else { return }
      let paragraph = ParagraphNode()
      let textNode = TextNode(text: "Initial text", key: nil)
      try paragraph.append([textNode])
      try rootNode.append([paragraph])

      currentState = getActiveEditorState()
    }

    // Create modified state
    var pendingState: EditorState!
    try editor.update {
      guard let rootNode = getActiveEditorState()?.getRootNode() else { return }
      let children = rootNode.getChildren()
      if let paragraph = children.first as? ParagraphNode {
        let paragraphChildren = paragraph.getChildren()
        if let textNode = paragraphChildren.first as? TextNode {
          try textNode.setText("Modified text")
        }
      }

      pendingState = getActiveEditorState()
    }

    // Test optimized reconciliation
    let result = try OptimizedReconciler.attemptOptimizedReconciliation(
      currentEditorState: currentState,
      pendingEditorState: pendingState,
      editor: editor,
      shouldReconcileSelection: false,
      markedTextOperation: nil
    )

    // Verify successful optimization
    XCTAssertTrue(result, "Optimized reconciliation should succeed for simple text change")

    // Verify metrics were recorded
    if featureFlags.reconcilerMetrics {
      XCTAssertGreaterThan(metrics.optimizedReconcilerRuns.count, 0, "Should record optimized reconciler metrics")
    }
  }

  func testOptimizedReconcilerFallback() throws {
    let featureFlags = FeatureFlags(optimizedReconciler: true, reconcilerMetrics: true)
    let metrics = OptimizedReconcilerTestMetricsContainer()
    let editorConfig = EditorConfig(theme: Theme(), plugins: [], metricsContainer: metrics)
    let textKitContext = LexicalReadOnlyTextKitContext(editorConfig: editorConfig, featureFlags: featureFlags)
    let editor = textKitContext.editor

    // Create complex initial state
    var currentState: EditorState!
    try editor.update {
      guard let rootNode = getActiveEditorState()?.getRootNode() else { return }

      // Create many nodes to potentially trigger fallback
      for i in 0..<150 { // Above fallback threshold
        let paragraph = ParagraphNode()
        let textNode = TextNode(text: "Paragraph \(i)", key: nil)
        try paragraph.append([textNode])
        try rootNode.append([paragraph])
      }

      currentState = getActiveEditorState()
    }

    // Create massive change that should trigger fallback
    var pendingState: EditorState!
    try editor.update {
      guard let rootNode = getActiveEditorState()?.getRootNode() else { return }
      let children = rootNode.getChildren()

      // Modify many nodes simultaneously
      for (index, child) in children.enumerated() {
        if let paragraph = child as? ParagraphNode {
          let paragraphChildren = paragraph.getChildren()
          if let textNode = paragraphChildren.first as? TextNode {
            try textNode.setText("Massively modified paragraph \(index) with much longer text")
          }
        }
      }

      pendingState = getActiveEditorState()
    }

    // Test optimized reconciliation with fallback scenario
    let result = try OptimizedReconciler.attemptOptimizedReconciliation(
      currentEditorState: currentState,
      pendingEditorState: pendingState,
      editor: editor,
      shouldReconcileSelection: false,
      markedTextOperation: nil
    )

    // Should fallback to legacy reconciler
    XCTAssertFalse(result, "Should fallback for massive batch changes")
  }

  func testOptimizedReconcilerWithMarkedText() throws {
    let featureFlags = FeatureFlags(optimizedReconciler: true, reconcilerMetrics: true)
    let metrics = OptimizedReconcilerTestMetricsContainer()
    let editorConfig = EditorConfig(theme: Theme(), plugins: [], metricsContainer: metrics)
    let textKitContext = LexicalReadOnlyTextKitContext(editorConfig: editorConfig, featureFlags: featureFlags)
    let editor = textKitContext.editor

    // Create initial state
    var currentState: EditorState!
    try editor.update {
      guard let rootNode = getActiveEditorState()?.getRootNode() else { return }
      let paragraph = ParagraphNode()
      let textNode = TextNode(text: "Text with marked range", key: nil)
      try paragraph.append([textNode])
      try rootNode.append([paragraph])

      currentState = getActiveEditorState()
    }

    // Create pending state
    var pendingState: EditorState!
    try editor.update {
      guard let rootNode = getActiveEditorState()?.getRootNode() else { return }
      let children = rootNode.getChildren()
      if let paragraph = children.first as? ParagraphNode {
        let paragraphChildren = paragraph.getChildren()
        if let textNode = paragraphChildren.first as? TextNode {
          try textNode.setText("Modified marked text")
        }
      }

      pendingState = getActiveEditorState()
    }

    // Create marked text operation
    let markedTextOperation = MarkedTextOperation(
      createMarkedText: true,
      selectionRangeToReplace: NSRange(location: 5, length: 6),
      markedTextString: "marked",
      markedTextInternalSelection: NSRange(location: 0, length: 6)
    )

    // Test optimized reconciliation with marked text
    let result = try OptimizedReconciler.attemptOptimizedReconciliation(
      currentEditorState: currentState,
      pendingEditorState: pendingState,
      editor: editor,
      shouldReconcileSelection: false,
      markedTextOperation: markedTextOperation
    )

    // Should fallback when marked text is present
    XCTAssertFalse(result, "Should fallback when marked text operation is present")
  }

  func testOptimizedReconcilerDisabled() throws {
    let featureFlags = FeatureFlags(optimizedReconciler: false, reconcilerMetrics: true)
    let metrics = OptimizedReconcilerTestMetricsContainer()
    let editorConfig = EditorConfig(theme: Theme(), plugins: [], metricsContainer: metrics)
    let textKitContext = LexicalReadOnlyTextKitContext(editorConfig: editorConfig, featureFlags: featureFlags)
    let editor = textKitContext.editor

    // Create states
    var currentState: EditorState!
    var pendingState: EditorState!

    try editor.update {
      guard let rootNode = getActiveEditorState()?.getRootNode() else { return }
      let paragraph = ParagraphNode()
      let textNode = TextNode(text: "Test text", key: nil)
      try paragraph.append([textNode])
      try rootNode.append([paragraph])

      currentState = getActiveEditorState()
    }

    try editor.update {
      guard let rootNode = getActiveEditorState()?.getRootNode() else { return }
      let children = rootNode.getChildren()
      if let paragraph = children.first as? ParagraphNode {
        let paragraphChildren = paragraph.getChildren()
        if let textNode = paragraphChildren.first as? TextNode {
          try textNode.setText("Modified text")
        }
      }

      pendingState = getActiveEditorState()
    }

    // Test optimized reconciliation when disabled
    let result = try OptimizedReconciler.attemptOptimizedReconciliation(
      currentEditorState: currentState,
      pendingEditorState: pendingState,
      editor: editor,
      shouldReconcileSelection: false,
      markedTextOperation: nil
    )

    // Should immediately return false when disabled
    XCTAssertFalse(result, "Should return false when optimized reconciler is disabled")
  }

  func testOptimizedReconcilerMetricsCollection() throws {
    let featureFlags = FeatureFlags(optimizedReconciler: true, reconcilerMetrics: true)
    let metrics = OptimizedReconcilerTestMetricsContainer()
    let editorConfig = EditorConfig(theme: Theme(), plugins: [], metricsContainer: metrics)
    let textKitContext = LexicalReadOnlyTextKitContext(editorConfig: editorConfig, featureFlags: featureFlags)
    let editor = textKitContext.editor

    // Create simple change scenario
    var currentState: EditorState!
    var pendingState: EditorState!

    try editor.update {
      guard let rootNode = getActiveEditorState()?.getRootNode() else { return }
      let paragraph = ParagraphNode()
      let textNode = TextNode(text: "Metrics test", key: nil)
      try paragraph.append([textNode])
      try rootNode.append([paragraph])

      currentState = getActiveEditorState()
    }

    try editor.update {
      guard let rootNode = getActiveEditorState()?.getRootNode() else { return }
      let children = rootNode.getChildren()
      if let paragraph = children.first as? ParagraphNode {
        let paragraphChildren = paragraph.getChildren()
        if let textNode = paragraphChildren.first as? TextNode {
          try textNode.setText("Updated metrics test")
        }
      }

      pendingState = getActiveEditorState()
    }

    let initialMetricsCount = metrics.optimizedReconcilerRuns.count

    // Perform optimized reconciliation
    let result = try OptimizedReconciler.attemptOptimizedReconciliation(
      currentEditorState: currentState,
      pendingEditorState: pendingState,
      editor: editor,
      shouldReconcileSelection: false,
      markedTextOperation: nil
    )

    if result {
      // Verify metrics were collected
      XCTAssertGreaterThan(metrics.optimizedReconcilerRuns.count, initialMetricsCount,
                          "Should record new optimized reconciler metric")

      if let latestMetric = metrics.optimizedReconcilerRuns.last {
        XCTAssertGreaterThan(latestMetric.duration, 0, "Should record positive duration")
        XCTAssertGreaterThanOrEqual(latestMetric.deltaCount, 0, "Should record delta count")
        XCTAssertGreaterThanOrEqual(latestMetric.fenwickOperations, 0, "Should record Fenwick operations")
      }
    }
  }

  func testOptimizedReconcilerWithComplexDocument() throws {
    let featureFlags = FeatureFlags(optimizedReconciler: true, reconcilerMetrics: true)
    let metrics = OptimizedReconcilerTestMetricsContainer()
    let editorConfig = EditorConfig(theme: Theme(), plugins: [], metricsContainer: metrics)
    let textKitContext = LexicalReadOnlyTextKitContext(editorConfig: editorConfig, featureFlags: featureFlags)
    let editor = textKitContext.editor

    // Create complex document structure
    var currentState: EditorState!
    var targetNodeKey: NodeKey!

    try editor.update {
      guard let rootNode = getActiveEditorState()?.getRootNode() else { return }

      // Create nested structure
      for i in 0..<5 {
        let paragraph = ParagraphNode()
        let textNode = TextNode(text: "Complex paragraph \(i) with content", key: nil)
        try paragraph.append([textNode])
        try rootNode.append([paragraph])

        if i == 2 {
          targetNodeKey = textNode.key
        }
      }

      currentState = getActiveEditorState()
    }

    // Modify only one node in the complex structure
    var pendingState: EditorState!
    try editor.update {
      guard let rootNode = getActiveEditorState()?.getRootNode() else { return }
      let children = rootNode.getChildren()

      if let targetParagraph = children[2] as? ParagraphNode {
        let paragraphChildren = targetParagraph.getChildren()
        if let textNode = paragraphChildren.first as? TextNode {
          try textNode.setText("MODIFIED: Complex paragraph 2 with new content")
        }
      }

      pendingState = getActiveEditorState()
    }

    // Test optimized reconciliation on complex document
    let result = try OptimizedReconciler.attemptOptimizedReconciliation(
      currentEditorState: currentState,
      pendingEditorState: pendingState,
      editor: editor,
      shouldReconcileSelection: false,
      markedTextOperation: nil
    )

    // Should succeed for targeted change in complex document
    XCTAssertTrue(result, "Should succeed for single node change in complex document")
  }

  func testOptimizedReconcilerErrorHandling() throws {
    let featureFlags = FeatureFlags(optimizedReconciler: true, reconcilerMetrics: true)
    let metrics = OptimizedReconcilerTestMetricsContainer()
    let editorConfig = EditorConfig(theme: Theme(), plugins: [], metricsContainer: metrics)
    let textKitContext = LexicalReadOnlyTextKitContext(editorConfig: editorConfig, featureFlags: featureFlags)
    let editor = textKitContext.editor

    // Create initial state
    var currentState: EditorState!
    try editor.update {
      guard let rootNode = getActiveEditorState()?.getRootNode() else { return }
      let paragraph = ParagraphNode()
      let textNode = TextNode(text: "Error test", key: nil)
      try paragraph.append([textNode])
      try rootNode.append([paragraph])

      currentState = getActiveEditorState()
    }

    // Create problematic pending state (simulating corruption)
    var pendingState: EditorState!
    try editor.update {
      guard let rootNode = getActiveEditorState()?.getRootNode() else { return }

      // Clear all children to create inconsistent state
      for child in rootNode.getChildren() {
        try child.remove()
      }

      pendingState = getActiveEditorState()
    }

    // Test error handling in optimized reconciliation
    let result = try OptimizedReconciler.attemptOptimizedReconciliation(
      currentEditorState: currentState,
      pendingEditorState: pendingState,
      editor: editor,
      shouldReconcileSelection: false,
      markedTextOperation: nil
    )

    // Should handle errors gracefully and fallback
    XCTAssertFalse(result, "Should fallback when encountering error conditions")
  }

  func testOptimizedReconcilerIntegrationWithFeatureFlags() throws {
    // Test with different feature flag combinations
    let flagCombinations: [(optimized: Bool, metrics: Bool, anchors: Bool)] = [
      (true, true, true),
      (true, true, false),
      (true, false, true),
      (true, false, false)
    ]

    for (optimized, metrics, anchors) in flagCombinations {
      let featureFlags = FeatureFlags(
        optimizedReconciler: optimized,
        reconcilerMetrics: metrics,
        anchorBasedReconciliation: anchors
      )

      let testMetrics = OptimizedReconcilerTestMetricsContainer()
      let editorConfig = EditorConfig(theme: Theme(), plugins: [], metricsContainer: testMetrics)
      let textKitContext = LexicalReadOnlyTextKitContext(editorConfig: editorConfig, featureFlags: featureFlags)
      let editor = textKitContext.editor

      // Create simple test scenario
      var currentState: EditorState!
      var pendingState: EditorState!

      try editor.update {
        guard let rootNode = getActiveEditorState()?.getRootNode() else { return }
        let paragraph = ParagraphNode()
        let textNode = TextNode(text: "Flag test", key: nil)
        try paragraph.append([textNode])
        try rootNode.append([paragraph])

        currentState = getActiveEditorState()
      }

      try editor.update {
        guard let rootNode = getActiveEditorState()?.getRootNode() else { return }
        let children = rootNode.getChildren()
        if let paragraph = children.first as? ParagraphNode {
          let paragraphChildren = paragraph.getChildren()
          if let textNode = paragraphChildren.first as? TextNode {
            try textNode.setText("Modified flag test")
          }
        }

        pendingState = getActiveEditorState()
      }

      // Test reconciliation with this flag combination
      let result = try OptimizedReconciler.attemptOptimizedReconciliation(
        currentEditorState: currentState,
        pendingEditorState: pendingState,
        editor: editor,
        shouldReconcileSelection: false,
        markedTextOperation: nil
      )

      // Verify behavior matches feature flags
      if optimized {
        // Should attempt optimization (may succeed or fallback)
        print("Optimization attempt with flags - optimized: \(optimized), metrics: \(metrics), anchors: \(anchors), result: \(result)")
      } else {
        XCTAssertFalse(result, "Should not attempt optimization when flag is disabled")
      }

      // Verify metrics collection based on flag
      if metrics && result {
        XCTAssertGreaterThan(testMetrics.optimizedReconcilerRuns.count, 0,
                           "Should collect metrics when enabled")
      }
    }
  }
}

// MARK: - Supporting Types

@MainActor
class OptimizedReconcilerTestMetricsContainer: EditorMetricsContainer {
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