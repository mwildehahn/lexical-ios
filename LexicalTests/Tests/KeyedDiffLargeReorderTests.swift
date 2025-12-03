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
final class KeyedDiffLargeReorderTests: XCTestCase {

  func makeEditors() -> (opt: (Editor, any ReadOnlyTextKitContextProtocol), leg: (Editor, any ReadOnlyTextKitContextProtocol)) {
    return makeParityTestEditors()
  }

  func buildParagraph(editor: Editor, count: Int) throws -> [NodeKey] {
    var keys: [NodeKey] = []
    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode()
      for i in 0..<count {
        let t = createTextNode(text: String(UnicodeScalar(65 + (i % 26))!)) // A,B,C...
        keys.append(t.getKey())
        try p.append([t])
      }
      try root.append([p])
    }
    return keys
  }

  func testLargeShuffleParity() throws {
    let (opt, leg) = makeEditors()
    _ = try buildParagraph(editor: opt.0, count: 10)
    _ = try buildParagraph(editor: leg.0, count: 10)

    // Shuffle pattern: interleave reverse
    func doShuffle(_ editor: Editor) throws {
      try editor.update {
        guard let p = getRoot()?.getFirstChild() as? ParagraphNode else { return }
        let children = p.getChildrenKeys(fromLatest: false)
        var i = 0; var j = children.count - 1
        while i < j {
          guard let left = getNodeByKey(key: children[i]), let right = getNodeByKey(key: children[j]) else { break }
          _ = try left.insertBefore(nodeToInsert: right)
          i += 1; j -= 1
        }
      }
    }
    try doShuffle(opt.0)
    try doShuffle(leg.0)

    XCTAssertEqual(opt.1.textStorage.string, leg.1.textStorage.string)
  }

  // UIKit-only: Uses TestDecoratorNode which is UIKit-specific
  #if !os(macOS) || targetEnvironment(macCatalyst)
  func testDecoratorInterleavedReorderParity() throws {
    let (opt, leg) = makeEditors()

    func buildMixed(_ editor: Editor) throws {
      try editor.registerNode(nodeType: .testNode, class: TestDecoratorNode.self)
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        // T, D, T, D, T, D
        try p.append([ createTextNode(text: "A"), TestDecoratorNode(), createTextNode(text: "B"), TestDecoratorNode(), createTextNode(text: "C"), TestDecoratorNode() ])
        try root.append([p])
      }
    }
    try buildMixed(opt.0)
    try buildMixed(leg.0)

    func reverse(_ editor: Editor) throws {
      try editor.update {
        guard let p = getRoot()?.getFirstChild() as? ParagraphNode else { return }
        let children = p.getChildrenKeys(fromLatest: false)
        for k in children.reversed() {
          guard let node = getNodeByKey(key: k) else { continue }
          _ = try p.append([node]) // move to end preserving relative reverse order
        }
      }
    }
    try reverse(opt.0)
    try reverse(leg.0)

    XCTAssertEqual(opt.1.textStorage.string, leg.1.textStorage.string)
  }
  #endif
}
