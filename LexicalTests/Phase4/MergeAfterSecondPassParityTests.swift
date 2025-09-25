/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 */

@testable import Lexical
import XCTest

@MainActor
final class MergeAfterSecondPassParityTests: XCTestCase {
  func testAdjacentTextNodesMergeParityAfterSecondPass() throws {
    func build(_ optimized: Bool) throws -> (Editor, NodeKey) {
      let ctx = LexicalReadOnlyTextKitContext(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags(optimizedReconciler: optimized))
      let ed = ctx.editor
      var pKey: NodeKey = ""
      try ed.update {
        guard let root = getActiveEditorState()?.getRootNode() else { return }
        let p = ParagraphNode()
        try p.append([TextNode(text: "ab", key: nil), TextNode(text: "cd", key: nil)])
        try root.append([p])
        pKey = p.getKey()
      }
      // Second pass to populate caches/normalization like other tests do
      try ed.update {}
      return (ed, pKey)
    }

    let (legacy, lp) = try build(false)
    let (opt, op) = try build(true)

    var lc = -1, oc = -1
    try legacy.read {
      guard let p = getNodeByKey(key: lp) as? ElementNode else { return XCTFail("legacy: no paragraph") }
      lc = p.getChildren().count
    }
    try opt.read {
      guard let p = getNodeByKey(key: op) as? ElementNode else { return XCTFail("opt: no paragraph") }
      oc = p.getChildren().count
    }

    XCTAssertEqual(lc, oc, "Legacy vs Optimized must agree on whether adjacent simple TextNodes merge after second pass")
  }
}

