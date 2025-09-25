/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import Lexical
import XCTest

@MainActor
final class RangeCacheTextLengthsParityTests: XCTestCase {

  private func buildTwoTexts(_ editor: Editor) throws -> (NodeKey, NodeKey, NodeKey) {
    var pKey: NodeKey = "", t1: NodeKey = "", t2: NodeKey = ""
    try editor.update {
      guard let root = getActiveEditorState()?.getRootNode() else { return }
      let p = ParagraphNode()
      let n1 = TextNode(text: "ab", key: nil)
      let n2 = TextNode(text: "cd", key: nil)
      try p.append([n1, n2])
      try root.append([p])
      pKey = p.getKey(); t1 = n1.getKey(); t2 = n2.getKey()
    }
    try editor.update {}
    return (pKey, t1, t2)
  }

  func testLegacyVsOptimizedTextLengthsParity() throws {
    func state(_ optimized: Bool) throws -> (Editor, NodeKey, NodeKey, NodeKey) {
      let ctx = LexicalReadOnlyTextKitContext(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags(optimizedReconciler: optimized))
      let ed = ctx.editor
      let (p, t1, t2) = try buildTwoTexts(ed)
      return (ed, p, t1, t2)
    }
    let (led, lp, lt1, lt2) = try state(false)
    let (oed, op, ot1, ot2) = try state(true)

    var lc = -1, oc = -1
    try led.read { lc = (getNodeByKey(key: lp) as? ElementNode)?.getChildren().count ?? -1 }
    try oed.read { oc = (getNodeByKey(key: op) as? ElementNode)?.getChildren().count ?? -1 }
    XCTAssertEqual(lc, oc)

    if lc == 2 {
      try led.read {
        guard let c1 = led.rangeCache[lt1], let c2 = led.rangeCache[lt2] else { return XCTFail("legacy: missing cache for both children") }
        XCTAssertEqual(c1.textLength, 2); XCTAssertEqual(c2.textLength, 2)
      }
      try oed.read {
        guard let c1 = oed.rangeCache[ot1], let c2 = oed.rangeCache[ot2] else { return XCTFail("opt: missing cache for both children") }
        XCTAssertEqual(c1.textLength, 2); XCTAssertEqual(c2.textLength, 2)
      }
    } else if lc == 1 {
      func checkMerged(_ ed: Editor, _ p: NodeKey, _ t1: NodeKey, _ t2: NodeKey) throws {
        try ed.read {
          guard let para = getNodeByKey(key: p) as? ElementNode, let child = para.getChildren().first as? TextNode else { return XCTFail("missing merged child") }
          let removed = (child.getKey() == t1) ? t2 : t1
          XCTAssertNil(ed.rangeCache[removed], "removed key must not remain in cache")
          guard let c = ed.rangeCache[child.getKey()] else { return XCTFail("missing cache for merged child") }
          XCTAssertEqual(c.textLength, 4)
        }
      }
      try checkMerged(led, lp, lt1, lt2)
      try checkMerged(oed, op, ot1, ot2)
    } else {
      XCTFail("unexpected children count: \(lc)")
    }
  }
}
