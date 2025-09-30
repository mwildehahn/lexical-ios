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

  func testInsertNewlineInMiddleSplitsParagraph() throws {
    let (editor, frontend) = makeOptimizedEditor(); _ = frontend
    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode(); let t = createTextNode(text: "HelloWorld")
      try p.append([t]); try root.append([p])
      try t.select(anchorOffset: 5, focusOffset: 5)
      try (getSelection() as? RangeSelection)?.insertParagraph()
    }
    try editor.read {
      XCTAssertEqual(getRoot()?.getTextContent(), "Hello\nWorld")
      guard let root = getRoot(), let p2 = root.getLastChild() as? ParagraphNode,
            let sel = try getSelection() as? RangeSelection else { return }
      // Caret at start of second paragraph
      XCTAssertEqual(sel.anchor.key, sel.focus.key)
      if let t2 = p2.getFirstChild() as? TextNode {
        XCTAssertEqual(sel.anchor.offset, 0)
        XCTAssertEqual(sel.focus.offset, 0)
        XCTAssertEqual(t2.getTextPart(), "World")
      }
    }
  }

  func testForwardDeleteAtEndMergesNextParagraph() throws {
    let (editor, frontend) = makeOptimizedEditor(); _ = frontend
    try editor.update {
      guard let root = getRoot() else { return }
      let p1 = createParagraphNode(); let t1 = createTextNode(text: "Hello")
      let p2 = createParagraphNode(); let t2 = createTextNode(text: "World")
      try p1.append([t1]); try p2.append([t2]); try root.append([p1, p2])
      try t1.select(anchorOffset: 5, focusOffset: 5)
    }
    try editor.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: false) }
    try editor.read {
      XCTAssertEqual(getRoot()?.getTextContent(), "HelloWorld")
      guard let root = getRoot(), let p = root.getFirstChild() as? ParagraphNode,
            let t = p.getFirstChild() as? TextNode,
            let sel = try getSelection() as? RangeSelection else { return }
      XCTAssertEqual(t.getTextPart(), "HelloWorld")
      XCTAssertTrue(sel.anchor.key == sel.focus.key)
      XCTAssertEqual(sel.anchor.offset, 5)
    }
  }

  func testBackspaceAtStartMergesWithPreviousParagraph() throws {
    let (editor, frontend) = makeOptimizedEditor(); _ = frontend
    try editor.update {
      guard let root = getRoot() else { return }
      let p1 = createParagraphNode(); let t1 = createTextNode(text: "Hello")
      let p2 = createParagraphNode(); let t2 = createTextNode(text: "World")
      try p1.append([t1]); try p2.append([t2]); try root.append([p1, p2])
      try t2.select(anchorOffset: 0, focusOffset: 0)
    }
    try editor.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
    try editor.read {
      XCTAssertEqual(getRoot()?.getTextContent(), "HelloWorld")
      guard let root = getRoot(), let p = root.getFirstChild() as? ParagraphNode,
            let t = p.getFirstChild() as? TextNode,
            let sel = try getSelection() as? RangeSelection else { return }
      XCTAssertEqual(t.getTextPart(), "HelloWorld")
      XCTAssertTrue(sel.anchor.key == sel.focus.key)
      XCTAssertEqual(sel.anchor.offset, 5)
    }
  }

  func testForwardDeleteInsideTextDoesNotDeleteWholeLine() throws {
    let (editor, _) = makeOptimizedEditor()
    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode(); let t = createTextNode(text: "The quick brown fox")
      try p.append([t]); try root.append([p])
      // Caret inside the word "quick" (between 'q' and 'u')
      try t.select(anchorOffset: 5, focusOffset: 5)
    }
    try editor.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: false) }
    try editor.read {
      guard let root = getRoot(), let p = root.getFirstChild() as? ParagraphNode,
            let t = p.getFirstChild() as? TextNode else { return XCTFail("Unexpected tree") }
      XCTAssertEqual(root.getChildrenSize(), 1)
      XCTAssertEqual(t.getTextPart(), "The qick brown fox") // 'u' removed only
    }
  }

  func testBackspaceInsideTextDoesNotDeleteWholeLine() throws {
    let (editor, _) = makeOptimizedEditor()
    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode(); let t = createTextNode(text: "Hello World")
      try p.append([t]); try root.append([p])
      // Caret after 'o' in Hello (index 5)
      try t.select(anchorOffset: 5, focusOffset: 5)
    }
    try editor.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
    try editor.read {
      guard let root = getRoot(), let p = root.getFirstChild() as? ParagraphNode,
            let t = p.getFirstChild() as? TextNode else { return XCTFail("Unexpected tree") }
      XCTAssertEqual(root.getChildrenSize(), 1)
      XCTAssertEqual(t.getTextPart(), "Hell World") // backspace removed the 'o'
    }
  }
}
