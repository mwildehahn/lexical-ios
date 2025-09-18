/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import Lexical
import XCTest

@MainActor
final class ReconcilerDeltaTests: XCTestCase {

  func testLegacyDeltaAppliedWhenAnchorsDisabled() throws {
    let context = LexicalReadOnlyTextKitContext(
      editorConfig: EditorConfig(theme: Theme(), plugins: []),
      featureFlags: FeatureFlags()
    )
    let editor = context.editor

    try editor.update {
      guard let rootNode = getActiveEditorState()?.getRootNode() else {
        XCTFail("Missing root node")
        return
      }
      _ = try? rootNode.clear()
      let paragraph = ParagraphNode()
      let textNode = TextNode(text: "Hello", key: nil)
      try paragraph.append([textNode])
      try rootNode.append([paragraph])
    }

    let textStorage = editor.textStorage
    XCTAssertNotNil(textStorage)
    let initialString = textStorage?.string ?? ""

    try editor.update {
      guard
        let rootNode = getActiveEditorState()?.getRootNode(),
        rootNode.getChildren().count == 1,
        let paragraph = rootNode.getFirstChild() as? ParagraphNode,
        let textNode = paragraph.getFirstChild() as? TextNode
      else {
        XCTFail("Missing nodes")
        return
      }
      try textNode.setText("Hello world")
    }

    XCTAssertNotEqual(textStorage, nil)
    XCTAssertEqual(textStorage?.string, "Hello world")
    XCTAssertNotEqual(initialString, textStorage?.string)
  }

  func testLegacyDeltaRunsWhenAnchorsEnabledButDeltaReturnsNil() throws {
    let context = LexicalReadOnlyTextKitContext(
      editorConfig: EditorConfig(theme: Theme(), plugins: []),
      featureFlags: FeatureFlags(reconcilerAnchors: true)
    )
    let editor = context.editor

    try editor.update {
      guard let rootNode = getActiveEditorState()?.getRootNode() else {
        XCTFail("Missing root node")
        return
      }
      _ = try? rootNode.clear()
      let paragraph = ParagraphNode()
      let textNode = TextNode(text: "Alpha", key: nil)
      try paragraph.append([textNode])
      try rootNode.append([paragraph])
    }

    let textStorage = editor.textStorage
    XCTAssertNotNil(textStorage)
    let initialString = textStorage?.string ?? ""

    try editor.update {
      guard
        let rootNode = getActiveEditorState()?.getRootNode(),
        rootNode.getChildren().count == 1,
        let paragraph = rootNode.getFirstChild() as? ParagraphNode,
        let textNode = paragraph.getFirstChild() as? TextNode
      else {
        XCTFail("Missing nodes")
        return
      }
      try textNode.setText("Alpha beta")
    }

    // With anchor mode currently falling back to legacy, we still expect a reconciled string.
    XCTAssertNotEqual(textStorage, nil)
    XCTAssertEqual(textStorage?.string, "S:1Alpha betaE:1")
    XCTAssertNotEqual(initialString, textStorage?.string)
  }
}
