/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import XCTest
@testable import Lexical

#if os(macOS) && !targetEnvironment(macCatalyst)
@testable import LexicalAppKit
#endif

@MainActor
final class OptimizedReconcilerAttributeOnlySequenceParityTests: XCTestCase {

  final class Metrics: EditorMetricsContainer {
    var runs: [ReconcilerMetric] = []
    func record(_ metric: EditorMetric) { if case let .reconcilerRun(m) = metric { runs.append(m) } }
    func resetMetrics() { runs.removeAll() }
  }

  private func makeContexts() -> (opt: any ReadOnlyTextKitContextProtocol, leg: any ReadOnlyTextKitContextProtocol, metrics: Metrics) {
    let metrics = Metrics()
    let cfgOpt = EditorConfig(theme: Theme(), plugins: [], metricsContainer: metrics)
    let cfgLeg = EditorConfig(theme: Theme(), plugins: [])
    let opt = makeReadOnlyContext(editorConfig: cfgOpt, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let leg = makeReadOnlyContext(editorConfig: cfgLeg, featureFlags: FeatureFlags())
    return (opt, leg, metrics)
  }

  func testParity_MultiUpdateAttributeOnly_NoStringEdits() throws {
    let (opt, leg, metrics) = makeContexts()

    func seed(on editor: Editor, count: Int) throws {
      try editor.update {
        guard let root = getRoot() else { return }
        var nodes: [Node] = []
        for i in 0..<count { let p = createParagraphNode(); try p.append([ createTextNode(text: "P\(i)") ]); nodes.append(p) }
        try root.append(nodes)
      }
    }
    try seed(on: opt.editor, count: 20)
    try seed(on: leg.editor, count: 20)

    let beforeOpt = opt.textStorage.string
    let beforeLeg = leg.textStorage.string

    // 1) Bold all
    func toggleBold(on editor: Editor, value: Bool) throws {
      try editor.update {
        guard let root = getRoot() else { return }
        for case let p as ParagraphNode in root.getChildren() {
          if let t = p.getFirstChild() as? TextNode { try t.setBold(value) }
        }
      }
    }
    try toggleBold(on: opt.editor, value: true)
    try toggleBold(on: leg.editor, value: true)

    // 2) Italic all
    func toggleItalic(on editor: Editor, value: Bool) throws {
      try editor.update {
        guard let root = getRoot() else { return }
        for case let p as ParagraphNode in root.getChildren() {
          if let t = p.getFirstChild() as? TextNode { try t.setItalic(value) }
        }
      }
    }
    try toggleItalic(on: opt.editor, value: true)
    try toggleItalic(on: leg.editor, value: true)

    // 3) Remove bold
    try toggleBold(on: opt.editor, value: false)
    try toggleBold(on: leg.editor, value: false)

    let afterOpt = opt.textStorage.string
    let afterLeg = leg.textStorage.string

    XCTAssertEqual(beforeOpt, beforeLeg)
    XCTAssertEqual(afterOpt, afterLeg)
    XCTAssertEqual(beforeOpt, afterOpt)

    if let last = metrics.runs.last {
      XCTAssertEqual(last.deleteCount, 0)
      XCTAssertEqual(last.insertCount, 0)
    }
  }
}
