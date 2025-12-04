/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import Lexical
import XCTest

#if os(macOS) && !targetEnvironment(macCatalyst)
@testable import LexicalAppKit
#endif

class ParagraphNodeTests: XCTestCase {

  private func makeEditor() -> (Editor, any ReadOnlyTextKitContextProtocol) {
    let ctx = makeReadOnlyContext(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags())
    return (ctx.editor, ctx)
  }

  func testinsertNewAfter() throws {
    let (editor, ctx) = makeEditor(); _ = ctx // Keep context alive

    try editor.update {
      guard let editorState = getActiveEditorState(),
            let rootNode = editorState.getRootNode()
      else {
        XCTFail("should have editor state")
        return
      }

      let paragraphNode = ParagraphNode()
      try rootNode.append([paragraphNode])
      // Create a selection to use in the test
      try paragraphNode.selectStart()
    }

    try editor.update {
      guard let paragraphNode = getNodeByKey(key: "0") as? ParagraphNode else {
        XCTFail("Paragraph node not found")
        return
      }

      guard let selection = try getSelection() as? RangeSelection else {
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
