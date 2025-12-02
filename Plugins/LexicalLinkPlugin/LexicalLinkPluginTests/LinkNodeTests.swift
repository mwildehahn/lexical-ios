/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import Lexical
@testable import LexicalLinkPlugin
import XCTest

#if os(macOS) && !targetEnvironment(macCatalyst)
@testable import LexicalAppKit
#endif

@MainActor
class LinkNodeTests: XCTestCase {

  #if !os(macOS) || targetEnvironment(macCatalyst)
  // UIKit-specific test that uses textStorage and .link attribute
  func testLinkAttributeLengthForAccessibility() throws {
    let view = Lexical.LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags())
    let editor = view.editor

    try editor.update {
      guard let editorState = getActiveEditorState(),
            let rootNode = editorState.getRootNode(),
            let paragraphNode = rootNode.getChildren().first as? ElementNode
      else {
        XCTFail("should have editor state")
        return
      }

      let linkNode = LinkNode()
      try linkNode.setURL("http://www.example.com")
      try paragraphNode.append([linkNode])

      let textNode = TextNode()
      try textNode.setText("Hello World")
      try linkNode.append([textNode])
    }

    // I have confirmed via the simulator that UITextView uses longestEffectiveRange to find the bounds of a link.
    var range = NSRange(location: NSNotFound, length: 0)
    let url: String? = editor.textStorage?.attribute(.link, at: 0, longestEffectiveRange: &range, in: NSRange(location: 0, length: editor.textStorage?.length ?? 0)) as? String

    XCTAssertEqual(url, "http://www.example.com", "Link address should match")
    XCTAssertEqual(range.length, 11, "link should span eleven characters")
  }
  #endif

  func testLinkNodeTypeAndProperties() throws {
    #if os(macOS) && !targetEnvironment(macCatalyst)
    let view = LexicalAppKit.LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags())
    #else
    let view = Lexical.LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags())
    #endif

    try view.editor.update {
      let linkNode = LinkNode()
      XCTAssertTrue(linkNode.type == NodeType.link)
      XCTAssertFalse(linkNode.canInsertTextBefore())
      XCTAssertFalse(linkNode.canInsertTextAfter())
      XCTAssertFalse(linkNode.canBeEmpty())
      XCTAssertTrue(linkNode.isInline())
    }
  }
}
