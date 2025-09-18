/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Lexical
import UIKit

@MainActor
final class PlaygroundMetricsContainer: EditorMetricsContainer {
  private(set) var lastReconcilerMetric: ReconcilerMetric?
  var onMetricRecorded: ((ReconcilerMetric) -> Void)?

  nonisolated func record(_ metric: EditorMetric) {
    Task { @MainActor [weak self] in
      guard case .reconcilerRun(let data) = metric else { return }
      self?.lastReconcilerMetric = data
      self?.onMetricRecorded?(data)
    }
  }

  nonisolated func resetMetrics() {
    Task { @MainActor [weak self] in
      self?.lastReconcilerMetric = nil
    }
  }
}

enum ReconcilerPlaygroundFixtures {

  @MainActor
  static func removeAllChildren(from element: ElementNode) throws {
    while let child: Node = element.getFirstChild() {
      try child.remove()
    }
  }

  @MainActor
  static func largeDocumentParagraphs(count: Int = 60) -> [ParagraphNode] {
    return (0..<count).map { index in
      let paragraph = ParagraphNode()
      let text = TextNode(text: "Paragraph \(index) — Lorem ipsum dolor sit amet, consectetur adipiscing elit.", key: nil)
      try? paragraph.append([text])
      return paragraph
    }
  }

  @discardableResult
  @MainActor
  static func loadStandardDocument(into editor: Editor) -> [ParagraphNode] {
    var paragraphs: [ParagraphNode] = []
    try? editor.update {
      guard let root = getRoot() else { return }
      try removeAllChildren(from: root)

      let intro = ParagraphNode()
      let introText = TextNode(text: "Reconciler playground document", key: nil)
      try intro.append([introText])

      let bulleted = ParagraphNode()
      let bulletedText = TextNode(text: "• Structural edits will be added below", key: nil)
      try bulleted.append([bulletedText])

      let longForm = ParagraphNode()
      let longFormText = TextNode(text: "Long paragraph with anchors enabled for delta application demos.", key: nil)
      try longForm.append([longFormText])

      let generated = largeDocumentParagraphs(count: 8)

      paragraphs = [intro, bulleted, longForm] + generated
      try root.append(paragraphs)
      try longForm.select(anchorOffset: 0, focusOffset: 0)
    }
    return paragraphs
  }

  @MainActor
  static func createStructuralFallbackScenario(in editor: Editor) {
    try? editor.update {
      guard let root = getRoot() else { return }
      try removeAllChildren(from: root)

      let first = ParagraphNode()
      try first.append([TextNode(text: "First paragraph", key: nil)])
      let second = ParagraphNode()
      try second.append([TextNode(text: "Second paragraph", key: nil)])
      try root.append([first, second])
      try first.select(anchorOffset: nil, focusOffset: nil)
    }
  }

  @MainActor
  static func appendSiblingBeforeCursor(in editor: Editor) {
    try? editor.update {
      guard let selection = try getSelection() as? RangeSelection,
        let node = try selection.anchor.getNode() as? ElementNode
      else { return }
      let parent: ElementNode = try node.getParentOrThrow()

      let sibling = ParagraphNode()
      try sibling.append([TextNode(text: "Inserted sibling at \(Date())", key: nil)])

      if let firstChild: Node = parent.getFirstChild() {
        try firstChild.insertBefore(nodeToInsert: sibling)
      } else {
        try parent.append([sibling])
      }
    }
  }
}

extension Editor {
  func enableAnchors(_ enabled: Bool) {
    setReconcilerAnchorsEnabled(enabled)
  }
}
