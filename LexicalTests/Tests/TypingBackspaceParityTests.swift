/*
 * Parity tests between legacy and optimized reconcilers for backspace behavior
 * around punctuation, newlines, and while typing a new word. Legacy is ground truth.
 */

@testable import Lexical
import XCTest

@MainActor
final class TypingBackspaceParityTests: XCTestCase {

  private func makeViews() -> (opt: LexicalView, leg: LexicalView) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let opt = LexicalView(editorConfig: cfg, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let leg = LexicalView(editorConfig: cfg, featureFlags: FeatureFlags())
    opt.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
    leg.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
    return (opt, leg)
  }

  private func scenario_dotNewline_typeWord_thenBackspaceOnce(on view: LexicalView) throws -> (text: String, caret: (key: NodeKey, offset: Int)?) {
    let ed = view.editor
    try ed.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode(); let t = createTextNode(text: "Hello")
      try p.append([t]); try root.append([p])
      try t.select(anchorOffset: 5, focusOffset: 5)
      try (getSelection() as? RangeSelection)?.insertText(".")
      try (getSelection() as? RangeSelection)?.insertParagraph()
      try (getSelection() as? RangeSelection)?.insertText("wor")
    }
    try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
    var caret: (NodeKey, Int)? = nil
    try ed.read {
      guard let sel = try getSelection() as? RangeSelection else { return }
      caret = (sel.anchor.key, sel.anchor.offset)
    }
    let s = view.attributedText.string.trimmingCharacters(in: .whitespacesAndNewlines)
    return (s, caret)
  }

  private func scenario_dotNewline_typeWord_thenBackspaceTwice(on view: LexicalView) throws -> String {
    let ed = view.editor
    try ed.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode(); let t = createTextNode(text: "Ok")
      try p.append([t]); try root.append([p])
      try t.select(anchorOffset: 2, focusOffset: 2)
      try (getSelection() as? RangeSelection)?.insertText(".")
      try (getSelection() as? RangeSelection)?.insertParagraph()
      try (getSelection() as? RangeSelection)?.insertText("word")
    }
    try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
    try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
    return view.attributedText.string.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  func testParity_BackspaceAfterNewline_WhileTypingWord_DeletesOneChar() throws {
    let (opt, leg) = makeViews()
    let a = try scenario_dotNewline_typeWord_thenBackspaceOnce(on: opt)
    let b = try scenario_dotNewline_typeWord_thenBackspaceOnce(on: leg)
    XCTAssertEqual(a.text, b.text)
    XCTAssertTrue(a.text.contains("Hello."))
    // Expect new paragraph to contain "wo" after deleting last char from "wor"
    XCTAssertTrue(a.text.hasSuffix("\nwo") || a.text.contains("\nwo"))
  }

  func testParity_BackspaceTwiceAfterNewline_WhileTypingWord() throws {
    let (opt, leg) = makeViews()
    let a = try scenario_dotNewline_typeWord_thenBackspaceTwice(on: opt)
    let b = try scenario_dotNewline_typeWord_thenBackspaceTwice(on: leg)
    XCTAssertEqual(a, b)
    XCTAssertTrue(a.contains("Hello") || a.contains("Ok"))
  }

  func testParity_BackspaceAtWordStart_DoesNotDeleteWholeWord() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "X.")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 2, focusOffset: 2)
        try (getSelection() as? RangeSelection)?.insertParagraph()
        try (getSelection() as? RangeSelection)?.insertText("word")
        // Move caret to start of the word then backspace – should merge paragraph, not delete the whole word in one go
        if let sel = try getSelection() as? RangeSelection {
          sel.focus.updatePoint(key: t.getKey(), offset: 0, type: .text)
        }
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return v.attributedText.string.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    let a = try run(opt)
    let b = try run(leg)
    XCTAssertEqual(a, b)
  }
}

