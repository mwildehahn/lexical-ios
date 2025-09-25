/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 */

@testable import Lexical
import XCTest

@MainActor
final class RangeCacheStaleEntriesTests: XCTestCase {
  func testNoStaleRangeCacheAfterMerge() throws {
    func build(_ optimized: Bool) throws -> (Editor, NodeKey, NodeKey, NodeKey) {
      let ctx = LexicalReadOnlyTextKitContext(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags(optimizedReconciler: optimized))
      let ed = ctx.editor
      var p: NodeKey = "", t1: NodeKey = "", t2: NodeKey = ""
      try ed.update {
        guard let root = getActiveEditorState()?.getRootNode() else { return }
        let para = ParagraphNode()
        let a = TextNode(text: "ab", key: nil)
        let b = TextNode(text: "cd", key: nil)
        try para.append([a, b])
        try root.append([para])
        p = para.getKey(); t1 = a.getKey(); t2 = b.getKey()
      }
      try ed.update {}
      return (ed, p, t1, t2)
    }
    let (legacy, lp, lt1, lt2) = try build(false)
    let (opt, op, ot1, ot2) = try build(true)

    func assertNoStale(_ ed: Editor, _ p: NodeKey, _ k1: NodeKey, _ k2: NodeKey) throws {
      try ed.read {
        guard let para = getNodeByKey(key: p) as? ElementNode else { return XCTFail("no paragraph") }
        let keys = para.getChildren().compactMap{ ($0 as? Node)?.getKey() }
        if keys.count == 1 {
          let survivor = keys[0]
          let removed = (survivor == k1) ? k2 : k1
          XCTAssertNotNil(ed.rangeCache[survivor], "cache for survivor exists")
          XCTAssertNil(ed.rangeCache[removed], "removed key must not remain in rangeCache")
        } else if keys.count == 2 {
          XCTAssertNotNil(ed.rangeCache[k1])
          XCTAssertNotNil(ed.rangeCache[k2])
        } else {
          XCTFail("unexpected children count: \(keys.count)")
        }
      }
    }

    try assertNoStale(legacy, lp, lt1, lt2)
    try assertNoStale(opt, op, ot1, ot2)
  }
}

