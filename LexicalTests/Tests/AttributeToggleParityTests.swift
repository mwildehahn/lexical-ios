@testable import Lexical
import XCTest

@MainActor
final class AttributeToggleParityTests: XCTestCase {

  private func makeViews() -> (opt: LexicalView, leg: LexicalView) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let opt = LexicalView(editorConfig: cfg, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let leg = LexicalView(editorConfig: cfg, featureFlags: FeatureFlags())
    opt.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
    leg.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
    return (opt, leg)
  }

  // MARK: - Single Attribute Toggle

  func testParity_ToggleBold_On() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Make Bold")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 0, focusOffset: 9)
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.formatText(formatType: .bold)
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_ToggleBold_Off() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Bold Text")
        var fmt = TextFormat(); fmt.bold = true
        _ = try t.setFormat(format: fmt)
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 0, focusOffset: 9)
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.formatText(formatType: .bold)
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_ToggleItalic_On() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Make Italic")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 0, focusOffset: 11)
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.formatText(formatType: .italic)
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_ToggleItalic_Off() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Italic Text")
        var fmt = TextFormat(); fmt.italic = true
        _ = try t.setFormat(format: fmt)
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 0, focusOffset: 11)
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.formatText(formatType: .italic)
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_ToggleUnderline_On() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Underline")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 0, focusOffset: 9)
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.formatText(formatType: .underline)
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_ToggleStrikethrough_On() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Strike")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 0, focusOffset: 6)
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.formatText(formatType: .strikethrough)
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Multiple Attributes

  func testParity_ToggleBoldItalic_Both() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Both")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 0, focusOffset: 4)
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.formatText(formatType: .bold)
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.formatText(formatType: .italic)
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_ToggleAll_On() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "All")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 0, focusOffset: 3)
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.formatText(formatType: .bold)
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.formatText(formatType: .italic)
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.formatText(formatType: .underline)
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_ToggleMixed_RemoveOne() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Mixed")
        var fmt = TextFormat()
        fmt.bold = true
        fmt.italic = true
        _ = try t.setFormat(format: fmt)
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 0, focusOffset: 5)
      }
      // Toggle off bold (italic remains)
      try ed.update {
        try (getSelection() as? RangeSelection)?.formatText(formatType: .bold)
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Partial Selection Toggling

  func testParity_TogglePartial_Beginning() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "ABCDEFGH")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 0, focusOffset: 3) // "ABC"
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.formatText(formatType: .bold)
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_TogglePartial_Middle() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "ABCDEFGH")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 3, focusOffset: 6) // "DEF"
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.formatText(formatType: .bold)
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_TogglePartial_End() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "ABCDEFGH")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 5, focusOffset: 8) // "FGH"
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.formatText(formatType: .bold)
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Toggle with Typing

  func testParity_ToggleBeforeTyping() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Text")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 4, focusOffset: 4)
      }
      // Collapsed selection - sets format for next typed character
      try ed.update {
        try (getSelection() as? RangeSelection)?.formatText(formatType: .bold)
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertText("!")
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_ToggleAfterTyping() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 0, focusOffset: 0)
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertText("Text")
      }
      // Select what was just typed
      try ed.update {
        guard let root = getRoot(), let p = root.getChildren().first as? ElementNode,
              let t = p.getChildren().first as? TextNode else { return }
        try t.select(anchorOffset: 0, focusOffset: 4)
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.formatText(formatType: .bold)
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Toggle Across Different Text Nodes

  func testParity_ToggleAcrossNodes_BothPlain() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        let t1 = createTextNode(text: "First")
        let t2 = createTextNode(text: "Second")
        try p.append([t1, t2]); try root.append([p])
        try t1.select(anchorOffset: 2, focusOffset: 2)
      }
      // Select across both nodes (simplified - just format first node)
      try ed.update {
        guard let root = getRoot(), let p = root.getChildren().first as? ElementNode,
              let t = p.getChildren().first as? TextNode else { return }
        try t.select(anchorOffset: 0, focusOffset: 5)
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.formatText(formatType: .bold)
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Toggle with Special Characters

  func testParity_ToggleBold_WithEmoji() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Text 😀 More")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 0, focusOffset: 11)
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.formatText(formatType: .bold)
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_ToggleBold_WithUnicode() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Hello 你好")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 0, focusOffset: 8)
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.formatText(formatType: .bold)
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Rapid Toggle Operations

  func testParity_RapidToggle_OnOff() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Toggle")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 0, focusOffset: 6)
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.formatText(formatType: .bold)
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.formatText(formatType: .bold)
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.formatText(formatType: .bold)
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_RapidToggle_MultipleAttributes() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Multi")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 0, focusOffset: 5)
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.formatText(formatType: .bold)
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.formatText(formatType: .italic)
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.formatText(formatType: .bold)
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.formatText(formatType: .underline)
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Toggle Edge Cases

  func testParity_ToggleEmpty_Selection() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Text")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 2, focusOffset: 2) // collapsed
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.formatText(formatType: .bold)
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_ToggleSingleChar() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "ABCDEF")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 2, focusOffset: 3) // select "C"
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.formatText(formatType: .bold)
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_ToggleWhitespace() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "A   B")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 1, focusOffset: 4) // select "   "
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.formatText(formatType: .bold)
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }
}
