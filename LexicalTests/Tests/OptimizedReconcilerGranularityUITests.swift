/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import Lexical
@testable import LexicalUIKit
import XCTest
@testable import LexicalInlineImagePlugin

final class OptimizedReconcilerGranularityUITests: XCTestCase {
  private func makeOptimizedEditorView() -> (Editor, LexicalView) {
    let flags = FeatureFlags.optimizedProfile(.aggressiveEditor)
    let view = LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: flags)
    return (view.editor, view)
  }

  func testDeleteWordForward_UI() throws {
    let (editor, view) = makeOptimizedEditorView(); _ = view
    let text = "The quick brown fox"
    let caret = ("The " as NSString).length // at start of "quick"
    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode(); let t = createTextNode(text: text)
      try p.append([t]); try root.append([p])
      try t.select(anchorOffset: caret, focusOffset: caret)
    }
    try editor.update { try (getSelection() as? RangeSelection)?.deleteWord(isBackwards: false) }
    try editor.read {
      let s = getRoot()?.getTextContent() ?? ""
      let norm = s.hasPrefix("\n") ? String(s.dropFirst(1)) : s
      XCTAssertEqual(norm, "The  brown fox")
    }
  }

  func testDeleteWordBackward_UI() throws {
    let (editor, view) = makeOptimizedEditorView(); _ = view
    let text = "The quick brown"
    let caret = ("The quick" as NSString).length // after word "quick"
    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode(); let t = createTextNode(text: text)
      try p.append([t]); try root.append([p])
      try t.select(anchorOffset: caret, focusOffset: caret)
    }
    try editor.update { try (getSelection() as? RangeSelection)?.deleteWord(isBackwards: true) }
    try editor.read {
      let s = getRoot()?.getTextContent() ?? ""
      let norm = s.hasPrefix("\n") ? String(s.dropFirst(1)) : s
      XCTAssertEqual(norm, "The  brown")
    }
  }

  func testDeleteLineForward_UI() throws {
    let (editor, view) = makeOptimizedEditorView(); _ = view
    let text = "Hello World"
    let caret = ("Hello" as NSString).length // 5
    var tKey: NodeKey = ""
    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode(); let t = createTextNode(text: text)
      try p.append([t]); try root.append([p])
      tKey = t.getKey()
      try t.select(anchorOffset: caret, focusOffset: caret)
    }
    // Manually emulate a forward line delete by selecting to end-of-paragraph and deleting
    try editor.update {
      guard let sel = try getSelection() as? RangeSelection,
            let t = getNodeByKey(key: tKey) as? TextNode else { return }
      let end = t.getTextContentSize()
      sel.focus.updatePoint(key: tKey, offset: end, type: .text)
    }
    try editor.update { try (getSelection() as? RangeSelection)?.insertText("") }
    try editor.read {
      let s = getRoot()?.getTextContent() ?? ""
      let norm = s.hasPrefix("\n") ? String(s.dropFirst(1)) : s
      XCTAssertEqual(norm, "Hello")
    }
  }

  func testDeleteLineBackward_UI() throws {
    let (editor, view) = makeOptimizedEditorView(); _ = view
    let text = "Hello World"
    let caret = ("Hello " as NSString).length // before 'W'
    var tKey: NodeKey = ""
    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode(); let t = createTextNode(text: text)
      try p.append([t]); try root.append([p])
      tKey = t.getKey()
      try t.select(anchorOffset: caret, focusOffset: caret)
    }
    // Emulate backward line delete by selecting from start-of-paragraph to caret and deleting
    try editor.update {
      guard let sel = try getSelection() as? RangeSelection else { return }
      sel.anchor.updatePoint(key: tKey, offset: 0, type: .text)
    }
    try editor.update { try (getSelection() as? RangeSelection)?.insertText("") }
    try editor.read {
      let s = getRoot()?.getTextContent() ?? ""
      let norm = s.hasPrefix("\n") ? String(s.dropFirst(1)) : s
      XCTAssertEqual(norm, "World")
    }
  }

  func testGraphemeBackspace_CombiningMark_UI() throws {
    let (editor, view) = makeOptimizedEditorView(); _ = view
    let combining = "e\u{0301}" // e + combining acute
    let text = "ab" + combining + "cd"
    let caretAfter = ("ab" + combining as NSString).length
    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode(); let t = createTextNode(text: text)
      try p.append([t]); try root.append([p])
      try t.select(anchorOffset: caretAfter, focusOffset: caretAfter)
    }
    try editor.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
    try editor.read {
      let s = getRoot()?.getTextContent() ?? ""
      let norm = s.hasPrefix("\n") ? String(s.dropFirst(1)) : s
      XCTAssertEqual(norm, "abcd")
    }
  }

  func testGraphemeBackspace_ZWJEmojiFamily_UI() throws {
    let (editor, view) = makeOptimizedEditorView(); _ = view
    let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}" // 👨‍👩‍👧
    let prefix = "hi" + family
    let text = prefix + "world"
    let caretAfter = (prefix as NSString).length
    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode(); let t = createTextNode(text: text)
      try p.append([t]); try root.append([p])
      try t.select(anchorOffset: caretAfter, focusOffset: caretAfter)
    }
    try editor.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
    try editor.read {
      let s = getRoot()?.getTextContent() ?? ""
      let norm = s.hasPrefix("\n") ? String(s.dropFirst(1)) : s
      XCTAssertEqual(norm, "hiworld")
    }
  }

  func testDeleteWordForwardAcrossInlineImage_UI() throws {
    let flags = FeatureFlags.optimizedProfile(.aggressiveEditor)
    let v = LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: [InlineImagePlugin()]), featureFlags: flags)
    let editor = v.editor
    let view = v
    let text1 = "Hello "
    let text2 = "World Test"
    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode()
      let t1 = createTextNode(text: text1)
      let img = ImageNode(url: "https://example.com/inline.png", size: CGSize(width: 16, height: 16), sourceID: "i")
      let t2 = createTextNode(text: text2)
      try p.append([t1, img, t2]); try root.append([p])
      try t1.select(anchorOffset: t1.getTextPart().lengthAsNSString(), focusOffset: t1.getTextPart().lengthAsNSString())
    }
    try editor.update { try (getSelection() as? RangeSelection)?.deleteWord(isBackwards: false) }
    try editor.read {
      let s = getRoot()?.getTextContent() ?? ""
      let norm = s.hasPrefix("\n") ? String(s.dropFirst(1)) : s
      // Expect the word "World" removed; attachment ignored for text content
      XCTAssertEqual(norm, "Hello  Test")
    }
    _ = view // keep
  }

  func testAttributeToggleWhileTyping_UI() throws {
    let (editor, view) = makeOptimizedEditorView(); _ = view
    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode(); let t = createTextNode(text: "")
      try p.append([t]); try root.append([p])
      try t.select(anchorOffset: 0, focusOffset: 0)
    }
    // Toggle bold on collapsed caret, type, backspace, toggle off
    try editor.update { try (getSelection() as? RangeSelection)?.formatText(formatType: .bold) }
    try editor.update { try (getSelection() as? RangeSelection)?.insertText("Bold") }
    try editor.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) } // remove 'd'
    try editor.update { try (getSelection() as? RangeSelection)?.formatText(formatType: .bold) }
    try editor.read {
      let s = getRoot()?.getTextContent() ?? ""
      let norm = s.hasPrefix("\n") ? String(s.dropFirst(1)) : s
      XCTAssertEqual(norm, "Bol") // "Bold" -> backspace -> "Bol"
    }
  }

  func testPasteThenDeleteWord_UI() throws {
    let (editor, view) = makeOptimizedEditorView(); _ = view
    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode(); let t = createTextNode(text: "Start ")
      try p.append([t]); try root.append([p])
      try t.select(anchorOffset: t.getTextPart().lengthAsNSString(), focusOffset: t.getTextPart().lengthAsNSString())
    }
    // Simulate paste of a word + space (plain text)
    try editor.update { try (getSelection() as? RangeSelection)?.insertRawText("Pasted Word ") }
    // Delete word forward (should remove the next word if present; here caret at end, so no-op).
    try editor.update { try (getSelection() as? RangeSelection)?.deleteWord(isBackwards: false) }
    try editor.read {
      let s = getRoot()?.getTextContent() ?? ""
      let norm = s.hasPrefix("\n") ? String(s.dropFirst(1)) : s
      XCTAssertEqual(norm, "Start Pasted Word ")
    }
  }
}
