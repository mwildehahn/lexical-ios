import XCTest
@testable import Lexical

@MainActor
final class SelectionStabilityAfterFormattingTests: XCTestCase {

  private func makeEditor() -> Editor {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let flags = FeatureFlags(
      reconcilerSanityCheck: false,
      proxyTextViewInputDelegate: false,
      useOptimizedReconciler: false  // Use legacy for tests without TextStorage
    )
    return Editor(featureFlags: flags, editorConfig: cfg)
  }

  private func buildDocument(_ editor: Editor) throws {
    try editor.update {
      guard let root = getRoot() else { return }
      let p1 = createParagraphNode()
      try p1.append([createTextNode(text: "First paragraph with some text to select.")])
      let p2 = createParagraphNode()
      try p2.append([createTextNode(text: "Second paragraph with more content for testing.")])
      let p3 = createParagraphNode()
      try p3.append([createTextNode(text: "Third paragraph at the end.")])
      try root.append([p1, p2, p3])
    }
  }

  private func captureSelection(_ editor: Editor) throws -> (anchorKey: NodeKey, anchorOffset: Int, focusKey: NodeKey, focusOffset: Int)? {
    var result: (NodeKey, Int, NodeKey, Int)?
    try editor.read {
      guard let sel = try getSelection() as? RangeSelection else { return }
      result = (sel.anchor.key, sel.anchor.offset, sel.focus.key, sel.focus.offset)
    }
    return result
  }

  // MARK: - Single Node Selection Tests

  func testBoldFormat_SingleNode_PreservesSelection() throws {
    let editor = makeEditor()
    try buildDocument(editor)

    // Select "some text" in first paragraph (offset 21-30)
    try editor.update {
      guard let root = getRoot(), let p = root.getChildren()[safe: 0] as? ParagraphNode,
            let t = p.getFirstChild() as? TextNode else { return }
      _ = try t.select(anchorOffset: 21, focusOffset: 30)
    }

    let beforeSel = try captureSelection(editor)
    XCTAssertNotNil(beforeSel, "Selection should exist before formatting")

    // Apply bold formatting
    try editor.update {
      guard let sel = try getSelection() as? RangeSelection else { return }
      try sel.formatText(formatType: .bold)
    }

    let afterSel = try captureSelection(editor)
    XCTAssertNotNil(afterSel, "Selection should exist after formatting")

    // Selection should be preserved (though node keys may change due to splitting)
    XCTAssertEqual(beforeSel?.anchorOffset, afterSel?.anchorOffset, "Anchor offset should be preserved")
    XCTAssertEqual(beforeSel?.focusOffset, afterSel?.focusOffset, "Focus offset should be preserved")
  }

  func testItalicFormat_SingleNode_PreservesSelection() throws {
    let editor = makeEditor()
    try buildDocument(editor)

    try editor.update {
      guard let root = getRoot(), let p = root.getChildren()[safe: 0] as? ParagraphNode,
            let t = p.getFirstChild() as? TextNode else { return }
      _ = try t.select(anchorOffset: 6, focusOffset: 15)
    }

    let beforeSel = try captureSelection(editor)

    try editor.update {
      guard let sel = try getSelection() as? RangeSelection else { return }
      try sel.formatText(formatType: .italic)
    }

    let afterSel = try captureSelection(editor)
    XCTAssertNotNil(afterSel, "Selection should exist after italic formatting")
    XCTAssertEqual(beforeSel?.anchorOffset, afterSel?.anchorOffset, "Anchor offset should be preserved")
    XCTAssertEqual(beforeSel?.focusOffset, afterSel?.focusOffset, "Focus offset should be preserved")
  }

  func testUnderlineFormat_SingleNode_PreservesSelection() throws {
    let editor = makeEditor()
    try buildDocument(editor)

    try editor.update {
      guard let root = getRoot(), let p = root.getChildren()[safe: 0] as? ParagraphNode,
            let t = p.getFirstChild() as? TextNode else { return }
      _ = try t.select(anchorOffset: 0, focusOffset: 5)
    }

    let beforeSel = try captureSelection(editor)

    try editor.update {
      guard let sel = try getSelection() as? RangeSelection else { return }
      try sel.formatText(formatType: .underline)
    }

    let afterSel = try captureSelection(editor)
    XCTAssertNotNil(afterSel, "Selection should exist after underline formatting")
    XCTAssertEqual(beforeSel?.anchorOffset, afterSel?.anchorOffset, "Anchor offset should be preserved")
    XCTAssertEqual(beforeSel?.focusOffset, afterSel?.focusOffset, "Focus offset should be preserved")
  }

