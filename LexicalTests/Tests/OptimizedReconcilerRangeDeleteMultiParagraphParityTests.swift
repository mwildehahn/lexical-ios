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
final class OptimizedReconcilerRangeDeleteMultiParagraphParityTests: XCTestCase {

  private func makeEditors() -> (opt: (Editor, any ReadOnlyTextKitContextProtocol), leg: (Editor, any ReadOnlyTextKitContextProtocol)) {
    return makeParityTestEditors()
  }

  func testParity_RangeDeleteAcrossThreeParagraphs() throws {
    let (opt, leg) = makeEditors()

    func buildAndDelete(on pair: (Editor, any ReadOnlyTextKitContextProtocol)) throws -> String {
      var t1: TextNode! = nil; var t2: TextNode! = nil; var t3: TextNode! = nil
      let editor = pair.0
      try editor.update {
        guard let root = getRoot() else { return }
        let p1 = createParagraphNode(); let p2 = createParagraphNode(); let p3 = createParagraphNode()
        t1 = createTextNode(text: "AAAA"); t2 = createTextNode(text: "BBBB"); t3 = createTextNode(text: "CCCC")
        try p1.append([t1]); try p2.append([t2]); try p3.append([t3])
        try root.append([p1, p2, p3])
        // Select from middle of t1 to middle of t3
        let a = createPoint(key: t1.getKey(), offset: 2, type: .text)
        let f = createPoint(key: t3.getKey(), offset: 2, type: .text)
        try setSelection(RangeSelection(anchor: a, focus: f, format: TextFormat()))
      }
      try editor.update { try (getSelection() as? RangeSelection)?.removeText() }
      var out = ""; try editor.read { out = getRoot()?.getTextContent() ?? "" }
      return out
    }

    let a = try buildAndDelete(on: opt)
    let b = try buildAndDelete(on: leg)
    XCTAssertEqual(a, b)
    XCTAssertEqual(a, "AACC")
  }
}
