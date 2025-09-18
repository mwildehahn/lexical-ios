/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import Lexical
import XCTest

@MainActor
class ParagraphNodeTests: XCTestCase {
  @MainActor
  func testParagraphAnchorsDisabledByDefault() throws {
    let context = LexicalReadOnlyTextKitContext(
      editorConfig: EditorConfig(theme: Theme(), plugins: []),
      featureFlags: FeatureFlags()
    )
    let editor = context.editor

    try editor.update {
      guard
        let rootNode = getActiveEditorState()?.getRootNode()
      else {
        XCTFail("No root node")
        return
      }

      _ = try? rootNode.clear()

      let paragraph = ParagraphNode()
      let textNode = TextNode(text: "Hello", key: nil)
      try paragraph.append([textNode])
      try rootNode.append([paragraph])
    }

    try editor.read {
      guard
        let rootNode = getActiveEditorState()?.getRootNode(),
        let paragraph = rootNode.getFirstChild() as? ParagraphNode
      else {
        XCTFail("Missing paragraph")
        return
      }

      XCTAssertFalse(paragraph.shouldEmitAnchorMarkers)
      XCTAssertEqual(paragraph.getPreamble(), "")
      XCTAssertEqual(paragraph.getPostamble(), "")
      XCTAssertEqual(rootNode.getTextContent(), "Hello")
    }
  }

  @MainActor
  func testParagraphAnchorsEnabledWrapText() throws {
    let context = LexicalReadOnlyTextKitContext(
      editorConfig: EditorConfig(theme: Theme(), plugins: []),
      featureFlags: FeatureFlags(reconcilerAnchors: true)
    )
    let editor = context.editor

    try editor.update {
      guard
        let rootNode = getActiveEditorState()?.getRootNode()
      else {
        XCTFail("No root node")
        return
      }

      _ = try? rootNode.clear()

      let paragraph = ParagraphNode()
      let textNode = TextNode(text: "Hello", key: nil)
      try paragraph.append([textNode])
      try rootNode.append([paragraph])
    }

    try editor.read {
      guard
        let rootNode = getActiveEditorState()?.getRootNode(),
        let paragraph = rootNode.getFirstChild() as? ParagraphNode
      else {
        XCTFail("Missing paragraph")
        return
      }

      XCTAssertTrue(paragraph.shouldEmitAnchorMarkers)
      let expectedStart = AnchorMarkers.make(kind: .start, key: paragraph.key)
      let expectedEnd = AnchorMarkers.make(kind: .end, key: paragraph.key)

      XCTAssertEqual(paragraph.getPreamble(), expectedStart)
      XCTAssertEqual(paragraph.getPostamble(), expectedEnd)
      XCTAssertEqual(rootNode.getTextContent(), expectedStart + "Hello" + expectedEnd)
    }
  }

  func testinsertNewAfter() throws {
    let view = LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags())
    let editor = view.editor

    try editor.update {
      guard let editorState = getActiveEditorState(),
            let rootNode = editorState.getRootNode()
      else {
        XCTFail("should have editor state")
        return
      }

      let paragraphNode = ParagraphNode()
      try rootNode.append([paragraphNode])
    }

    try editor.update {
      guard let editorState = getActiveEditorState() else {
        XCTFail("should have editor state")
        return
      }

      guard let paragraphNode = getNodeByKey(key: "0") as? ParagraphNode else {
        XCTFail("Paragraph node not found")
        return
      }

      guard let selection = editorState.selection as? RangeSelection else {
        XCTFail("Expected range selection")
        return
      }

      let result = try paragraphNode.insertNewAfter(selection: selection)
      let newNode = result.element
      XCTAssertNotNil(newNode)
      XCTAssertEqual(newNode?.parent, paragraphNode.parent)
      XCTAssertEqual(newNode?.type, paragraphNode.type)
      XCTAssertNotEqual(newNode?.key, paragraphNode.key)
      XCTAssertEqual(newNode, paragraphNode.getNextSibling())
    }
  }
}
