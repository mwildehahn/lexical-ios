@testable import Lexical
import XCTest

@MainActor
final class ClipboardOperationsParityTests: XCTestCase {

  private func makeViews() -> (opt: LexicalView, leg: LexicalView) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let opt = LexicalView(editorConfig: cfg, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let leg = LexicalView(editorConfig: cfg, featureFlags: FeatureFlags())
    opt.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
    leg.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
    return (opt, leg)
  }

  // MARK: - Copy Operations

  func testParity_Copy_SimpleText() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Hello World")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 0, focusOffset: 5) // select "Hello"
      }
      // Copy would use system clipboard, but we can test selection state
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_Copy_FormattedText() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Bold Text")
        var fmt = TextFormat(); fmt.bold = true
        _ = try t.setFormat(format: fmt)
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 0, focusOffset: 4) // select "Bold"
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_Copy_MultiParagraph() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p1 = createParagraphNode(); let t1 = createTextNode(text: "First")
        let p2 = createParagraphNode(); let t2 = createTextNode(text: "Second")
        try p1.append([t1]); try p2.append([t2])
        try root.append([p1, p2])
        try t1.select(anchorOffset: 0, focusOffset: 5)
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Cut Operations

  func testParity_Cut_SimpleText_Delete() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Cut This Text")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 4, focusOffset: 8) // select "This"
      }
      // Simulate cut by deleting selection
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_Cut_EntireLine() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Entire Line")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 0, focusOffset: 11) // select all
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_Cut_WithFormatting() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Bold Text Here")
        var fmt = TextFormat(); fmt.bold = true
        _ = try t.setFormat(format: fmt)
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 5, focusOffset: 9) // select "Text"
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Paste Operations

  func testParity_Paste_SimplePlainText() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Before")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 6, focusOffset: 6)
      }
      // Simulate paste by inserting text
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertText(" Pasted")
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_Paste_ReplaceSelection() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Replace THIS word")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 8, focusOffset: 12) // select "THIS"
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertText("THAT")
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_Paste_MultilineText() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Start")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 5, focusOffset: 5)
      }
      // Paste with newline (creates paragraph)
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertText("\n")
        try (getSelection() as? RangeSelection)?.insertText("Next line")
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_Paste_AtBeginning() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "End")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 0, focusOffset: 0)
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertText("Beginning ")
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_Paste_AtEnd() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Start")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 5, focusOffset: 5)
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertText(" Ending")
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Copy-Paste Sequences

  func testParity_CopyPaste_Sequence() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Copy Me")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 0, focusOffset: 4) // "Copy"
      }
      // Collapse to end and paste
      try ed.update {
        guard let root = getRoot(), let p = root.getChildren().first as? ElementNode,
              let t = p.getChildren().first as? TextNode else { return }
        try t.select(anchorOffset: 7, focusOffset: 7)
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertText(" Copy")
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_CutPaste_Sequence() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Move This Text")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 5, focusOffset: 9) // "This"
      }
      // Delete selection
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      // Move to end and paste
      try ed.update {
        guard let root = getRoot(), let p = root.getChildren().first as? ElementNode,
              let t = p.getChildren().first as? TextNode else { return }
        try t.select(anchorOffset: t.getTextPart().lengthAsNSString(), focusOffset: t.getTextPart().lengthAsNSString())
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertText(" This")
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Special Characters in Clipboard

  func testParity_Paste_Unicode() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Test: ")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 6, focusOffset: 6)
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertText("你好 😀")
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_Paste_Emoji() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Emoji: ")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 7, focusOffset: 7)
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertText("👨‍👩‍👧‍👦")
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_Paste_SpecialWhitespace() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "A")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 1, focusOffset: 1)
      }
      // Non-breaking space
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertText("\u{00A0}B")
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Edge Cases

  func testParity_Paste_EmptyString() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Text")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 2, focusOffset: 2)
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertText("")
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_Paste_VeryLongText() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      let longText = String(repeating: "A", count: 500)
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Start ")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 6, focusOffset: 6)
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertText(longText)
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_Paste_ReplaceAll() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Replace Everything")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 0, focusOffset: 18) // select all
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertText("New")
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }
}
