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
final class OptimizedReconcilerLegacyParityReorderTextMixTests: XCTestCase {

  private func makeEditors() -> (opt: (Editor, any ReadOnlyTextKitContextProtocol), leg: (Editor, any ReadOnlyTextKitContextProtocol)) {
    return makeParityTestEditors()
  }

  func testReorderAndEditInsideMovedNode_Parity() throws {
    let (opt, leg) = makeEditors()

    func build(on editor: Editor) throws -> (NodeKey, NodeKey, NodeKey) {
      var aKey: NodeKey = ""; var bKey: NodeKey = ""; var cKey: NodeKey = ""
      try editor.update {
        guard let root = getRoot() else { return }
        let a = createParagraphNode(); aKey = a.getKey(); try a.append([ createTextNode(text: "A") ])
        let b = createParagraphNode(); bKey = b.getKey(); try b.append([ createTextNode(text: "B") ])
        let c = createParagraphNode(); cKey = c.getKey(); try c.append([ createTextNode(text: "C") ])
        try root.append([a, b, c])
      }
      return (aKey, bKey, cKey)
    }
    let (ao, bo, co) = try build(on: opt.0)
    let (al, bl, cl) = try build(on: leg.0)

    // Update both: move C to front, and change C's text to "CX" in same update.
    try opt.0.update {
      guard let a = getNodeByKey(key: ao) as? ParagraphNode,
            let c = getNodeByKey(key: co) as? ParagraphNode,
            let ct = c.getFirstChild() as? TextNode else { return }
      _ = try a.insertBefore(nodeToInsert: c)
      ct.setText_dangerousPropertyAccess("CX")
    }
    try leg.0.update {
      guard let a = getNodeByKey(key: al) as? ParagraphNode,
            let c = getNodeByKey(key: cl) as? ParagraphNode,
            let ct = c.getFirstChild() as? TextNode else { return }
      _ = try a.insertBefore(nodeToInsert: c)
      ct.setText_dangerousPropertyAccess("CX")
    }

    XCTAssertEqual(opt.1.textStorage.string, leg.1.textStorage.string)
  }
}
