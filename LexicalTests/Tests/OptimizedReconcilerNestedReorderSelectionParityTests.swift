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
final class OptimizedReconcilerNestedReorderSelectionParityTests: XCTestCase {

  private func makeEditors() -> (opt: (Editor, any ReadOnlyTextKitContextProtocol), leg: (Editor, any ReadOnlyTextKitContextProtocol)) {
    return makeParityTestEditors()
  }

  func testParity_NestedReorderWithCaretInsideMovedParagraph() throws {
    let (opt, leg) = makeEditors()

    func scenario(on pair: (Editor, any ReadOnlyTextKitContextProtocol)) throws -> (String, Int) {
      let editor = pair.0
      var caretOffset: Int = -1
      try editor.update {
        guard let root = getRoot() else { return }
        let quote = QuoteNode()
        let p1 = createParagraphNode(); let p2 = createParagraphNode()
        try p1.append([ createTextNode(text: "First") ])
        let moved = createTextNode(text: "Second")
        try p2.append([ moved ])
        try quote.append([p1, p2]); try root.append([quote])
        try moved.select(anchorOffset: 2, focusOffset: 2)
      }

      try editor.update {
        guard let quote = getRoot()?.getFirstChild() as? QuoteNode,
              let p1 = quote.getFirstChild() as? ParagraphNode,
              let p2 = quote.getLastChild() as? ParagraphNode else { return }
        _ = try p1.insertBefore(nodeToInsert: p2)
      }

      var out = ""; try editor.read {
        out = getRoot()?.getTextContent() ?? ""
        if let sel = try getSelection() as? RangeSelection { caretOffset = sel.anchor.offset }
      }
      return (out, caretOffset)
    }

    let (aStr, aOff) = try scenario(on: opt)
    let (bStr, bOff) = try scenario(on: leg)
    XCTAssertEqual(aStr, bStr)
    if aOff >= 0 && bOff >= 0 { XCTAssertEqual(aOff, bOff) }
  }
}
