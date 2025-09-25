/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import Lexical
import XCTest

@MainActor
final class IncrementalUpdaterTextLengthTests: XCTestCase {

  func testTextInsertionKeepsLeafLengths() throws {
    let flags = FeatureFlags(optimizedReconciler: true)
    let ctx = LexicalReadOnlyTextKitContext(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: flags)
    let editor = ctx.editor

    var t1: TextNode = TextNode(text: "", key: nil)
    var t2: TextNode = TextNode(text: "", key: nil)
    var originalText: [NodeKey: String] = [:]

    try editor.update {
      guard let root = getActiveEditorState()?.getRootNode() else { return }
      let p = ParagraphNode()
      let n1 = TextNode(text: "ab", key: nil)
      let n2 = TextNode(text: "cd", key: nil)
      try p.append([n1, n2])
      try root.append([p])
      t1 = n1; t2 = n2
      // Capture original texts before any normalization could merge nodes
      originalText[n1.getKey()] = n1.getText_dangerousPropertyAccess()
      originalText[n2.getKey()] = n2.getText_dangerousPropertyAccess()
    }
    // Trigger a no-op update (may merge adjacent text in editor state), but
    // our synthetic deltas will use the captured original texts.
    try editor.update {}

    // Build synthetic deltas using original leaf texts, not potentially-merged state
    func ins(_ nodeKey: NodeKey, at loc: Int) -> ReconcilerDelta {
      let pre = NSAttributedString(string: "")
      let content = NSAttributedString(string: originalText[nodeKey] ?? "")
      let post = NSAttributedString(string: "")
      let ins = NodeInsertionData(preamble: pre, content: content, postamble: post, nodeKey: nodeKey)
      return ReconcilerDelta(type: .nodeInsertion(nodeKey: nodeKey, insertionData: ins, location: loc), metadata: DeltaMetadata(sourceUpdate: "test"))
    }
    // Assume t1 at 0, t2 at 2
    let deltas = [ins(t1.getKey(), at: 0), ins(t2.getKey(), at: 2)]

    var cache = editor.rangeCache
    let updater = IncrementalRangeCacheUpdater(editor: editor, fenwickTree: editor.fenwickTree)
    try updater.updateRangeCache(&cache, basedOn: deltas)

    // After update, leaf lengths must match original leaf text
    guard let c1 = cache[t1.getKey()], let c2 = cache[t2.getKey()] else { return XCTFail("missing cache leaves") }
    XCTAssertEqual(c1.textLength, 2)
    XCTAssertEqual(c2.textLength, 2)

    // Running the updater again must be idempotent
    try updater.updateRangeCache(&cache, basedOn: deltas)
    XCTAssertEqual(cache[t1.getKey()]?.textLength, 2)
    XCTAssertEqual(cache[t2.getKey()]?.textLength, 2)
  }
}
