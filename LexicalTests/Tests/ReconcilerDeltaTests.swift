/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import Lexical
import XCTest

@MainActor
final class ReconcilerDeltaTests: XCTestCase {

  private final class TestMetricsContainer: EditorMetricsContainer {
    private(set) var lastMetric: ReconcilerMetric?

    nonisolated func record(_ metric: EditorMetric) {
      Task { @MainActor in
        if case let .reconcilerRun(data) = metric {
          self.lastMetric = data
        }
      }
    }

    nonisolated func resetMetrics() {
      Task { @MainActor in
        self.lastMetric = nil
      }
    }

    func reset() {
      lastMetric = nil
    }
  }

  func testLegacyDeltaAppliedWhenAnchorsDisabled() throws {
    let context = LexicalReadOnlyTextKitContext(
      editorConfig: EditorConfig(theme: Theme(), plugins: []),
      featureFlags: FeatureFlags()
    )
    let editor = context.editor

    try editor.update {
      guard let rootNode = getActiveEditorState()?.getRootNode() else {
        XCTFail("Missing root node")
        return
      }
      _ = try? rootNode.clear()
      let paragraph = ParagraphNode()
      let textNode = TextNode(text: "Hello", key: nil)
      try paragraph.append([textNode])
      try rootNode.append([paragraph])
    }

    let textStorage = editor.textStorage
    XCTAssertNotNil(textStorage)
    let initialString = textStorage?.string ?? ""

    try editor.update {
      guard
        let rootNode = getActiveEditorState()?.getRootNode(),
        rootNode.getChildren().count == 1,
        let paragraph = rootNode.getFirstChild() as? ParagraphNode,
        let textNode = paragraph.getFirstChild() as? TextNode
      else {
        XCTFail("Missing nodes")
        return
      }
      try textNode.setText("Hello world")
    }

    XCTAssertNotEqual(textStorage, nil)
    XCTAssertEqual(textStorage?.string, "Hello world")
    XCTAssertNotEqual(initialString, textStorage?.string)
  }

  func testAnchorDeltaAppliesWhenAnchorsEnabled() throws {
    let context = LexicalReadOnlyTextKitContext(
      editorConfig: EditorConfig(theme: Theme(), plugins: []),
      featureFlags: FeatureFlags(reconcilerAnchors: true)
    )
    let editor = context.editor

    try editor.update {
      guard let rootNode = getActiveEditorState()?.getRootNode() else {
        XCTFail("Missing root node")
        return
      }
      _ = try? rootNode.clear()
      let paragraph = ParagraphNode()
      let textNode = TextNode(text: "Alpha", key: nil)
      try paragraph.append([textNode])
      try rootNode.append([paragraph])
    }

    let textStorage = editor.textStorage
    XCTAssertNotNil(textStorage)
    let initialString = textStorage?.string ?? ""

    try editor.update {
      guard
        let rootNode = getActiveEditorState()?.getRootNode(),
        rootNode.getChildren().count == 1,
        let paragraph = rootNode.getFirstChild() as? ParagraphNode,
        let textNode = paragraph.getFirstChild() as? TextNode
      else {
        XCTFail("Missing nodes")
        return
      }
      try textNode.setText("Alpha beta")
    }

    XCTAssertNotNil(textStorage)
    XCTAssertEqual(textStorage?.string, "S:1Alpha betaE:1")
    XCTAssertNotEqual(initialString, textStorage?.string)
    XCTAssertTrue(editor.lastReconcilerUsedAnchors)
    XCTAssertNil(editor.lastReconcilerFallbackReason)
  }

  func testAnchorDeltaPerformsPartialReplacement() throws {
    let metrics = TestMetricsContainer()
    let context = LexicalReadOnlyTextKitContext(
      editorConfig: EditorConfig(theme: Theme(), plugins: [], metricsContainer: metrics),
      featureFlags: FeatureFlags(reconcilerAnchors: true)
    )
    let editor = context.editor

    try editor.update {
      guard let rootNode = getActiveEditorState()?.getRootNode() else {
        XCTFail("Missing root node")
        return
      }
      _ = try? rootNode.clear()
      let paragraph = ParagraphNode()
      let textNode = TextNode(text: "Baseline", key: nil)
      try paragraph.append([textNode])
      try rootNode.append([paragraph])
      try textNode.select(anchorOffset: nil, focusOffset: nil)
    }

    metrics.reset()

    try editor.update {
      guard
        let rootNode = getActiveEditorState()?.getRootNode(),
        let paragraph = rootNode.getFirstChild() as? ParagraphNode,
        let textNode = paragraph.getFirstChild() as? TextNode
      else {
        XCTFail("Missing nodes")
        return
      }
      try textNode.setText("Baseline appended text")
    }

    RunLoop.current.run(until: Date().addingTimeInterval(0.01))

    guard let metric = metrics.lastMetric else {
      XCTFail("Expected reconciler metric after anchored mutation")
      return
    }

    XCTAssertNil(metric.fallbackReason)
    XCTAssertTrue(editor.lastReconcilerUsedAnchors)
    XCTAssertLessThanOrEqual(metric.insertedCharacters, 80)
    XCTAssertGreaterThan(metric.insertedCharacters, 0)
  }

