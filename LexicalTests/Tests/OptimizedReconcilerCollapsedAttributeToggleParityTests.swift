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
final class OptimizedReconcilerCollapsedAttributeToggleParityTests: XCTestCase {

  private func makeEditors() -> (opt: (Editor, any ReadOnlyTextKitContextProtocol), leg: (Editor, any ReadOnlyTextKitContextProtocol)) {
    return makeParityTestEditors()
  }

  func testParity_ToggleBoldAtCaret_NoStringChange() throws {
    let (opt, leg) = makeEditors()

    func scenario(on pair: (Editor, any ReadOnlyTextKitContextProtocol)) throws -> String {
      let editor = pair.0
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Hello")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 2, focusOffset: 2)
      }
      try editor.update {
        guard let sel = try getSelection() as? RangeSelection,
              let t = (getRoot()?.getFirstChild() as? ParagraphNode)?.getFirstChild() as? TextNode else { return }
        // toggling bold on collapsed should be attribute-only; string stays equal
        try t.setBold(true)
        _ = sel // keep selection
      }
      return pair.1.textStorage.string
    }

    let a = try scenario(on: opt)
    let b = try scenario(on: leg)
    XCTAssertEqual(a, b)
  }
}
