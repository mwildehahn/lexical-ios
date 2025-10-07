/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import Lexical
@testable import LexicalUIKit
import XCTest

@MainActor
final class OptimizedReconcilerLiveParityTests: XCTestCase {

  private func makeEditors() -> (opt: (Editor, LexicalReadOnlyTextKitContext), leg: (Editor, LexicalReadOnlyTextKitContext)) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let optFlags = FeatureFlags.optimizedProfile(.aggressiveEditor)
    let legFlags = FeatureFlags()
    let opt = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: optFlags)
    let leg = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: legFlags)
    return ((opt.editor, opt), (leg.editor, leg))
  }

  func testParity_BackspaceSingleChar() throws {
    let (opt, leg) = makeEditors()

    func buildAndDelete(on editor: Editor) throws -> String {
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Hey")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 3, focusOffset: 3)
      }
      try editor.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      var out = ""
      try editor.read { out = getRoot()?.getTextContent() ?? "" }
      return out
    }

    let a = try buildAndDelete(on: opt.0)
    // Optimized caret parity: caret should be collapsed at end of the only text node
    try opt.0.read {
      guard let root = getRoot(), let p = root.getLastChild() as? ParagraphNode,
            let t = p.getLastChild() as? TextNode,
            let sel = try getSelection() as? RangeSelection else { return XCTFail("Tree or selection unexpected") }
      XCTAssertTrue(sel.anchor.key == sel.focus.key && sel.anchor.offset == sel.focus.offset)
      XCTAssertEqual(sel.anchor.offset, t.getTextPart().lengthAsNSString())
    }

    let b = try buildAndDelete(on: leg.0)
    // Legacy caret parity
    try leg.0.read {
      guard let root = getRoot(), let p = root.getLastChild() as? ParagraphNode,
            let t = p.getLastChild() as? TextNode,
            let sel = try getSelection() as? RangeSelection else { return XCTFail("Tree or selection unexpected") }
      XCTAssertTrue(sel.anchor.key == sel.focus.key && sel.anchor.offset == sel.focus.offset)
      XCTAssertEqual(sel.anchor.offset, t.getTextPart().lengthAsNSString())
    }
    XCTAssertEqual(a, b)
    XCTAssertEqual(a, "He")
  }

  func testParity_InsertParagraphThenType() throws {
    let (opt, leg) = makeEditors()

    func buildAndInsert(on editor: Editor) throws -> String {
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Hello")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 5, focusOffset: 5)
        try (getSelection() as? RangeSelection)?.insertParagraph()
      }
      try editor.update { try (getSelection() as? RangeSelection)?.insertText("Hey") }
      var out = ""
      try editor.read { out = getRoot()?.getTextContent() ?? "" }
      return out
    }

    let a = try buildAndInsert(on: opt.0)
    // Optimized caret parity after typing "Hey" on second paragraph
    try opt.0.read {
      guard let root = getRoot(), let p2 = root.getLastChild() as? ParagraphNode,
            let t2 = p2.getLastChild() as? TextNode,
            let sel = try getSelection() as? RangeSelection else { return XCTFail("Tree or selection unexpected") }
      XCTAssertTrue(sel.anchor.key == sel.focus.key && sel.anchor.offset == sel.focus.offset)
      XCTAssertEqual(sel.anchor.offset, t2.getTextPart().lengthAsNSString())
    }

    let b = try buildAndInsert(on: leg.0)
    // Legacy caret parity after typing "Hey"
    try leg.0.read {
      guard let root = getRoot(), let p2 = root.getLastChild() as? ParagraphNode,
            let t2 = p2.getLastChild() as? TextNode,
            let sel = try getSelection() as? RangeSelection else { return XCTFail("Tree or selection unexpected") }
      XCTAssertTrue(sel.anchor.key == sel.focus.key && sel.anchor.offset == sel.focus.offset)
      XCTAssertEqual(sel.anchor.offset, t2.getTextPart().lengthAsNSString())
    }
    XCTAssertEqual(a, b)
    XCTAssertEqual(a, "Hello\nHey")
  }

  func testReadOnlyBackspaceAndForwardDelete_Fallback() throws {
    // Verify deleteCharacter() behaves correctly in read-only frontend without native selection movement.
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let ro = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: FeatureFlags())
    let editor = ro.editor

    // Backspace at end → remove last character
    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode(); let t = createTextNode(text: "Hey")
      try p.append([t]); try root.append([p])
      try t.select(anchorOffset: 3, focusOffset: 3)
    }
    try editor.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
    try editor.read { XCTAssertEqual(getRoot()?.getTextContent(), "He") }

    // Forward delete at start → remove first character
    try editor.update {
      guard let root = getRoot(), let p = root.getLastChild() as? ParagraphNode,
            let t = p.getFirstChild() as? TextNode else { return }
      try t.setText("Hey")
      try t.select(anchorOffset: 0, focusOffset: 0)
    }
    try editor.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: false) }
    try editor.read { XCTAssertEqual(getRoot()?.getTextContent(), "ey") }
  }

  func testParity_BackspaceAtStartMergesParagraphs() throws {
    let (opt, leg) = makeEditors()

    func buildAndBackspace(on editor: Editor) throws -> (String, Int) {
      try editor.update {
        guard let root = getRoot() else { return }
        let p1 = createParagraphNode(); let t1 = createTextNode(text: "ABC")
        let p2 = createParagraphNode(); let t2 = createTextNode(text: "DEF")
        try p1.append([t1]); try p2.append([t2]); try root.append([p1, p2])
        try t2.select(anchorOffset: 0, focusOffset: 0)
      }
      try editor.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      var out = ""; var caret = -1
      try editor.read {
        out = getRoot()?.getTextContent() ?? ""
        if let p = getRoot()?.getFirstChild() as? ParagraphNode,
           let t = p.getFirstChild() as? TextNode,
           let sel = try getSelection() as? RangeSelection {
          _ = t // keep for clarity
          caret = sel.anchor.offset
        }
      }
      return (out, caret)
    }

    let (a, aCaret) = try buildAndBackspace(on: opt.0)
    let (b, bCaret) = try buildAndBackspace(on: leg.0)
    XCTAssertEqual(a, b)
    if aCaret >= 0 && bCaret >= 0 { XCTAssertEqual(aCaret, bCaret) }
  }

  func testParity_ForwardDeleteAtEndMergesParagraphs() throws {
    let (opt, leg) = makeEditors()

    func buildAndForwardDelete(on editor: Editor) throws -> (String, Int) {
      try editor.update {
        guard let root = getRoot() else { return }
        let p1 = createParagraphNode(); let t1 = createTextNode(text: "ABC")
        let p2 = createParagraphNode(); let t2 = createTextNode(text: "DEF")
        try p1.append([t1]); try p2.append([t2]); try root.append([p1, p2])
        try t1.select(anchorOffset: 3, focusOffset: 3)
      }
      try editor.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: false) }
      var out = ""; var caret = -1
      try editor.read {
        out = getRoot()?.getTextContent() ?? ""
        if let sel = try getSelection() as? RangeSelection { caret = sel.anchor.offset }
      }
      return (out, caret)
    }

    let (a, aCaret) = try buildAndForwardDelete(on: opt.0)
    let (b, bCaret) = try buildAndForwardDelete(on: leg.0)
    XCTAssertEqual(a, b)
    if aCaret >= 0 && bCaret >= 0 { XCTAssertEqual(aCaret, bCaret) }
  }

  func testParity_SplitParagraphAtMiddle() throws {
    let (opt, leg) = makeEditors()

    func buildAndSplit(on editor: Editor) throws -> String {
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "HelloWorld")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 5, focusOffset: 5)
        try (getSelection() as? RangeSelection)?.insertParagraph()
      }
      var out = ""; try editor.read { out = getRoot()?.getTextContent() ?? "" }
      return out
    }

    let a = try buildAndSplit(on: opt.0)
    let b = try buildAndSplit(on: leg.0)
    XCTAssertEqual(a, b)
    XCTAssertEqual(a, "Hello\nWorld")
  }

  func testParity_RangeDeleteAcrossParagraphBoundary() throws {
    let (opt, leg) = makeEditors()

    func buildAndRangeDelete(on editor: Editor) throws -> String {
      var t1: TextNode! = nil; var t2: TextNode! = nil
      try editor.update {
        guard let root = getRoot() else { return }
        let p1 = createParagraphNode(); let p2 = createParagraphNode()
        t1 = createTextNode(text: "Hello"); t2 = createTextNode(text: "World")
        try p1.append([t1]); try p2.append([t2]); try root.append([p1, p2])
        // Cross-paragraph selection: end of t1 → start of t2
        let a = createPoint(key: t1.getKey(), offset: t1.getTextPart().lengthAsNSString(), type: .text)
        let f = createPoint(key: t2.getKey(), offset: 0, type: .text)
        let sel = RangeSelection(anchor: a, focus: f, format: TextFormat())
        try setSelection(sel)
      }
      try editor.update { try (getSelection() as? RangeSelection)?.removeText() }
      var out = ""; try editor.read { out = getRoot()?.getTextContent() ?? "" }
      return out
    }

    let a = try buildAndRangeDelete(on: opt.0)
    let b = try buildAndRangeDelete(on: leg.0)
    XCTAssertEqual(a, b)
    XCTAssertEqual(a, "HelloWorld")
  }

  func testParity_GraphemeClusterBackspace() throws {
    // Family emoji is a multi-scalar ZWJ sequence; backspace should remove it as one character.
    let (opt, leg) = makeEditors()
    let emoji = "👨‍👩‍👦‍👦" // ZWJ sequence

    func buildAndBackspace(on editor: Editor) throws -> String {
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "A\(emoji)B")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: ("A\(emoji)").lengthAsNSString(), focusOffset: ("A\(emoji)").lengthAsNSString())
      }
      try editor.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      var out = ""; try editor.read { out = getRoot()?.getTextContent() ?? "" }
      return out
    }

    let a = try buildAndBackspace(on: opt.0)
    let b = try buildAndBackspace(on: leg.0)
    XCTAssertEqual(a, b)
  }
}