  func testStrikethroughFormat_SingleNode_PreservesSelection() throws {
    let editor = makeEditor()
    try buildDocument(editor)

    try editor.update {
      guard let root = getRoot(), let p = root.getChildren()[safe: 1] as? ParagraphNode,
            let t = p.getFirstChild() as? TextNode else { return }
      _ = try t.select(anchorOffset: 7, focusOffset: 16)
    }

    let beforeSel = try captureSelection(editor)

    try editor.update {
      guard let sel = try getSelection() as? RangeSelection else { return }
      try sel.formatText(formatType: .strikethrough)
    }

    let afterSel = try captureSelection(editor)
    XCTAssertNotNil(afterSel, "Selection should exist after strikethrough formatting")
    XCTAssertEqual(beforeSel?.anchorOffset, afterSel?.anchorOffset, "Anchor offset should be preserved")
    XCTAssertEqual(beforeSel?.focusOffset, afterSel?.focusOffset, "Focus offset should be preserved")
  }

  // MARK: - Multi-Node Selection Tests (Critical!)

  func testBoldFormat_MultiNode_PreservesSelection() throws {
    let editor = makeEditor()
    try buildDocument(editor)

    var firstNodeKey: NodeKey = ""
    var lastNodeKey: NodeKey = ""

    // Select from middle of first paragraph to middle of second paragraph
    try editor.update {
      guard let root = getRoot(),
            let p1 = root.getChildren()[safe: 0] as? ParagraphNode,
            let t1 = p1.getFirstChild() as? TextNode,
            let p2 = root.getChildren()[safe: 1] as? ParagraphNode,
            let t2 = p2.getFirstChild() as? TextNode else { return }
      firstNodeKey = t1.key
      lastNodeKey = t2.key
      let sel = RangeSelection(anchor: Point(key: t1.key, offset: 20, type: .text),
                               focus: Point(key: t2.key, offset: 25, type: .text),
                               format: TextFormat())
      getActiveEditorState()?.selection = sel
    }

    let beforeSel = try captureSelection(editor)
    XCTAssertNotNil(beforeSel, "Multi-node selection should exist before formatting")

    // Apply bold formatting to multi-node selection
    try editor.update {
      guard let sel = try getSelection() as? RangeSelection else { return }
      try sel.formatText(formatType: .bold)
    }

    let afterSel = try captureSelection(editor)
    XCTAssertNotNil(afterSel, "Multi-node selection should exist after bold formatting")

    // Selection should still span across nodes (even if keys changed)
    XCTAssertNotEqual(afterSel?.anchorKey, afterSel?.focusKey, "Selection should still span multiple nodes")
  }

  func testItalicFormat_MultiNode_PreservesSelection() throws {
    let editor = makeEditor()
    try buildDocument(editor)

    try editor.update {
      guard let root = getRoot(),
            let p1 = root.getChildren()[safe: 0] as? ParagraphNode,
            let t1 = p1.getFirstChild() as? TextNode,
            let p2 = root.getChildren()[safe: 1] as? ParagraphNode,
            let t2 = p2.getFirstChild() as? TextNode else { return }
      let sel = RangeSelection(anchor: Point(key: t1.key, offset: 15, type: .text),
                               focus: Point(key: t2.key, offset: 20, type: .text),
                               format: TextFormat())
      getActiveEditorState()?.selection = sel
    }

    let beforeSel = try captureSelection(editor)

    try editor.update {
      guard let sel = try getSelection() as? RangeSelection else { return }
      try sel.formatText(formatType: .italic)
    }

    let afterSel = try captureSelection(editor)
    XCTAssertNotNil(afterSel, "Multi-node selection should exist after italic formatting")
    XCTAssertNotEqual(afterSel?.anchorKey, afterSel?.focusKey, "Selection should still span multiple nodes")
  }

  func testUnderlineFormat_MultiNode_PreservesSelection() throws {
    let editor = makeEditor()
    try buildDocument(editor)

    try editor.update {
      guard let root = getRoot(),
            let p2 = root.getChildren()[safe: 1] as? ParagraphNode,
            let t2 = p2.getFirstChild() as? TextNode,
            let p3 = root.getChildren()[safe: 2] as? ParagraphNode,
            let t3 = p3.getFirstChild() as? TextNode else { return }
      let sel = RangeSelection(anchor: Point(key: t2.key, offset: 10, type: .text),
                               focus: Point(key: t3.key, offset: 15, type: .text),
                               format: TextFormat())
      getActiveEditorState()?.selection = sel
    }

    let beforeSel = try captureSelection(editor)

    try editor.update {
      guard let sel = try getSelection() as? RangeSelection else { return }
      try sel.formatText(formatType: .underline)
    }

    let afterSel = try captureSelection(editor)
    XCTAssertNotNil(afterSel, "Multi-node selection should exist after underline formatting")
    XCTAssertNotEqual(afterSel?.anchorKey, afterSel?.focusKey, "Selection should still span multiple nodes")
  }

