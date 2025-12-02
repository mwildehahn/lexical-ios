/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import XCTest
@testable import Lexical

#if os(macOS) && !targetEnvironment(macCatalyst)
@testable import LexicalAppKit
#endif

@MainActor
final class OptimizedReconcilerSelectionStabilityParityTests: XCTestCase {

  private func makeEditors() -> (opt: (Editor, any ReadOnlyTextKitContextProtocol), leg: (Editor, any ReadOnlyTextKitContextProtocol)) {
    return makeParityTestEditors()
  }

  func testParity_SelectionUnchangedWhenEditingElsewhere() throws {
    let (opt, leg) = makeEditors()

    func scenario(on pair: (Editor, any ReadOnlyTextKitContextProtocol)) throws -> (String, (NodeKey, Int)) {
      let editor = pair.0
      var anchorKey: NodeKey = ""; var anchorOffset: Int = -1
      try editor.update {
        guard let root = getRoot() else { return }
        let p1 = createParagraphNode(); let t1 = createTextNode(text: "Hello")
        let p2 = createParagraphNode(); let t2 = createTextNode(text: "World")
        try p1.append([t1]); try p2.append([t2]); try root.append([p1, p2])
        // Place caret in middle of first paragraph
        try t1.select(anchorOffset: 2, focusOffset: 2)
      }
      // Edit elsewhere (append text to second paragraph)
      try editor.update {
        guard let root = getRoot(), let p2 = root.getLastChild() as? ParagraphNode,
              let t2 = p2.getFirstChild() as? TextNode else { return }
        try t2.setText("World!")
      }

      var s = ""
      try editor.read {
        s = getRoot()?.getTextContent() ?? ""
        if let sel = try getSelection() as? RangeSelection { anchorKey = sel.anchor.key; anchorOffset = sel.anchor.offset }
      }
      return (s, (anchorKey, anchorOffset))
    }

    let (aStr, aSel) = try scenario(on: opt)
    let (bStr, bSel) = try scenario(on: leg)
    XCTAssertEqual(aStr, bStr)
    XCTAssertEqual(aSel.0, bSel.0)
    XCTAssertEqual(aSel.1, bSel.1)
  }
}
