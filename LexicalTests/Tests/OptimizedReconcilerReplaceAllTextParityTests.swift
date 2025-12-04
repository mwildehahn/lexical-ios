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
final class OptimizedReconcilerReplaceAllTextParityTests: XCTestCase {

  private func makeEditors() -> (opt: (Editor, any ReadOnlyTextKitContextProtocol), leg: (Editor, any ReadOnlyTextKitContextProtocol)) {
    return makeParityTestEditors()
  }

  func testParity_ReplaceWholeDocumentWithText() throws {
    let (opt, leg) = makeEditors()

    func run(on pair: (Editor, any ReadOnlyTextKitContextProtocol)) throws -> String {
      let editor = pair.0
      try editor.update {
        guard let root = getRoot() else { return }
        var nodes: [Node] = []
        for i in 0..<5 { let p = createParagraphNode(); try p.append([ createTextNode(text: "P\(i)") ]); nodes.append(p) }
        try root.append(nodes)
        // Select whole document via root element selection [0, childrenCount]
        let a = createPoint(key: root.getKey(), offset: 0, type: .element)
        let f = createPoint(key: root.getKey(), offset: root.getChildrenSize(), type: .element)
        try setSelection(RangeSelection(anchor: a, focus: f, format: TextFormat()))
      }
      try editor.update { try (getSelection() as? RangeSelection)?.insertRawText(text: "Z") }
      var out = ""; try editor.read { out = getRoot()?.getTextContent() ?? "" }
      return out
    }

    let a = try run(on: opt)
    let b = try run(on: leg)
    XCTAssertEqual(a, b)
    XCTAssertEqual(a, "Z")
  }
}
