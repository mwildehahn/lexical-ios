/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import Lexical
import XCTest

@MainActor
final class FenwickIndexOrderingTests: XCTestCase {

  func testAncestorFirstIndexAndElementStartLocation() throws {
    let ctx = LexicalReadOnlyTextKitContext(
      editorConfig: EditorConfig(theme: Theme(), plugins: []),
      featureFlags: FeatureFlags(optimizedReconciler: true)
    )
    let editor = ctx.editor

    var paragraphKey: NodeKey = ""
    var textKey: NodeKey = ""

    try editor.update {
      guard let root = getActiveEditorState()?.getRootNode() else { return }
      let p = ParagraphNode()
      let t = TextNode(text: "Hi", key: nil)
      try p.append([t])
      try root.append([p])
      paragraphKey = p.getKey()
      textKey = t.getKey()
    }

    // Ensure caches are populated
    try editor.update {}

    // 1) Ancestor-first index assignment: paragraph should have a lower Fenwick index than its child
    guard let pIdx = editor.fenwickIndexMap[paragraphKey], let tIdx = editor.fenwickIndexMap[textKey] else {
      return XCTFail("Missing Fenwick indices for nodes")
    }
    XCTAssertLessThan(pIdx, tIdx, "Ancestor (paragraph) index should be assigned before child (text)")

    // 2) Element start location round-trip: Fenwick-based location equals element offset(0) location
    try editor.read {
      guard let pItem = editor.rangeCache[paragraphKey] else { return XCTFail("Missing paragraph range cache") }
      let fenwickLoc = pItem.locationFromFenwick(using: editor.fenwickTree)
      let elemLoc = try stringLocationForPoint(Point(key: paragraphKey, offset: 0, type: .element), editor: editor)
      XCTAssertEqual(elemLoc, fenwickLoc, "Element start should match Fenwick-computed start location")
    }
  }
}

