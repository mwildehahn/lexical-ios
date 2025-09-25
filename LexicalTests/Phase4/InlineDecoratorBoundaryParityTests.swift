/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import Lexical
import XCTest

@MainActor
final class InlineDecoratorBoundaryParityTests: XCTestCase {

  private func makeView(optimized: Bool, parity: Bool = true) -> LexicalView {
    let flags = FeatureFlags(
      reconcilerSanityCheck: true,
      optimizedReconciler: optimized,
      selectionParityDebug: parity
    )
    return LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: flags)
  }

  private func buildDoc(with editor: Editor) throws -> (ParagraphNode, TextNode, NodeKey, TextNode) {
    try editor.registerNode(nodeType: .testNode, class: TestDecoratorNode.self)

    var para = ParagraphNode()
    var t1 = TextNode(text: "AB", key: nil)
    var t2 = TextNode(text: "CD", key: nil)
    var dKey: NodeKey = ""

    try editor.update {
      guard let root = getActiveEditorState()?.getRootNode() else { return }
      let p = ParagraphNode()
      let left = TextNode(text: "AB", key: nil)
      let deco = TestDecoratorNode()
      let right = TextNode(text: "CD", key: nil)
      dKey = deco.getKey()
      try p.append([left, deco, right])
      try root.append([p])
      para = p; t1 = left; t2 = right
    }
    // Flush reconciliation
    try editor.update {}
    return (para, t1, dKey, t2)
  }

  private func buildDocDecoratorFirst(with editor: Editor) throws -> (ParagraphNode, NodeKey, TextNode) {
    try editor.registerNode(nodeType: .testNode, class: TestDecoratorNode.self)

    var para = ParagraphNode()
    var t = TextNode(text: "CD", key: nil)
    var dKey: NodeKey = ""

    try editor.update {
      guard let root = getActiveEditorState()?.getRootNode() else { return }
      let p = ParagraphNode()
      let deco = TestDecoratorNode()
      let right = TextNode(text: "CD", key: nil)
      dKey = deco.getKey()
      try p.append([deco, right])
      try root.append([p])
      para = p; t = right
    }
    try editor.update {}
    return (para, dKey, t)
  }

  /// Parity: selection spanning across an inline decorator yields the same native range length
  func testSpanAcrossInlineDecoratorParity() throws {
    let legacyView = makeView(optimized: false)
    let optView = makeView(optimized: true)
    let legacy = legacyView.editor
    let opt = optView.editor

    let (lPara, lT1, _, lT2) = try buildDoc(with: legacy)
    let (oPara, oT1, _, oT2) = try buildDoc(with: opt)
    _ = (lPara, oPara) // silence unused in some toolchains

    var lRange: NSRange = .init(location: 0, length: 0)
    var oRange: NSRange = .init(location: 0, length: 0)

    try legacy.read {
      let sel = RangeSelection(
        anchor: Point(key: lT1.getKey(), offset: 1, type: .text),
        focus: Point(key: lT2.getKey(), offset: 1, type: .text),
        format: TextFormat())
      lRange = try createNativeSelection(from: sel, editor: legacy).range ?? NSRange(location: 0, length: 0)
    }

    try opt.read {
      let sel = RangeSelection(
        anchor: Point(key: oT1.getKey(), offset: 1, type: .text),
        focus: Point(key: oT2.getKey(), offset: 1, type: .text),
        format: TextFormat())
      oRange = try createNativeSelection(from: sel, editor: opt).range ?? NSRange(location: 0, length: 0)
    }

    XCTAssertEqual(lRange.length, oRange.length, "Span across inline decorator must yield equal length in legacy vs optimized")
  }

  /// Parity: element offset mapping immediately before an inline decorator is consistent
  func testElementOffsetAroundInlineDecoratorParity() throws {
    let legacyView = makeView(optimized: false)
    let optView = makeView(optimized: true)
    let legacy = legacyView.editor
    let opt = optView.editor

    let (lPara, lT1, lDKey, _) = try buildDoc(with: legacy)
    let (oPara, oT1, oDKey, _) = try buildDoc(with: opt)

    var lRange: NSRange = .init(location: 0, length: 0)
    var oRange: NSRange = .init(location: 0, length: 0)

    try legacy.read {
      guard let latestP: ElementNode = getNodeByKey(key: lPara.getKey()) else { return }
      let decIndexLegacy = latestP.getChildrenKeys().firstIndex(of: lDKey) ?? 1
      let start = Point(key: latestP.getKey(), offset: decIndexLegacy, type: .element)
      let end = Point(key: lT1.getKey(), offset: 2, type: .text) // end of left text
      let sel = RangeSelection(anchor: start, focus: end, format: TextFormat())
      lRange = try createNativeSelection(from: sel, editor: legacy).range ?? NSRange(location: 0, length: 0)
    }

    try opt.read {
      guard let latestP: ElementNode = getNodeByKey(key: oPara.getKey()) else { return }
      let decIndexOpt = latestP.getChildrenKeys().firstIndex(of: oDKey) ?? 1
      let start = Point(key: latestP.getKey(), offset: decIndexOpt, type: .element)
      let end = Point(key: oT1.getKey(), offset: 2, type: .text)
      let sel = RangeSelection(anchor: start, focus: end, format: TextFormat())
      oRange = try createNativeSelection(from: sel, editor: opt).range ?? NSRange(location: 0, length: 0)
    }

    XCTAssertEqual(lRange.length, oRange.length, "Element offset at inline decorator boundary must map equivalently")
  }

  /// Parity: paragraph start boundary when first child is an inline decorator
  func testDecoratorAtParagraphStartBoundaryParity() throws {
    let legacyView = makeView(optimized: false)
    let optView = makeView(optimized: true)
    let legacy = legacyView.editor
    let opt = optView.editor

    let (lPara, _, lText) = try buildDocDecoratorFirst(with: legacy)
    let (oPara, _, oText) = try buildDocDecoratorFirst(with: opt)

    var lRange: NSRange = .init(location: 0, length: 0)
    var oRange: NSRange = .init(location: 0, length: 0)

    try legacy.read {
      // From paragraph element offset 0 (childrenStart) to first character of the right text
      let start = Point(key: lPara.getKey(), offset: 0, type: .element)
      let end = Point(key: lText.getKey(), offset: 1, type: .text)
      let sel = RangeSelection(anchor: start, focus: end, format: TextFormat())
      lRange = try createNativeSelection(from: sel, editor: legacy).range ?? NSRange(location: 0, length: 0)
    }

    try opt.read {
      let start = Point(key: oPara.getKey(), offset: 0, type: .element)
      let end = Point(key: oText.getKey(), offset: 1, type: .text)
      let sel = RangeSelection(anchor: start, focus: end, format: TextFormat())
      oRange = try createNativeSelection(from: sel, editor: opt).range ?? NSRange(location: 0, length: 0)
    }

    XCTAssertEqual(lRange.length, oRange.length, "Paragraph start before inline decorator must map equivalently")
  }
}
