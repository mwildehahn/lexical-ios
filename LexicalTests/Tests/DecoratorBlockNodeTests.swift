// Cross-platform decorator block node tests

import XCTest
@testable import Lexical

#if os(macOS) && !targetEnvironment(macCatalyst)
@testable import LexicalAppKit
#endif

@MainActor
class DecoratorBlockNodeTests: XCTestCase {

  func createEditorView() -> TestEditorView {
    return createTestEditorView()
  }

  func testIsDecoratorBlockNode() throws {
    let view = createEditorView()
    let editor = view.editor

    try editor.update {
      let decoratorNode = DecoratorBlockNode()
      let textNode = TextNode()

      XCTAssert(isDecoratorBlockNode(decoratorNode))
      XCTAssert(!isDecoratorBlockNode(textNode))
    }
  }

  func testInsertDecoratorBlockNode() throws {
    let view = createEditorView()
    let editor = view.editor
    try registerTestDecoratorBlockNode(on: editor)

    try editor.update {
      guard let root = getRoot() else {
        XCTFail("No root node")
        return
      }

      let paragraph1 = createParagraphNode()
      let text1 = createTextNode(text: "Hello")
      try paragraph1.append([text1])
      try root.append([paragraph1])

      let decoratorNode = TestDecoratorBlockNodeCrossplatform()
      try text1.select(anchorOffset: 5, focusOffset: 5)
      guard let selection = try getSelection() as? RangeSelection else {
        XCTFail("No selection")
        return
      }
      _ = try selection.insertNodes(nodes: [decoratorNode])
    }

    try editor.read {
      guard let root = getRoot() else {
        XCTFail("No root node")
        return
      }

      // Verify structure
      XCTAssertEqual(root.getChildrenSize(), 3)
      XCTAssertTrue(root.getChildAtIndex(index: 2) is TestDecoratorBlockNodeCrossplatform)
    }
  }

  func testInsertDecoratorBlockNodeAtStart() throws {
    let view = createEditorView()
    let editor = view.editor
    try registerTestDecoratorBlockNode(on: editor)

    try editor.update {
      guard let root = getRoot() else {
        XCTFail("No root node")
        return
      }

      let paragraph1 = createParagraphNode()
      let text1 = createTextNode(text: "Hello")
      try paragraph1.append([text1])
      try root.append([paragraph1])

      let decoratorNode = TestDecoratorBlockNodeCrossplatform()
      try text1.select(anchorOffset: 0, focusOffset: 0)
      guard let selection = try getSelection() as? RangeSelection else {
        XCTFail("No selection")
        return
      }
      _ = try selection.insertNodes(nodes: [decoratorNode])
    }

    try editor.read {
      guard let root = getRoot() else {
        XCTFail("No root node")
        return
      }

      // Verify structure
      XCTAssertEqual(root.getChildrenSize(), 3)
      XCTAssertTrue(root.getChildAtIndex(index: 1) is ParagraphNode)
      XCTAssertTrue(root.getChildAtIndex(index: 2) is TestDecoratorBlockNodeCrossplatform)
    }
  }

  func testInsertDecoratorBlockNodeInMiddle() throws {
    let view = createEditorView()
    let editor = view.editor
    try registerTestDecoratorBlockNode(on: editor)

    try editor.update {
      guard let root = getRoot() else {
        XCTFail("No root node")
        return
      }

      let paragraph1 = createParagraphNode()
      let text1 = createTextNode(text: "Hello")
      try paragraph1.append([text1])

      let paragraph2 = createParagraphNode()
      let text2 = createTextNode(text: "World")
      try paragraph2.append([text2])

      try root.append([paragraph1, paragraph2])

      let decoratorNode = TestDecoratorBlockNodeCrossplatform()
      try text1.select(anchorOffset: 5, focusOffset: 5)
      guard let selection = try getSelection() as? RangeSelection else {
        XCTFail("No selection")
        return
      }
      _ = try selection.insertNodes(nodes: [decoratorNode])
    }

    try editor.read {
      guard let root = getRoot() else {
        XCTFail("No root node")
        return
      }

      // Verify structure
      XCTAssertEqual(root.getChildrenSize(), 4)
      XCTAssertTrue(root.getChildAtIndex(index: 1) is ParagraphNode)
      XCTAssertTrue(root.getChildAtIndex(index: 2) is TestDecoratorBlockNodeCrossplatform)
      XCTAssertTrue(root.getChildAtIndex(index: 3) is ParagraphNode)

      // Verify text content
      let firstParagraph = root.getChildAtIndex(index: 1) as? ParagraphNode
      let lastParagraph = root.getChildAtIndex(index: 3) as? ParagraphNode
      XCTAssertEqual(firstParagraph?.getTextContent(), "Hello\n")
      XCTAssertEqual(lastParagraph?.getTextContent(), "\nWorld")
    }
  }

  func testInsertDecoratorBlockNodeAfterExistingOne() throws {
    let view = createEditorView()
    let editor = view.editor
    try registerTestDecoratorBlockNode(on: editor)

    try editor.update {
      guard let root = getRoot() else {
        XCTFail("No root node")
        return
      }

      let paragraph = createParagraphNode()
      let text = createTextNode(text: "Hello")
      try paragraph.append([text])

      let decoratorNode1 = TestDecoratorBlockNodeCrossplatform()
      try root.append([paragraph, decoratorNode1])

      // Select the first decorator node
      try decoratorNode1.selectStart()

    }

    try editor.update {
      guard let root = getRoot() else {
        XCTFail("No root node")
        return
      }

      guard let selection = try getSelection() as? RangeSelection else {
        XCTFail("No selection")
        return
      }

      XCTAssertEqual(root.getChildrenSize(), 3)
      XCTAssertTrue(root.getChildAtIndex(index: 0) is ParagraphNode)
      XCTAssertTrue(root.getChildAtIndex(index: 1) is ParagraphNode)
      XCTAssertTrue(root.getChildAtIndex(index: 2) is TestDecoratorBlockNodeCrossplatform)

      // Insert second decorator node
      let decoratorNode2 = TestDecoratorBlockNodeCrossplatform()
      _ = try selection.insertNodes(nodes: [decoratorNode2])
    }

    try editor.read {
      guard let root = getRoot() else {
        XCTFail("No root node")
        return
      }

      // Verify structure
      XCTAssertEqual(root.getChildrenSize(), 3)
      XCTAssertTrue(root.getChildAtIndex(index: 0) is TestDecoratorBlockNodeCrossplatform)
      XCTAssertTrue(root.getChildAtIndex(index: 1) is ParagraphNode)
      XCTAssertTrue(root.getChildAtIndex(index: 2) is TestDecoratorBlockNodeCrossplatform)
    }

  }
}
