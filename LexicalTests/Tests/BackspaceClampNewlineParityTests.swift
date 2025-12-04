@testable import Lexical
import XCTest

#if os(macOS) && !targetEnvironment(macCatalyst)
@testable import LexicalAppKit
#endif

@MainActor
final class BackspaceClampNewlineParityTests: XCTestCase {

  #if os(macOS) && !targetEnvironment(macCatalyst)
  private func makeViews() -> (opt: LexicalAppKit.LexicalView, leg: LexicalAppKit.LexicalView) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let opt = LexicalAppKit.LexicalView(editorConfig: cfg, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let leg = LexicalAppKit.LexicalView(editorConfig: cfg, featureFlags: FeatureFlags())
    opt.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
    leg.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
    return (opt, leg)
  }
  #else
  private func makeViews() -> (opt: Lexical.LexicalView, leg: Lexical.LexicalView) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let opt = Lexical.LexicalView(editorConfig: cfg, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let leg = Lexical.LexicalView(editorConfig: cfg, featureFlags: FeatureFlags())
    opt.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
    leg.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
    return (opt, leg)
  }
  #endif

  // Build: "Hello\nworld" then simulate native expansion selecting the entire
  // second-line word before issuing backspace. Ensure only one character is deleted
  // (parity with legacy reconciler).
  func testParity_BackspaceAfterNewline_WithPreExpandedSelection_DeletesOneChar() throws {
    let (opt, leg) = makeViews()
    func run(_ ed: Editor) throws -> String {
      // Compose the two-line document and place caret after "world"
      try ed.update {
        guard let root = getRoot() else { return }
        let p1 = createParagraphNode(); let t1 = createTextNode(text: "Hello")
        try p1.append([t1]); try root.append([p1])
        try t1.select(anchorOffset: 5, focusOffset: 5)
        try (getSelection() as? RangeSelection)?.insertParagraph()
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertText("world")
      }

      // Simulate an over-eager native selection expansion that selects the full word on the second line
      // by selecting string range corresponding to "world".
      let full = (ed.textStorage?.string ?? "") as NSString
      let wordRange = full.range(of: "world")
      XCTAssertNotEqual(wordRange.location, NSNotFound, "Should find 'world' in attributed text")

      try ed.update {
        if let sel = try getSelection() as? RangeSelection {
          try sel.applySelectionRange(wordRange, affinity: .forward)
        }
      }

      // Now perform a backward delete; only the last character should be removed
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }

      // Return resulting plain string for assertion (from editor state)
      var out = ""
      try ed.read { out = getRoot()?.getTextContent() ?? "" }
      return out
    }

    let optOut = try run(opt.editor)
    let legOut = try run(leg.editor)
    XCTAssertEqual(optOut, legOut)
  }

  // Similar to above, but expand selection to include the newline + word (e.g., tokenizer jumped
  // from caret to a wider range). Backspace should still clamp to a single character delete.
  func testParity_BackspaceAfterNewline_ExpandedFromBreakThroughWord_DeletesOneChar() throws {
    let (opt, leg) = makeViews()
    func run(_ ed: Editor) throws -> String {
      try ed.update {
        guard let root = getRoot() else { return }
        let p1 = createParagraphNode(); let t1 = createTextNode(text: "Hello")
        try p1.append([t1]); try root.append([p1])
        try t1.select(anchorOffset: 5, focusOffset: 5)
        try (getSelection() as? RangeSelection)?.insertParagraph()
      }
      try ed.update { try (getSelection() as? RangeSelection)?.insertText("world") }

      let full = (ed.textStorage?.string ?? "") as NSString
      // Build a range that starts at the newline character and spans the whole word "world".
      // This simulates an aggressive native expansion crossing the line boundary.
      guard let nlRange = full.range(of: "\n").location != NSNotFound ? Optional(full.range(of: "\n")) : nil else {
        return ed.textStorage?.string ?? ""
      }
      let wordRange = full.range(of: "world")
      let combined = NSRange(location: nlRange.location, length: (wordRange.location + wordRange.length) - nlRange.location)

      try ed.update {
        if let sel = try getSelection() as? RangeSelection {
          try sel.applySelectionRange(combined, affinity: .forward)
        }
      }

      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      var out = ""
      try ed.read { out = getRoot()?.getTextContent() ?? "" }
      return out
    }

    let optOut = try run(opt.editor)
    let legOut = try run(leg.editor)
    XCTAssertEqual(optOut, legOut)
  }
}
