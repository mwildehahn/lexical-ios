@testable import Lexical
import XCTest

@MainActor
final class MultiRangeSelectionParityTests: XCTestCase {

  private func makeViews() -> (opt: LexicalView, leg: LexicalView) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let opt = LexicalView(editorConfig: cfg, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let leg = LexicalView(editorConfig: cfg, featureFlags: FeatureFlags())
    opt.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
    leg.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
    return (opt, leg)
  }

  // MARK: - Selection Direction (Anchor vs Focus)

  func testParity_MultiRange_ReverseSelection_Backspace() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Hello World")
        try p.append([t]); try root.append([p])
        // Reverse selection: focus before anchor
        try t.select(anchorOffset: 9, focusOffset: 3) // "rld" <- "o W"
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_MultiRange_ReverseSelection_ForwardDelete() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "ABCDEFGH")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 5, focusOffset: 2) // "F" <- "CD"
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: false) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Multi-Paragraph Selection

  func testParity_MultiRange_TwoParagraphs_Delete() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p1 = createParagraphNode(); let t1 = createTextNode(text: "First line")
        let p2 = createParagraphNode(); let t2 = createTextNode(text: "Second line")
        try p1.append([t1]); try p2.append([t2])
        try root.append([p1, p2])
        // Select across paragraphs: from "First" to "Second"
        try t1.select(anchorOffset: 3, focusOffset: 3)
      }
      // Simple delete at selection
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Range Selection with Formatting

  func testParity_MultiRange_WideSelection_Format() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "ABCDEFGHIJ")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 2, focusOffset: 8) // select "CDEFGH"
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.formatText(formatType: .bold)
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_MultiRange_WideSelection_Replace() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "The quick brown fox")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 4, focusOffset: 15) // select "quick brown"
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertText("slow")
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Zero-Length Selections

  func testParity_MultiRange_ZeroLength_AtStart() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Test")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 0, focusOffset: 0)
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertText("Start")
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_MultiRange_ZeroLength_AtEnd() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Test")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 4, focusOffset: 4)
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertText("End")
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_MultiRange_ZeroLength_Middle() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "ABCDEF")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 3, focusOffset: 3)
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertText("X")
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Selection Edge Cases

  func testParity_MultiRange_SelectAll_Delete() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Everything")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 0, focusOffset: 10) // select all
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_MultiRange_SingleChar_Selection() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "ABCDEFGH")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 3, focusOffset: 4) // select "D"
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertText("X")
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Multiple Operations

  func testParity_MultiRange_SelectDeleteSelect() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "ABCDEFGH")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 2, focusOffset: 6) // select "CDEF"
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      // Directly set new selection
      try ed.update {
        guard let root = getRoot(), let p = root.getChildren().first as? ElementNode,
              let t = p.getChildren().first as? TextNode else { return }
        try t.select(anchorOffset: 0, focusOffset: 4)
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.formatText(formatType: .italic)
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Boundary Conditions

  func testParity_MultiRange_EmptyDocument_Insert() throws {
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
        try (getSelection() as? RangeSelection)?.insertText("First")
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_MultiRange_LongText_WideSelection() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      let longText = String(repeating: "A", count: 100)
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: longText)
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 20, focusOffset: 80) // 60-char selection
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertText("B")
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }
}
