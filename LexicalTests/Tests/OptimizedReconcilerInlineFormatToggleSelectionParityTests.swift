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
final class OptimizedReconcilerInlineFormatToggleSelectionParityTests: XCTestCase {

  private func makeEditors() -> (opt: (Editor, any ReadOnlyTextKitContextProtocol), leg: (Editor, any ReadOnlyTextKitContextProtocol)) {
    return makeParityTestEditors()
  }

  func testParity_ToggleItalicOnRange_SelectionCollapsedEnd() throws {
    let (opt, leg) = makeEditors()

    func run(on pair: (Editor, any ReadOnlyTextKitContextProtocol)) throws -> (String, Int) {
      let editor = pair.0; let ctx = pair.1
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "HelloWorld")
        try p.append([t]); try root.append([p])
        // Select "World"
        let a = createPoint(key: t.getKey(), offset: 5, type: .text)
        let f = createPoint(key: t.getKey(), offset: 10, type: .text)
        try setSelection(RangeSelection(anchor: a, focus: f, format: TextFormat()))
      }
      try editor.update {
        guard let p = getRoot()?.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        try t.setItalic(true)
      }
      var caret = -1
      try editor.read { if let sel = try getSelection() as? RangeSelection { caret = sel.anchor.offset } }
      return (ctx.textStorage.string, caret)
    }

    let (aStr, aOff) = try run(on: opt)
    let (bStr, bOff) = try run(on: leg)
    XCTAssertEqual(aStr, bStr)
    if aOff >= 0 && bOff >= 0 { XCTAssertEqual(aOff, bOff) }
  }
}
