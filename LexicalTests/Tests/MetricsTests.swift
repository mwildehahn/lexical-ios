/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import Lexical
import XCTest

@MainActor
final class MetricsTests: XCTestCase {

  func testReconcilerRecordsMetricsForLargeDocument() throws {
    let metrics = TestMetricsContainer()
    let editorConfig = EditorConfig(theme: Theme(), plugins: [], metricsContainer: metrics)
    let textKitContext = LexicalReadOnlyTextKitContext(editorConfig: editorConfig, featureFlags: FeatureFlags())
    let editor = textKitContext.editor

    metrics.resetMetrics()

    try editor.update {
      guard let rootNode = getActiveEditorState()?.getRootNode() else {
        XCTFail("No root node")
        return
      }

      for index in 0..<200 {
        let paragraph = ParagraphNode()
        let textNode = TextNode(text: "Paragraph \(index)", key: nil)
        try paragraph.append([textNode])
        try rootNode.append([paragraph])
      }
    }

    guard let metric = metrics.reconcilerRuns.last else {
      XCTFail("Expected reconciler metrics to be recorded")
      return
    }

    XCTAssertGreaterThan(metric.duration, 0)
    XCTAssertGreaterThan(metric.dirtyNodes, 0)
    XCTAssertGreaterThan(metric.rangesAdded, 0)
    XCTAssertGreaterThanOrEqual(metric.rangesDeleted, 0)
  }
}

@MainActor
final class TestMetricsContainer: EditorMetricsContainer {
  private(set) var reconcilerRuns: [ReconcilerMetric] = []
  var metricsData: [String: Any] = [:]

  func record(_ metric: EditorMetric) {
    switch metric {
    case .reconcilerRun(let data):
      reconcilerRuns.append(data)
    }
  }

  func resetMetrics() {
    reconcilerRuns.removeAll()
    metricsData.removeAll()
  }
}
