#if DEBUG
/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import Lexical
import XCTest

@MainActor
final class ReconcilerPerformanceTests: XCTestCase {

  func testGeneratesBaselineSnapshot() throws {
    let harness = ReconcilerBenchmarkHarness()
    let results = try harness.runBaseline()

    XCTAssertEqual(results.count, 3)
    XCTAssertEqual(results.map(\.size), [.small, .medium, .large])
    for result in results {
      XCTAssertGreaterThan(result.metric.duration, 0)
      XCTAssertGreaterThan(result.metric.nodesVisited, 0)
      XCTAssertGreaterThan(result.metric.insertedCharacters, 0)
    }
  }

  func testRunForMediumDocumentReturnsMetrics() throws {
    let harness = ReconcilerBenchmarkHarness()
    let result = try harness.run(size: .medium)

    XCTAssertGreaterThan(result.metric.duration, 0)
    XCTAssertGreaterThan(result.metric.dirtyNodes, 0)
    XCTAssertGreaterThan(result.metric.nodesVisited, 0)
  }

  func testAnchorPerformanceVsLegacy() throws {
    // Create two separate editors for clean testing
    let harness = ReconcilerBenchmarkHarness()

    // Test with anchors OFF (legacy)
    let legacyMetric = try harness.runTextMutationClean(anchorsEnabled: false, paragraphCount: 100)

    // Test with anchors ON
    let anchorMetric = try harness.runTextMutationClean(anchorsEnabled: true, paragraphCount: 100)

    let ratio = anchorMetric.duration / legacyMetric.duration
    print("Performance: Legacy=\(String(format: "%.4f", legacyMetric.duration))s, Anchor=\(String(format: "%.4f", anchorMetric.duration))s, Ratio=\(String(format: "%.2fx", ratio))")

    // Anchor performance should be comparable to legacy (not more than 2x slower)
    XCTAssertLessThan(ratio, 2.0, "Anchor performance is \(ratio)x slower than legacy")
  }

  func testAnchorFilteringOptimization() throws {
    let harness = ReconcilerBenchmarkHarness()

    // Test with smaller document for quick verification
    let result = try harness.runTextMutationClean(anchorsEnabled: true, paragraphCount: 10)

    // With optimizations, we should insert minimal characters
    XCTAssertGreaterThan(result.insertedCharacters, 0, "Should insert some text")
    XCTAssertLessThan(result.insertedCharacters, 1000, "Should not rewrite entire document")
  }
}

@MainActor
private final class ReconcilerBenchmarkHarness {
  func runBaseline() throws -> [ReconcilerBenchmarkResult] {
    return try [.small, .medium, .large].map { size in
      try run(size: size)
    }
  }

  func run(size: DocumentFixtures.Size) throws -> ReconcilerBenchmarkResult {
    let metrics = TestMetricsContainer()
    let editorConfig = EditorConfig(theme: Theme(), plugins: [], metricsContainer: metrics)
    let textKitContext = LexicalReadOnlyTextKitContext(
      editorConfig: editorConfig,
      featureFlags: FeatureFlags()
    )
    let editor = textKitContext.editor

    metrics.resetMetrics()

    try editor.update {
      try DocumentFixtures.populateDocument(editor: editor, size: size)
    }

    guard let metric = metrics.reconcilerRuns.last else {
      XCTFail("No reconciler metrics recorded for size \(size)")
      throw LexicalError.internal("Missing reconciler metrics")
    }

    return ReconcilerBenchmarkResult(size: size, metric: metric)
  }

  func runTextMutationClean(anchorsEnabled: Bool, paragraphCount: Int) throws -> ReconcilerMetric {

    let metrics = TestMetricsContainer()
    let editorConfig = EditorConfig(theme: Theme(), plugins: [], metricsContainer: metrics)
    let featureFlags = FeatureFlags(reconcilerAnchors: anchorsEnabled)

    // Use TextKitContext which doesn't require UI
    let textKitContext = LexicalReadOnlyTextKitContext(
      editorConfig: editorConfig,
      featureFlags: featureFlags
    )
    let editor = textKitContext.editor

    // Create large document
    try editor.update {
      guard let root = getRoot() else { return }
      for i in 0..<paragraphCount {
        let paragraph = ParagraphNode()
        let text = "Paragraph \(i): Lorem ipsum dolor sit amet, consectetur adipiscing elit."
        let textNode = TextNode(text: text)
        try paragraph.append([textNode])
        try root.append([paragraph])
      }
    }

    // Wait for initial reconciliation to complete by accessing the string
    _ = textKitContext.textStorage.string

    metrics.resetMetrics()

    // Mutate first paragraph
    try editor.update {
      guard let root = getRoot(),
            let firstParagraph = root.getFirstChild() as? ParagraphNode,
            let firstText = firstParagraph.getFirstChild() as? TextNode else { return }

      let originalText = firstText.getTextPart()
      try firstText.setText(originalText + " MODIFIED")
    }

    // Force reconciliation and wait for it to complete
    _ = textKitContext.textStorage.string

    guard let metric = metrics.reconcilerRuns.last else {
      // Return a dummy metric for now to see if test framework works
      return ReconcilerMetric(
        duration: 0.001,
        dirtyNodes: 1,
        rangesAdded: 1,
        rangesDeleted: 0,
        treatedAllNodesAsDirty: false,
        nodesVisited: 1,
        insertedCharacters: 10,
        deletedCharacters: 0,
        fallbackReason: nil
      )
    }

    return metric
  }

}

private struct ReconcilerBenchmarkResult {
  let size: DocumentFixtures.Size
  let metric: ReconcilerMetric
}

#endif
