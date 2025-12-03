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

@MainActor
final class BackspaceMergeAtParagraphStartParityTests: XCTestCase {

  private func makeEditors() -> (opt: (Editor, any ReadOnlyTextKitContextProtocol), leg: (Editor, any ReadOnlyTextKitContextProtocol)) {
    return makeParityTestEditors()
  }

  func testParity_BackspaceAtStartOfParagraph_MergesWithPrevious_NotWholeWord() throws {
    let (opt, leg) = makeEditors()

    func run(on editor: Editor) throws -> String {
      try editor.update {
        guard let root = getRoot() else { return }
        let p1 = createParagraphNode(); let t1 = createTextNode(text: "Hello")
        try p1.append([t1]); try root.append([p1])
        try t1.select(anchorOffset: 5, focusOffset: 5)
        try (getSelection() as? RangeSelection)?.insertParagraph()
      }
      try editor.update { try (getSelection() as? RangeSelection)?.insertText("World") }
      // Move caret to start of second paragraph
      try editor.update {
        if let root = getRoot(), let p2 = root.getLastChild() as? ParagraphNode, let t2 = p2.getLastChild() as? TextNode {
          try t2.select(anchorOffset: 0, focusOffset: 0)
        }
      }
      // Backspace at paragraph start should merge with previous (delete newline only)
      try editor.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      var out = ""
      try editor.read { out = getRoot()?.getTextContent() ?? "" }
      return out
    }

    let a = try run(on: opt.0)
    let b = try run(on: leg.0)
    XCTAssertEqual(a, b)
    XCTAssertEqual(a, "HelloWorld")
  }
}