  // MARK: - Sequential Formatting Tests

  func testSequentialFormatting_PreservesSelection() throws {
    let editor = makeEditor()
    try buildDocument(editor)

    try editor.update {
      guard let root = getRoot(), let p = root.getChildren()[safe: 0] as? ParagraphNode,
            let t = p.getFirstChild() as? TextNode else { return }
      _ = try t.select(anchorOffset: 6, focusOffset: 20)
    }

    let initialSel = try captureSelection(editor)

    // Apply bold
    try editor.update {
      guard let sel = try getSelection() as? RangeSelection else { return }
      try sel.formatText(formatType: .bold)
    }

    let afterBold = try captureSelection(editor)
    XCTAssertNotNil(afterBold, "Selection should exist after bold")

    // Apply italic
    try editor.update {
      guard let sel = try getSelection() as? RangeSelection else { return }
      try sel.formatText(formatType: .italic)
    }

    let afterItalic = try captureSelection(editor)
    XCTAssertNotNil(afterItalic, "Selection should exist after italic")

    // Apply underline
    try editor.update {
      guard let sel = try getSelection() as? RangeSelection else { return }
      try sel.formatText(formatType: .underline)
    }

    let afterUnderline = try captureSelection(editor)
    XCTAssertNotNil(afterUnderline, "Selection should exist after underline")

    // Offsets should remain consistent throughout
    XCTAssertEqual(initialSel?.anchorOffset, afterUnderline?.anchorOffset, "Anchor offset should be preserved through sequential formatting")
    XCTAssertEqual(initialSel?.focusOffset, afterUnderline?.focusOffset, "Focus offset should be preserved through sequential formatting")
  }

  // MARK: - Edge Cases

  func testFormat_SelectionAtDocumentStart_PreservesSelection() throws {
    let editor = makeEditor()
    try buildDocument(editor)

    try editor.update {
      guard let root = getRoot(), let p = root.getChildren()[safe: 0] as? ParagraphNode,
            let t = p.getFirstChild() as? TextNode else { return }
      _ = try t.select(anchorOffset: 0, focusOffset: 10)
    }

    let beforeSel = try captureSelection(editor)

    try editor.update {
      guard let sel = try getSelection() as? RangeSelection else { return }
      try sel.formatText(formatType: .bold)
    }

    let afterSel = try captureSelection(editor)
    XCTAssertNotNil(afterSel, "Selection at document start should be preserved")
    XCTAssertEqual(beforeSel?.anchorOffset, afterSel?.anchorOffset, "Anchor offset at start should be preserved")
  }

  func testFormat_SelectionAtDocumentEnd_PreservesSelection() throws {
    let editor = makeEditor()
    try buildDocument(editor)

    try editor.update {
      guard let root = getRoot(), let p = root.getChildren()[safe: 2] as? ParagraphNode,
            let t = p.getFirstChild() as? TextNode else { return }
      let len = t.getTextPartSize()
      _ = try t.select(anchorOffset: len - 10, focusOffset: len)
    }

    let beforeSel = try captureSelection(editor)

    try editor.update {
      guard let sel = try getSelection() as? RangeSelection else { return }
      try sel.formatText(formatType: .italic)
    }

    let afterSel = try captureSelection(editor)
    XCTAssertNotNil(afterSel, "Selection at document end should be preserved")
    XCTAssertEqual(beforeSel?.focusOffset, afterSel?.focusOffset, "Focus offset at end should be preserved")
  }

  func testFormat_EntireDocument_PreservesSelection() throws {
    let editor = makeEditor()
    try buildDocument(editor)

    try editor.update {
      guard let root = getRoot(),
            let p1 = root.getChildren()[safe: 0] as? ParagraphNode,
            let t1 = p1.getFirstChild() as? TextNode,
            let p3 = root.getChildren()[safe: 2] as? ParagraphNode,
            let t3 = p3.getFirstChild() as? TextNode else { return }
      let len3 = t3.getTextPartSize()
      let sel = RangeSelection(anchor: Point(key: t1.key, offset: 0, type: .text),
                               focus: Point(key: t3.key, offset: len3, type: .text),
                               format: TextFormat())
      getActiveEditorState()?.selection = sel
    }

    let beforeSel = try captureSelection(editor)

    try editor.update {
      guard let sel = try getSelection() as? RangeSelection else { return }
      try sel.formatText(formatType: .bold)
    }

    let afterSel = try captureSelection(editor)
    XCTAssertNotNil(afterSel, "Entire document selection should be preserved")
    XCTAssertEqual(beforeSel?.anchorOffset, 0, "Should start at beginning")
    XCTAssertEqual(afterSel?.anchorOffset, 0, "Should still start at beginning after formatting")
  }
}

private extension Array {
  func chunked(into size: Int) -> [[Element]] {
    stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
  }
  subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
