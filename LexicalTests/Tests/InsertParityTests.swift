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
final class InsertParityTests: XCTestCase {

  func makeEditors() -> (opt: (Editor, any ReadOnlyTextKitContextProtocol), leg: (Editor, any ReadOnlyTextKitContextProtocol)) {
    return makeParityTestEditors()
  }

  func seed(_ editor: Editor, paragraphs: Int) throws {
    try editor.update {
      guard let root = getRoot() else { return }
      var arr: [Node] = []
      for i in 0..<paragraphs { let p = ParagraphNode(); let t = TextNode(text: "P#\(i)"); try p.append([t]); arr.append(p) }
      try root.append(arr)
    }
  }

  func insertTop(_ editor: Editor) throws {
    try editor.update {
      guard let root = getRoot(), let first = root.getFirstChild() else { return }
      let p = ParagraphNode(); let t = TextNode(text: "INS_TOP"); try p.append([t]); _ = try first.insertBefore(nodeToInsert: p)
    }
  }

  func insertMid(_ editor: Editor) throws {
    try editor.update {
      guard let root = getRoot() else { return }
      let idx = max(0, root.getChildrenSize()/2)
      let p = ParagraphNode(); let t = TextNode(text: "INS_MID"); try p.append([t])
      if let mid = root.getChildAtIndex(index: idx) { _ = try mid.insertBefore(nodeToInsert: p) } else { try root.append([p]) }
    }
  }

  func insertEnd(_ editor: Editor) throws {
    try editor.update {
      guard let root = getRoot() else { return }
      let p = ParagraphNode(); let t = TextNode(text: "INS_END"); try p.append([t]); try root.append([p])
    }
  }

  func testInsertTopMidEndParity() throws {
    let (opt, leg) = makeEditors()
    try seed(opt.0, paragraphs: 60)
    try seed(leg.0, paragraphs: 60)

    try insertTop(opt.0); try insertTop(leg.0)
    try insertMid(opt.0); try insertMid(leg.0)
    try insertEnd(opt.0); try insertEnd(leg.0)

    XCTAssertEqual(opt.1.textStorage.string, leg.1.textStorage.string)
  }

  func buildWithCaret(on editor: Editor, paragraphs: Int, caretIndex: Int) throws -> NodeKey {
    var caretKey: NodeKey = ""
    try editor.update {
      guard let root = getRoot() else { return }
      var arr: [Node] = []
      for i in 0..<paragraphs {
        let p = ParagraphNode(); let t = TextNode(text: "Para#\(i)")
        if i == caretIndex { caretKey = t.getKey() }
        try p.append([t]); arr.append(p)
      }
      try root.append(arr)
      if let t = getNodeByKey(key: caretKey) as? TextNode { _ = try t.select(anchorOffset: nil, focusOffset: nil) }
    }
    return caretKey
  }

  func selectionAnchor(_ editor: Editor) throws -> (NodeKey, Int, SelectionType) {
    var out: (NodeKey, Int, SelectionType) = ("", -1, .text)
    try editor.update {
      guard let sel = try getSelection() as? RangeSelection else { return }
      out = (sel.anchor.key, sel.anchor.offset, sel.anchor.type)
    }
    return out
  }

  func testInsertTopKeepsSelectionMapping() throws {
    let (opt, leg) = makeEditors()
    let caretOpt = try buildWithCaret(on: opt.0, paragraphs: 40, caretIndex: 20)
    let caretLeg = try buildWithCaret(on: leg.0, paragraphs: 40, caretIndex: 20)
    let beforeOpt = try selectionAnchor(opt.0); let beforeLeg = try selectionAnchor(leg.0)
    try insertTop(opt.0); try insertTop(leg.0)
    let afterOpt = try selectionAnchor(opt.0); let afterLeg = try selectionAnchor(leg.0)
    XCTAssertEqual(beforeOpt.0, caretOpt); XCTAssertEqual(afterOpt.0, caretOpt)
    XCTAssertEqual(beforeLeg.0, caretLeg); XCTAssertEqual(afterLeg.0, caretLeg)
    XCTAssertEqual(beforeOpt.1, afterOpt.1)
    XCTAssertEqual(beforeLeg.1, afterLeg.1)
    XCTAssertEqual(opt.1.textStorage.string, leg.1.textStorage.string)
  }

  func testInsertMiddleKeepsSelectionMapping() throws {
    let (opt, leg) = makeEditors()
    let caretOpt = try buildWithCaret(on: opt.0, paragraphs: 40, caretIndex: 30) // selection after middle
    let caretLeg = try buildWithCaret(on: leg.0, paragraphs: 40, caretIndex: 30)
    let beforeOpt = try selectionAnchor(opt.0); let beforeLeg = try selectionAnchor(leg.0)
    try insertMid(opt.0); try insertMid(leg.0)
    let afterOpt = try selectionAnchor(opt.0); let afterLeg = try selectionAnchor(leg.0)
    XCTAssertEqual(beforeOpt.0, caretOpt); XCTAssertEqual(afterOpt.0, caretOpt)
    XCTAssertEqual(beforeLeg.0, caretLeg); XCTAssertEqual(afterLeg.0, caretLeg)
    XCTAssertEqual(beforeOpt.1, afterOpt.1)
    XCTAssertEqual(beforeLeg.1, afterLeg.1)
    XCTAssertEqual(opt.1.textStorage.string, leg.1.textStorage.string)
  }

  func testInsertEndKeepsSelectionMapping() throws {
    let (opt, leg) = makeEditors()
    let caretOpt = try buildWithCaret(on: opt.0, paragraphs: 40, caretIndex: 10)
    let caretLeg = try buildWithCaret(on: leg.0, paragraphs: 40, caretIndex: 10)
    let beforeOpt = try selectionAnchor(opt.0); let beforeLeg = try selectionAnchor(leg.0)
    try insertEnd(opt.0); try insertEnd(leg.0)
    let afterOpt = try selectionAnchor(opt.0); let afterLeg = try selectionAnchor(leg.0)
    XCTAssertEqual(beforeOpt.0, caretOpt); XCTAssertEqual(afterOpt.0, caretOpt)
    XCTAssertEqual(beforeLeg.0, caretLeg); XCTAssertEqual(afterLeg.0, caretLeg)
    XCTAssertEqual(beforeOpt.1, afterOpt.1)
    XCTAssertEqual(beforeLeg.1, afterLeg.1)
    XCTAssertEqual(opt.1.textStorage.string, leg.1.textStorage.string)
  }
}
