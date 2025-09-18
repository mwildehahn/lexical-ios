/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import Lexical
import UIKit
import XCTest

@MainActor
final class CopyPasteHelpersTests: XCTestCase {

  func testStripAnchorsRemovesMarkersFromPlainText() {
    let start = AnchorMarkers.make(kind: .start, key: "P1")
    let end = AnchorMarkers.make(kind: .end, key: "P1")
    let text = "\(start)Hello\(end)"

    let sanitized = AnchorMarkers.stripAnchors(from: text)

    XCTAssertEqual(sanitized, "Hello")
  }

  func testStripAnchorsRemovesMarkersFromAttributedString() {
    let start = AnchorMarkers.make(kind: .start, key: "P1")
    let end = AnchorMarkers.make(kind: .end, key: "P1")

    let attributed = NSMutableAttributedString(string: start + "Hello" + end)
    attributed.addAttribute(.foregroundColor, value: UIColor.red, range: NSRange(location: start.count, length: 5))

    let sanitized = AnchorMarkers.stripAnchors(from: attributed)

    XCTAssertEqual(sanitized.string, "Hello")
    let attributes = sanitized.attributes(at: 0, effectiveRange: nil)
    XCTAssertEqual(attributes[.foregroundColor] as? UIColor, UIColor.red)
  }

  func testInsertPlainTextRemovesAnchors() throws {
    let textKitContext = LexicalReadOnlyTextKitContext(
      editorConfig: EditorConfig(theme: Theme(), plugins: []),
      featureFlags: FeatureFlags(reconcilerAnchors: true)
    )
    let editor = textKitContext.editor

    var paragraphKey: NodeKey = ""

    try editor.update {
      guard let rootNode = getActiveEditorState()?.getRootNode() else {
        XCTFail("Missing root node")
        return
      }
      let paragraph = ParagraphNode()
      let textNode = TextNode(text: "", key: nil)
      try paragraph.append([textNode])
      try rootNode.append([paragraph])
      paragraphKey = paragraph.key
      try paragraph.select(anchorOffset: nil, focusOffset: nil)
    }

    let start = AnchorMarkers.make(kind: .start, key: "Injected")
    let end = AnchorMarkers.make(kind: .end, key: "Injected")

    try editor.update {
      guard let selection = try getSelection() as? RangeSelection else {
        XCTFail("Expected range selection")
        return
      }
      try insertPlainText(selection: selection, text: start + "Sanitized" + end)
    }

    try editor.read {
      guard
        let paragraph = getNodeByKey(key: paragraphKey) as? ParagraphNode,
        let textNode = paragraph.getFirstChild() as? TextNode
      else {
        XCTFail("Failed to get paragraph")
        return
      }
      XCTAssertEqual(textNode.getTextPart(), "Sanitized")
    }
  }
}
