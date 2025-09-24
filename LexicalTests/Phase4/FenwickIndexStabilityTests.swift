/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import Lexical
import XCTest

@MainActor
final class FenwickIndexStabilityTests: XCTestCase {

  func testDeleteAndReinsertKeepsExistingIndicesStable() throws {
    let ctx = LexicalReadOnlyTextKitContext(
      editorConfig: EditorConfig(theme: Theme(), plugins: []),
      featureFlags: FeatureFlags(optimizedReconciler: true)
    )
    let editor = ctx.editor

    var p1: ParagraphNode = ParagraphNode()
    var p2: ParagraphNode = ParagraphNode()
    var t1Key: NodeKey = ""

    try editor.update {
      guard let root = getActiveEditorState()?.getRootNode() else { return }
      let pA = ParagraphNode(); let tA = TextNode(text: "A", key: nil); try pA.append([tA])
      let pB = ParagraphNode(); let tB = TextNode(text: "B", key: nil); try pB.append([tB])
      try root.append([pA, pB])
      p1 = pA; p2 = pB; t1Key = tA.getKey()
    }
    try editor.update {}

    guard let p1IdxBefore = editor.fenwickIndexMap[p1.getKey()],
          let p2IdxBefore = editor.fenwickIndexMap[p2.getKey()] else {
      return XCTFail("Missing initial indices")
    }

    // Delete second paragraph and insert a new third one
    var newPKey: NodeKey = ""
    try editor.update {
      try p2.remove()
      guard let root = getActiveEditorState()?.getRootNode() else { return }
      let p3 = ParagraphNode(); let t3 = TextNode(text: "C", key: nil); try p3.append([t3])
      try root.append([p3])
      newPKey = p3.getKey()
    }

    try editor.update {}

    // Existing paragraph’s index should remain the same
    XCTAssertEqual(editor.fenwickIndexMap[p1.getKey()], p1IdxBefore)

    // New paragraph should get a strictly larger index than any existing
    guard let newIdx = editor.fenwickIndexMap[newPKey] else { return XCTFail("Missing new index") }
    XCTAssertGreaterThan(newIdx, max(p1IdxBefore, p2IdxBefore))

    // Element start location parity for p1 should remain valid
    try editor.read {
      guard let item = editor.rangeCache[p1.getKey()] else { return XCTFail("Missing cache for p1") }
      let fenwickLoc = item.locationFromFenwick(using: editor.fenwickTree)
      let elemLoc = try stringLocationForPoint(Point(key: p1.getKey(), offset: 0, type: .element), editor: editor)
      XCTAssertEqual(elemLoc, fenwickLoc)
    }
  }
}

