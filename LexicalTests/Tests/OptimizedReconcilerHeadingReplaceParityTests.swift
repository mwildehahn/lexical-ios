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
final class OptimizedReconcilerHeadingReplaceParityTests: XCTestCase {

  private func makeEditors() -> (opt: (Editor, any ReadOnlyTextKitContextProtocol), leg: (Editor, any ReadOnlyTextKitContextProtocol)) {
    return makeParityTestEditors()
  }

  func testParity_ReplaceParagraphWithHeading_AndBack() throws {
    let (opt, leg) = makeEditors()

    func scenario(on pair: (Editor, any ReadOnlyTextKitContextProtocol)) throws -> String {
      let editor = pair.0; let ctx = pair.1
      var paraKey: NodeKey = ""
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); try p.append([ createTextNode(text: "Title") ])
        try root.append([p]); paraKey = p.getKey()
      }
      try editor.update {
        guard let p: ParagraphNode = getNodeByKey(key: paraKey) else { return }
        let h = createHeadingNode(headingTag: .h2)
        _ = try p.replace(replaceWith: h, includeChildren: true)
      }
      try editor.update {
        guard let root = getRoot(), let h = root.getFirstChild() as? HeadingNode else { return }
        let newP = createParagraphNode(); _ = try h.replace(replaceWith: newP, includeChildren: true)
      }
      return ctx.textStorage.string
    }

    let a = try scenario(on: opt)
    let b = try scenario(on: leg)
    XCTAssertEqual(a, b)
  }
}
