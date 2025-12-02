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
final class OptimizedReconcilerGraphemeReplaceParityTests: XCTestCase {

  private func makeEditors() -> (opt: (Editor, any ReadOnlyTextKitContextProtocol), leg: (Editor, any ReadOnlyTextKitContextProtocol)) {
    return makeParityTestEditors()
  }

  func testParity_ReplaceZWJFamilyWithText() throws {
    let (opt, leg) = makeEditors()
    let family = "👨‍👩‍👦‍👦"

    func scenario(on pair: (Editor, any ReadOnlyTextKitContextProtocol)) throws -> String {
      let editor = pair.0; let ctx = pair.1
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "A\(family)B")
        try p.append([t]); try root.append([p])
      }
      let s = ctx.textStorage.string as NSString
      let r = s.range(of: family)
      XCTAssertTrue(r.location != NSNotFound)
      // Select the family range and replace with "X"
      try editor.update {
        guard let p = getRoot()?.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        let a = createPoint(key: t.getKey(), offset: r.location, type: .text)
        let f = createPoint(key: t.getKey(), offset: r.location + r.length, type: .text)
        try setSelection(RangeSelection(anchor: a, focus: f, format: TextFormat()))
      }
      try editor.update { try (getSelection() as? RangeSelection)?.insertText("X") }
      return ctx.textStorage.string
    }

    let a = try scenario(on: opt)
    let b = try scenario(on: leg)
    XCTAssertEqual(a, b)
  }
}
