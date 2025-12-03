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
final class OptimizedReconcilerLineBreakParityTests: XCTestCase {

  private func makeEditors() -> (opt: (Editor, any ReadOnlyTextKitContextProtocol), leg: (Editor, any ReadOnlyTextKitContextProtocol)) {
    return makeParityTestEditors()
  }

  func testParity_InsertLineBreakDoesNotCreateParagraph() throws {
    let (opt, leg) = makeEditors()

    func run(on editor: Editor) throws -> String {
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "HelloWorld")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 5, focusOffset: 5)
      }
      try editor.update { try (getSelection() as? RangeSelection)?.insertLineBreak(selectStart: false) }
      var out = ""; try editor.read { out = getRoot()?.getTextContent() ?? "" }
      return out
    }

    let a = try run(on: opt.0)
    let b = try run(on: leg.0)
    XCTAssertEqual(a, b)
    XCTAssertEqual(a, "Hello\nWorld")
  }
}