  func testAnchoredMutationOnLargeDocumentMatchesLegacyTiming() throws {
    let baselineMetrics = TestMetricsContainer()
    let baselineContext = LexicalReadOnlyTextKitContext(
      editorConfig: EditorConfig(theme: Theme(), plugins: [], metricsContainer: baselineMetrics),
      featureFlags: FeatureFlags()
    )
    let baselineEditor = baselineContext.editor
    let baselineOriginal = try populateLargeDocument(in: baselineEditor, paragraphCount: 200, sentencesPerParagraph: 6)
    let baselineSuffix = "\nBaseline mutation \(UUID().uuidString)"

    let legacy = try measureMutation(
      on: baselineEditor,
      metrics: baselineMetrics,
      originalText: baselineOriginal,
      suffix: baselineSuffix,
      anchorsEnabled: false
    )

    let anchoredMetrics = TestMetricsContainer()
    let anchoredContext = LexicalReadOnlyTextKitContext(
      editorConfig: EditorConfig(theme: Theme(), plugins: [], metricsContainer: anchoredMetrics),
      featureFlags: FeatureFlags(reconcilerAnchors: true)
    )
    let anchoredEditor = anchoredContext.editor
    let anchoredOriginal = try populateLargeDocument(in: anchoredEditor, paragraphCount: 200, sentencesPerParagraph: 6)
    let warmupSuffix = "\nWarm up \(UUID().uuidString)"
    let anchoredSuffix = "\nAnchored mutation \(UUID().uuidString)"

    _ = try measureMutation(
      on: anchoredEditor,
      metrics: anchoredMetrics,
      originalText: anchoredOriginal,
      suffix: warmupSuffix,
      anchorsEnabled: true
    )

    let anchored = try measureMutation(
      on: anchoredEditor,
      metrics: anchoredMetrics,
      originalText: anchoredOriginal,
      suffix: anchoredSuffix,
      anchorsEnabled: true
    )

    XCTAssertNil(anchored.metric.fallbackReason)
    XCTAssertTrue(anchoredEditor.lastReconcilerUsedAnchors)
    XCTAssertLessThanOrEqual(anchored.metric.insertedCharacters, anchoredSuffix.count + 20)

    let durationCeiling = max(legacy.duration * 3.0, legacy.duration + 0.015, 0.03)
    XCTAssertLessThanOrEqual(anchored.duration, durationCeiling)
  }
}

// MARK: - Helpers

@MainActor
extension ReconcilerDeltaTests {

  private func populateLargeDocument(
    in editor: Editor,
    paragraphCount: Int,
    sentencesPerParagraph: Int
  ) throws -> String {
    var original = ""
    try editor.update {
      guard let root = getRoot() else { return }
      try ReconcilerTestsHelpers.removeAllChildren(from: root)

      for paragraphIndex in 0..<paragraphCount {
        let paragraph = ParagraphNode()
        var combined = ""
        for sentenceIndex in 0..<sentencesPerParagraph {
          combined += "Paragraph \(paragraphIndex) sentence \(sentenceIndex): Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vivamus pulvinar lectus sit amet arcu mollis placerat. "
        }
        let textNode = TextNode(text: combined, key: nil)
        try paragraph.append([textNode])
        try root.append([paragraph])
      }

      guard
        let firstParagraph = root.getFirstChild() as? ParagraphNode,
        let firstText = firstParagraph.getFirstChild() as? TextNode
      else { return }

      original = firstText.getTextPart()
      let extent = original.lengthAsNSString()
      try firstText.select(anchorOffset: extent, focusOffset: extent)
    }
    return original
  }

  private func measureMutation(
    on editor: Editor,
    metrics: TestMetricsContainer,
    originalText: String,
    suffix: String,
    anchorsEnabled: Bool
  ) throws -> (duration: CFTimeInterval, metric: ReconcilerMetric) {
    metrics.resetMetrics()
    editor.setReconcilerAnchorsEnabled(anchorsEnabled)

    let start = CFAbsoluteTimeGetCurrent()
    try editor.update {
      guard
        let rootNode = getRoot(),
        let paragraph = rootNode.getFirstChild() as? ParagraphNode,
        let textNode = paragraph.getFirstChild() as? TextNode
      else { return }
      try textNode.setText(originalText + suffix)
    }
    let duration = CFAbsoluteTimeGetCurrent() - start

    RunLoop.current.run(until: Date().addingTimeInterval(0.02))

    let metric = try XCTUnwrap(metrics.lastMetric, "Expected reconciler metric after mutation")

    try editor.update {
      guard
        let rootNode = getRoot(),
        let paragraph = rootNode.getFirstChild() as? ParagraphNode,
        let textNode = paragraph.getFirstChild() as? TextNode
      else { return }
      try textNode.setText(originalText)
    }

    RunLoop.current.run(until: Date().addingTimeInterval(0.02))

    return (duration, metric)
  }
}

@MainActor
private enum ReconcilerTestsHelpers {
  fileprivate static func removeAllChildren(from element: ElementNode) throws {
    while let child = element.getFirstChild() {
      try child.remove()
    }
  }
}
