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
final class SelectionStabilityReorderLargeUnrelatedEditsTests: XCTestCase {

  private func makeEditors() -> (opt: (Editor, any ReadOnlyTextKitContextProtocol), leg: (Editor, any ReadOnlyTextKitContextProtocol)) {
    return makeParityTestEditors()
  }

  private func buildLargeDoc(on editor: Editor, paragraphs: Int) throws {
    try editor.update {
      guard let root = getRoot() else { return }
      var nodes: [Node] = []
      for i in 0..<paragraphs {
        let p = createParagraphNode()
        try p.append([ createTextNode(text: String(repeating: "x", count: 16) + "-\(i)") ])
        nodes.append(p)
      }
      try root.append(nodes)
    }
  }

  func testSelectionStable_WithTailReordersAndEdits() throws {
    let (opt, leg) = makeEditors()
    try buildLargeDoc(on: opt.0, paragraphs: 400)
    try buildLargeDoc(on: leg.0, paragraphs: 400)

    // First, perform a tail reorder on both editors (unrelated to selection we will place later)
    func onlyReorder(_ editor: Editor) throws {
      try editor.update {
        guard let root = getRoot() else { return }
        for _ in 0..<10 {
          if let last = root.getLastChild(), let first = root.getFirstChild() {
            try last.remove(); _ = try first.insertBefore(nodeToInsert: last)
          }
        }
      }
    }
    try onlyReorder(opt.0)
    try onlyReorder(leg.0)

    func placeCaret(_ editor: Editor) throws -> Int {
      var loc = -1
      try editor.update {
        guard let root = getRoot(), let p = root.getChildren()[safe: 20] as? ParagraphNode, let t = p.getFirstChild() as? TextNode else { return }
        _ = try t.select(anchorOffset: 8, focusOffset: 8)
      }
      try editor.read {
        if let sel = try getSelection() as? RangeSelection {
          loc = try stringLocationForPoint(sel.anchor, editor: editor) ?? -1
        }
      }
      return loc
    }
    let l0Opt = try placeCaret(opt.0)
    let l0Leg = try placeCaret(leg.0)
    XCTAssertEqual(l0Opt, l0Leg)

    func tailEdits(_ editor: Editor) throws {
      try editor.update {
        guard let root = getRoot() else { return }
        // toggle italic in a safe tail range and append text
        let children = root.getChildren()
        let start = min(150, children.count)
        let end = min(start + 20, children.count)
        for idx in start..<end {
          if let p = children[idx] as? ParagraphNode, let t = p.getFirstChild() as? TextNode {
            try t.setItalic(true); try t.setText(t.getTextPart() + "!")
          }
        }
      }
    }
    // Now only apply the tail edits; the reorder already happened.
    try tailEdits(opt.0)
    try tailEdits(leg.0)

    func caretLoc(_ editor: Editor) throws -> Int {
      var loc = -1
      try editor.read {
        guard let sel = try getSelection() as? RangeSelection else { return }
        loc = try stringLocationForPoint(sel.anchor, editor: editor) ?? -1
      }
      return loc
    }
    XCTAssertEqual(try caretLoc(opt.0), l0Opt)
    XCTAssertEqual(try caretLoc(leg.0), l0Leg)
    XCTAssertEqual(try caretLoc(opt.0), try caretLoc(leg.0))
  }
}

private extension Array {
  func chunked(into size: Int) -> [[Element]] {
    stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
  }
  subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
