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
}

private struct ReconcilerBenchmarkResult {
  let size: DocumentFixtures.Size
  let metric: ReconcilerMetric
}

#endif
