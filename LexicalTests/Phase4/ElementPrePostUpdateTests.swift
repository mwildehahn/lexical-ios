/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import Lexical
import XCTest

@MainActor
final class ElementPrePostUpdateTests: XCTestCase {

  func testPostambleUpdatesOnSiblingInsert_Optimized() throws {
    let flags = FeatureFlags(reconcilerMode: .optimized,
                             diagnostics: Diagnostics(selectionParity: false,
                                                       sanityChecks: false,
                                                       metrics: false,
                                                       verboseLogs: false))
    let view = LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: []),
                           featureFlags: flags)
    let editor = view.editor

    var p1Key: NodeKey = "", tKey: NodeKey = ""

    // Initial paragraph with text
    try editor.update {
      guard let root = getActiveEditorState()?.getRootNode() else { return }
      let p1 = ParagraphNode()
      let t = TextNode()
      try t.setText("Hi")
      try p1.append([t])
      try root.append([p1])
      p1Key = p1.getKey(); tKey = t.getKey()
    }

    // Sanity: leaf and element lengths before change
    try editor.read {
      guard let p1Item = editor.rangeCache[p1Key] else { return XCTFail("missing cache for p1") }
      guard let tItem = editor.rangeCache[tKey] else { return XCTFail("missing cache for text") }
      XCTAssertEqual(tItem.textLength, 2)
      XCTAssertEqual(p1Item.postambleLength, 0)
    }

    // Insert a sibling paragraph after p1 — previous sibling should gain a newline postamble
    try editor.update {
      guard let root = getActiveEditorState()?.getRootNode() else { return }
      let p2 = ParagraphNode()
      try root.append([p2])
    }

    try editor.read {
      guard let p1Item = editor.rangeCache[p1Key] else { return XCTFail("missing cache for p1 after insert") }
      guard let tItem = editor.rangeCache[tKey] else { return XCTFail("missing cache for text after insert") }
      // Leaf text remains 2; paragraph gains postamble 1 (newline)
      XCTAssertEqual(tItem.textLength, 2)
      XCTAssertEqual(p1Item.postambleLength, 1)
      // Root childrenLength should be at least p1’s total contribution after change
      guard let rootItem = editor.rangeCache[kRootNodeKey] else { return XCTFail("missing root cache") }
      let p1Total = p1Item.preambleLength + p1Item.childrenLength + p1Item.textLength + p1Item.postambleLength
      XCTAssertGreaterThanOrEqual(rootItem.childrenLength, p1Total)
    }
  }
}
