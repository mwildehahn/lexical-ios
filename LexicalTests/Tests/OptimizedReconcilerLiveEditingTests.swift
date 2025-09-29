/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import Lexical
import XCTest

final class OptimizedReconcilerLiveEditingTests: XCTestCase {

  private func makeOptimizedEditor() -> (Editor, LexicalReadOnlyTextKitContext) {
    let flags = FeatureFlags.optimizedProfile(.aggressiveEditor)
    let ctx = LexicalReadOnlyTextKitContext(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: flags)
    return (ctx.editor, ctx)
  }

  func testTypingDoesNotDuplicateCharacters() throws {
    let (editor, frontend) = makeOptimizedEditor()
    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode()
      let t = createTextNode(text: "")
      try p.append([t]); try root.append([p])
      try t.select(anchorOffset: 0, focusOffset: 0)
      try (getSelection() as? RangeSelection)?.insertText("H")
      try (getSelection() as? RangeSelection)?.insertText("e")
      try (getSelection() as? RangeSelection)?.insertText("y")
    }
    XCTAssertTrue(frontend.textStorage.string.hasSuffix("Hey"))
    try editor.read {
      guard let sel = try getSelection() as? RangeSelection else { return XCTFail("Need selection") }
      XCTAssertEqual(sel.anchor.offset, 3)
      XCTAssertEqual(sel.focus.offset, 3)
    }
  }

  func testBackspaceDeletesSingleCharacterOnly() throws {
    let (editor, frontend) = makeOptimizedEditor()
    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode(); let t = createTextNode(text: "Hey")
      try p.append([t]); try root.append([p])
      try t.select(anchorOffset: 3, focusOffset: 3)
    }
    try editor.update {
      guard let root = getRoot(), let p = root.getLastChild() as? ParagraphNode,
            let t = p.getFirstChild() as? TextNode else { return }
      try t.setText("He")
    }
    try editor.read {
      guard let root = getRoot(), let p = root.getLastChild() as? ParagraphNode else { return XCTFail("Tree shape unexpected") }
      XCTAssertEqual(p.getTextContent(), "He")
    }
    try editor.update {
      guard let root = getRoot(), let p = root.getLastChild() as? ParagraphNode,
            let t = p.getFirstChild() as? TextNode else { return }
      try t.setText("H")
    }
    try editor.read {
      guard let root = getRoot(), let p = root.getLastChild() as? ParagraphNode else { return XCTFail("Tree shape unexpected") }
      XCTAssertEqual(p.getTextContent(), "H")
    }
    try editor.update {
      guard let root = getRoot(), let p = root.getLastChild() as? ParagraphNode,
            let t = p.getFirstChild() as? TextNode else { return }
      try t.setText("")
    }
    try editor.read {
      guard let root = getRoot(), let p = root.getLastChild() as? ParagraphNode else { return XCTFail("Tree shape unexpected") }
      XCTAssertEqual(p.getChildren().count, 0)
    }
  }

  func testInsertNewlineCreatesNewParagraphAndKeepsCaret() throws {
    let (editor, frontend) = makeOptimizedEditor()
    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode(); let t = createTextNode(text: "Hello")
      try p.append([t]); try root.append([p])
      try t.select(anchorOffset: 5, focusOffset: 5)
      try (getSelection() as? RangeSelection)?.insertParagraph()
    }
    try editor.update { try (getSelection() as? RangeSelection)?.insertText("Hey") }
    try editor.read {
      guard let root = getRoot() else { return XCTFail("No root") }
      XCTAssertEqual(root.getTextContent(), "Hello\nHey")
    }
  }

  func testLegacyParityBackspaceSingleChar() throws {
    // Legacy flags: ensure single char delete works identically
    let ctx = LexicalReadOnlyTextKitContext(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags())
    let editor = ctx.editor
    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode(); let t = createTextNode(text: "Hey")
      try p.append([t]); try root.append([p])
      try t.setText("He")
    }
    try editor.read {
      guard let root = getRoot(), let p = root.getLastChild() as? ParagraphNode else { return XCTFail("Tree shape unexpected") }
      XCTAssertEqual(p.getTextContent(), "He")
    }
  }
}
