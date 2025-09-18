/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import Lexical
import XCTest

@MainActor
final class ReconcilerFallbackTests: XCTestCase {

  func testStructuralChangeTriggersFallback() throws {
    let metrics = TestMetricsContainer()
    let editorConfig = EditorConfig(theme: Theme(), plugins: [], metricsContainer: metrics)
    let textKitContext = LexicalReadOnlyTextKitContext(
      editorConfig: editorConfig,
      featureFlags: FeatureFlags(reconcilerAnchors: true)
    )
    let editor = textKitContext.editor

    try editor.update {
      guard let root = getRoot() else {
        XCTFail("Missing root node")
        return
      }

      for name in ["First", "Second"] {
        let paragraph = ParagraphNode()
        let textNode = TextNode(text: name, key: nil)
        try paragraph.append([textNode])
        try root.append([paragraph])
      }
    }

    metrics.resetMetrics()

    try editor.update {
      guard let root = getRoot(), let first = root.getFirstChild() else {
        XCTFail("Failed to fetch first paragraph")
        return
      }
      let inserted = ParagraphNode()
      let textNode = TextNode(text: "Inserted", key: nil)
      try inserted.append([textNode])
      try first.insertBefore(nodeToInsert: inserted)
    }

    XCTAssertEqual(editor.lastReconcilerFallbackReason, .structuralChange)
    XCTAssertEqual(editor.lastReconcilerUsedAnchors, false)

    guard let metric = metrics.reconcilerRuns.last else {
      XCTFail("Expected reconciler metrics")
      return
    }

    XCTAssertEqual(metric.fallbackReason, .structuralChange)
  }
}

