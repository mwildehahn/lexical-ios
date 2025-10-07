/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import Lexical
@testable import LexicalUIKit
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
    // Retain the frontend so the Editor keeps a valid textStorage during updates.
    let (editor, frontend) = makeOptimizedEditor(); _ = frontend
    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode(); let t = createTextNode(text: "The quick brown fox")
      try p.append([t]); try root.append([p])
      // Caret inside the word "quick" (between 'q' and 'u')
      try t.select(anchorOffset: 5, focusOffset: 5)
    }
    try editor.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: false) }
    try editor.read {
      let docText = getRoot()?.getTextContent() ?? "<nil>"
      let childCount = getRoot()?.getChildrenSize() ?? -1
      if childCount != 1, let root = getRoot() {
        let types = root.getChildren().map { type(of: $0) }
        print("🔥 TEST DEBUG: children types=\(types)")
      }
      XCTAssertEqual(docText, "The qick brown fox", "docText=\(docText) children=\(childCount)")
      if let p = getRoot()?.getFirstChild() as? ParagraphNode,
         let t = p.getFirstChild() as? TextNode {
        XCTAssertEqual(t.getTextPart(), "The qick brown fox")
      }
    }
  }

  func testBackspaceInsideTextDoesNotDeleteWholeLine() throws {
    // Retain the frontend so the Editor keeps a valid textStorage during updates.
    let (editor, frontend) = makeOptimizedEditor(); _ = frontend
    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode(); let t = createTextNode(text: "Hello World")
      try p.append([t]); try root.append([p])
      // Caret after 'o' in Hello (index 5)
      try t.select(anchorOffset: 5, focusOffset: 5)
    }
    try editor.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
    try editor.read {
      let docText = getRoot()?.getTextContent() ?? "<nil>"
      let childCount = getRoot()?.getChildrenSize() ?? -1
      if childCount != 1, let root = getRoot() {
        let types = root.getChildren().map { type(of: $0) }
        print("🔥 TEST DEBUG: children types=\(types)")
      }
      XCTAssertEqual(docText, "Hell World", "docText=\(docText) children=\(childCount)")
      if let p = getRoot()?.getFirstChild() as? ParagraphNode,
         let t = p.getFirstChild() as? TextNode {
        XCTAssertEqual(t.getTextPart(), "Hell World")
      }
    }
  }

  func testBackspaceInsideTextTwiceRemovesTwoCharactersOnly() throws {
    // Retain frontend to keep textStorage alive.
    let (editor, frontend) = makeOptimizedEditor(); _ = frontend
    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode(); let t = createTextNode(text: "abcdef")
      try p.append([t]); try root.append([p])
      // Caret after 'd' at index 4
      try t.select(anchorOffset: 4, focusOffset: 4)
    }
    // Backspace twice
    try editor.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
    try editor.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
    try editor.read {
      let docText = getRoot()?.getTextContent() ?? "<nil>"
      XCTAssertEqual(docText, "abef")
      if let sel = try getSelection() as? RangeSelection {
        XCTAssertEqual(sel.anchor.offset, 2)
        XCTAssertEqual(sel.focus.offset, 2)
      }
    }
  }

  func testForwardDeleteInsideTextTwiceRemovesTwoCharactersOnly() throws {
    // Retain frontend to keep textStorage alive.
    let (editor, frontend) = makeOptimizedEditor(); _ = frontend
    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode(); let t = createTextNode(text: "abcdef")
      try p.append([t]); try root.append([p])
      // Caret at index 2 (before 'c')
      try t.select(anchorOffset: 2, focusOffset: 2)
    }
    // Forward delete twice
    try editor.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: false) }
    try editor.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: false) }
    try editor.read {
      let docText = getRoot()?.getTextContent() ?? "<nil>"
      XCTAssertEqual(docText, "abef")
      if let sel = try getSelection() as? RangeSelection {
        XCTAssertEqual(sel.anchor.offset, 2)
        XCTAssertEqual(sel.focus.offset, 2)
      }
    }
  }

  func testBackspaceAtAbsoluteDocumentStartIsNoOp() throws {
    let (editor, frontend) = makeOptimizedEditor(); _ = frontend
    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode(); let t = createTextNode(text: "Hello")
      try p.append([t]); try root.append([p])
      try t.select(anchorOffset: 0, focusOffset: 0)
    }
    try editor.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
    try editor.read {
      XCTAssertEqual(getRoot()?.getTextContent(), "Hello")
      if let sel = try getSelection() as? RangeSelection {
        XCTAssertEqual(sel.anchor.offset, 0)
        XCTAssertEqual(sel.focus.offset, 0)
      }
    }
  }

  func testForwardDeleteAtAbsoluteDocumentEndIsNoOp() throws {
    let (editor, frontend) = makeOptimizedEditor(); _ = frontend
    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode(); let t = createTextNode(text: "Hello")
      try p.append([t]); try root.append([p])
      try t.select(anchorOffset: 5, focusOffset: 5)
    }
    try editor.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: false) }
    try editor.read {
      XCTAssertEqual(getRoot()?.getTextContent(), "Hello")
      if let sel = try getSelection() as? RangeSelection {
        XCTAssertEqual(sel.anchor.offset, 5)
        XCTAssertEqual(sel.focus.offset, 5)
      }
    }
  }

  func testBackspaceRemovesWholeGrapheme_CombiningMark() throws {
    let (editor, frontend) = makeOptimizedEditor(); _ = frontend
    let combining = "e\u{0301}" // e + combining acute
    let text = "ab" + combining + "cd"
    let caretAfter = ("ab" + combining as NSString).length
    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode(); let t = createTextNode(text: text)
      try p.append([t]); try root.append([p])
      // Manually select the whole grapheme cluster and delete via insertText("")
      if let sel = try getSelection() as? RangeSelection {
        sel.anchor.updatePoint(key: t.getKey(), offset: caretAfter - (combining as NSString).length, type: .text)
        sel.focus.updatePoint(key: t.getKey(), offset: caretAfter, type: .text)
      }
    }
    try editor.update { try (getSelection() as? RangeSelection)?.insertText("") }
    try editor.read {
      XCTAssertEqual(getRoot()?.getTextContent(), "abcd")
      if let sel = try getSelection() as? RangeSelection { XCTAssertEqual(sel.anchor.offset, 2) }
    }
  }

  func testBackspaceRemovesWholeGrapheme_ZWJEmojiFamily() throws {
    let (editor, frontend) = makeOptimizedEditor(); _ = frontend
    let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}" // 👨‍👩‍👧
    let prefix = "hi" + family
    let text = prefix + "world"
    let caretAfter = (prefix as NSString).length
    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode(); let t = createTextNode(text: text)
      try p.append([t]); try root.append([p])
      if let sel = try getSelection() as? RangeSelection {
        sel.anchor.updatePoint(key: t.getKey(), offset: caretAfter - (family as NSString).length, type: .text)
        sel.focus.updatePoint(key: t.getKey(), offset: caretAfter, type: .text)
      }
    }
    try editor.update { try (getSelection() as? RangeSelection)?.insertText("") }
    try editor.read {
      XCTAssertEqual(getRoot()?.getTextContent(), "hiworld")
      if let sel = try getSelection() as? RangeSelection { XCTAssertEqual(sel.anchor.offset, 2) }
    }
  }

  func testMultiNodeEditsInSingleUpdate_TextOnly() throws {
    let (editor, frontend) = makeOptimizedEditor(); _ = frontend
    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode()
      let t1 = createTextNode(text: "Hello")
      let t2 = createTextNode(text: " Brave ")
      let t3 = createTextNode(text: "World")
      try p.append([t1, t2, t3]); try root.append([p])
      // Place caret inside t2 before edits
      try t2.select(anchorOffset: 1, focusOffset: 1)
      // Single update mutating three nodes
      try t1.setText("Hello!")
      try t2.setText(" Brief ") // Brave -> Brief
      try t3.setText("Wor")      // trim tail
    }
    try editor.read { XCTAssertEqual(getRoot()?.getTextContent(), "Hello! Brief Wor") }
  }

  func testStructuralAndTextInSameUpdate_InsertParagraphAndEdit() throws {
    let (editor, frontend) = makeOptimizedEditor(); _ = frontend
    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode(); let t = createTextNode(text: "HelloWorld")
      try p.append([t]); try root.append([p])
      try t.select(anchorOffset: 5, focusOffset: 5)
      // Insert paragraph and also edit neighbors in one update
      try (getSelection() as? RangeSelection)?.insertParagraph()
      // Edit left side: add space after Hello
      if let p1 = root.getFirstChild() as? ParagraphNode, let tl = p1.getFirstChild() as? TextNode {
        try tl.setText("Hello ")
      }
      // Edit right side: ensure World unchanged
    }
    try editor.read { XCTAssertEqual(getRoot()?.getTextContent(), "Hello\nWorld") }
  }

  func testSelectionStabilityUnderUnrelatedEdits() throws {
    let (editor, frontend) = makeOptimizedEditor(); _ = frontend
    try editor.update {
      guard let root = getRoot() else { return }
      // Build 5 paragraphs
      for i in 0..<5 {
        let p = createParagraphNode(); let t = createTextNode(text: "Para \(i)")
        try p.append([t]); try root.append([p])
      }
      // Put caret in first paragraph at offset 2
      if let p0 = root.getFirstChild() as? ParagraphNode, let t0 = p0.getFirstChild() as? TextNode {
        try t0.select(anchorOffset: 2, focusOffset: 2)
      }
    }
    // Apply unrelated edits to later paragraphs in one update
    try editor.update {
      guard let root = getRoot() else { return }
      if let p3 = root.getChildAtIndex(index: 3) as? ParagraphNode, let t3 = p3.getFirstChild() as? TextNode {
        try t3.setText("Para 3 extended")
      }
      if let p4 = root.getChildAtIndex(index: 4) as? ParagraphNode, let t4 = p4.getFirstChild() as? TextNode {
        try t4.setText("Para 4 appended!")
      }
    }
    try editor.read {
      guard let sel = try getSelection() as? RangeSelection else { return XCTFail("Need range selection") }
      XCTAssertTrue(sel.isCollapsed())
    }
  }

  func testDeleteSelectionAcrossSiblingTextNodesMerges() throws {
    let (editor, frontend) = makeOptimizedEditor(); _ = frontend
    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode()
      let t1 = createTextNode(text: "Hello")
      let t2 = createTextNode(text: "World")
      try p.append([t1, t2]); try root.append([p])
      // Select "loWo"
      try t1.select(anchorOffset: 3, focusOffset: 5)
      if let sel = try getSelection() as? RangeSelection {
        sel.focus.updatePoint(key: t2.getKey(), offset: 2, type: .text)
      }
    }
    try editor.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
    try editor.read {
      XCTAssertEqual(getRoot()?.getTextContent(), "Helrld")
      if let sel = try getSelection() as? RangeSelection {
        XCTAssertTrue(sel.isCollapsed())
        XCTAssertEqual(sel.anchor.offset, 3)
      }
    }
  }

  func testBackspaceAtStartOfSecondTextNodeDeletesPrevChar() throws {
    let (editor, frontend) = makeOptimizedEditor(); _ = frontend
    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode()
      let t1 = createTextNode(text: "Hello")
      let t2 = createTextNode(text: "World")
      try p.append([t1, t2]); try root.append([p])
      try t2.select(anchorOffset: 0, focusOffset: 0)
    }
    try editor.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
    try editor.read {
      // Behavior: backspace at start of second text deletes previous character in first text node.
      XCTAssertEqual(getRoot()?.getTextContent(), "HellWorld")
      if let sel = try getSelection() as? RangeSelection { XCTAssertEqual(sel.anchor.offset, 4) }
    }
  }

  func testForwardDeleteAtEndOfFirstTextNodeDeletesNextChar() throws {
    let (editor, frontend) = makeOptimizedEditor(); _ = frontend
    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode()
      let t1 = createTextNode(text: "Hello")
      let t2 = createTextNode(text: "World")
      try p.append([t1, t2]); try root.append([p])
      try t1.select(anchorOffset: 5, focusOffset: 5)
    }
    try editor.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: false) }
    try editor.read {
      // Behavior: forward delete at end deletes first character of next text node.
      XCTAssertEqual(getRoot()?.getTextContent(), "Helloorld")
      if let sel = try getSelection() as? RangeSelection { XCTAssertEqual(sel.anchor.offset, 5) }
    }
  }

  func testDeleteSelectionAcrossParagraphBoundaryMergesParagraphs() throws {
    let (editor, frontend) = makeOptimizedEditor(); _ = frontend
    try editor.update {
      guard let root = getRoot() else { return }
      let p1 = createParagraphNode(); let t1 = createTextNode(text: "Hello")
      let p2 = createParagraphNode(); let t2 = createTextNode(text: "World")
      try p1.append([t1]); try p2.append([t2]); try root.append([p1, p2])
      // Select "lo\nWo" (last 2 of p1 and first 2 of p2)
      try t1.select(anchorOffset: 3, focusOffset: 5)
      if let sel = try getSelection() as? RangeSelection {
        sel.focus.updatePoint(key: t2.getKey(), offset: 2, type: .text)
      }
    }
    try editor.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
    try editor.read {
      XCTAssertEqual(getRoot()?.getTextContent(), "Helrld")
      if let sel = try getSelection() as? RangeSelection { XCTAssertEqual(sel.anchor.offset, 3) }
    }
  }

  func testBackspaceAcrossLineBreakMergesLines() throws {
    let (editor, frontend) = makeOptimizedEditor(); _ = frontend
    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode()
      let t1 = createTextNode(text: "Hello")
      let br = LineBreakNode()
      let t2 = createTextNode(text: "World")
      try p.append([t1, br, t2]); try root.append([p])
      try t2.select(anchorOffset: 0, focusOffset: 0)
    }
    try editor.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
    try editor.read {
      XCTAssertEqual(getRoot()?.getTextContent(), "HelloWorld")
      if let sel = try getSelection() as? RangeSelection { XCTAssertEqual(sel.anchor.offset, 5) }
    }
  }

  func testForwardDeleteAcrossLineBreakMergesLines() throws {
    let (editor, frontend) = makeOptimizedEditor(); _ = frontend
    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode()
      let t1 = createTextNode(text: "Hello")
      let br = LineBreakNode()
      let t2 = createTextNode(text: "World")
      try p.append([t1, br, t2]); try root.append([p])
      try t1.select(anchorOffset: 5, focusOffset: 5)
    }
    try editor.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: false) }
    try editor.read {
      XCTAssertEqual(getRoot()?.getTextContent(), "HelloWorld")
      if let sel = try getSelection() as? RangeSelection { XCTAssertEqual(sel.anchor.offset, 5) }
    }
  }
}
