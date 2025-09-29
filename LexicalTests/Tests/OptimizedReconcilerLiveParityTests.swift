/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import Lexical
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
}
