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
final class OptimizedReconcilerLiveTypingCaretParityTests: XCTestCase {

  private func makeEditors() -> (opt: (Editor, any ReadOnlyTextKitContextProtocol), leg: (Editor, any ReadOnlyTextKitContextProtocol)) {
    return makeParityTestEditors()
  }

  func testParity_TypingInMiddleOfMultiParagraphDoc() throws {
    let (opt, leg) = makeEditors()

    func scenario(on pair: (Editor, any ReadOnlyTextKitContextProtocol)) throws -> (String, Int) {
      let editor = pair.0; let ctx = pair.1
      try editor.update {
        guard let root = getRoot() else { return }
        var nodes: [Node] = []
        for i in 0..<10 { let p = createParagraphNode(); try p.append([ createTextNode(text: "Para\(i) content") ]); nodes.append(p) }
        try root.append(nodes)
        if let p5 = root.getChildAtIndex(index: 5) as? ParagraphNode,
           let t = p5.getFirstChild() as? TextNode {
          // Place caret between words: after "Para5"
          let idx = ("Para5").lengthAsNSString()
          try t.select(anchorOffset: idx, focusOffset: idx)
        }
      }
      // Type burst "!!!"
      for _ in 0..<3 { try editor.update { try (getSelection() as? RangeSelection)?.insertText("!") } }
      var caret = -1
      try editor.read { if let sel = try getSelection() as? RangeSelection { caret = sel.anchor.offset } }
      return (ctx.textStorage.string, caret)
    }

    let (aStr, aOff) = try scenario(on: opt)
    let (bStr, bOff) = try scenario(on: leg)
    XCTAssertEqual(aStr, bStr)
    if aOff >= 0 && bOff >= 0 { XCTAssertEqual(aOff, bOff) }
  }
}
