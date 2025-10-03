@testable import Lexical
import XCTest

@MainActor
final class NestedBlockParityTests: XCTestCase {

  private func makeViews() -> (opt: LexicalView, leg: LexicalView) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let opt = LexicalView(editorConfig: cfg, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let leg = LexicalView(editorConfig: cfg, featureFlags: FeatureFlags())
    opt.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
    leg.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
    return (opt, leg)
  }

  // MARK: - Multiple Paragraphs

  func testParity_TwoParagraphs_Create() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p1 = createParagraphNode(); let t1 = createTextNode(text: "First")
        let p2 = createParagraphNode(); let t2 = createTextNode(text: "Second")
        try p1.append([t1]); try p2.append([t2])
        try root.append([p1, p2])
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_ThreeParagraphs_DeleteMiddle() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p1 = createParagraphNode(); let t1 = createTextNode(text: "First")
        let p2 = createParagraphNode(); let t2 = createTextNode(text: "Middle")
        let p3 = createParagraphNode(); let t3 = createTextNode(text: "Last")
        try p1.append([t1]); try p2.append([t2]); try p3.append([t3])
        try root.append([p1, p2, p3])
        try t2.select(anchorOffset: 0, focusOffset: 6)
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_MultipleParagraphs_InsertBetween() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p1 = createParagraphNode(); let t1 = createTextNode(text: "First")
        let p2 = createParagraphNode(); let t2 = createTextNode(text: "Last")
        try p1.append([t1]); try p2.append([t2])
        try root.append([p1, p2])
        try t1.select(anchorOffset: 5, focusOffset: 5)
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertParagraph()
        try (getSelection() as? RangeSelection)?.insertText("Middle")
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Paragraph Splitting

  func testParity_SplitParagraph_AtStart() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Split Me")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 0, focusOffset: 0)
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertParagraph()
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_SplitParagraph_AtMiddle() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Split Here")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 6, focusOffset: 6)
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertParagraph()
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_SplitParagraph_AtEnd() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "End Split")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 9, focusOffset: 9)
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertParagraph()
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Paragraph Merging

  func testParity_MergeParagraphs_DeleteAtBoundary() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p1 = createParagraphNode(); let t1 = createTextNode(text: "First")
        let p2 = createParagraphNode(); let t2 = createTextNode(text: "Second")
        try p1.append([t1]); try p2.append([t2])
        try root.append([p1, p2])
        try t2.select(anchorOffset: 0, focusOffset: 0)
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_MergeParagraphs_ForwardDelete() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p1 = createParagraphNode(); let t1 = createTextNode(text: "First")
        let p2 = createParagraphNode(); let t2 = createTextNode(text: "Second")
        try p1.append([t1]); try p2.append([t2])
        try root.append([p1, p2])
        try t1.select(anchorOffset: 5, focusOffset: 5)
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: false) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Empty Paragraphs

  func testParity_EmptyParagraph_Between() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p1 = createParagraphNode(); let t1 = createTextNode(text: "First")
        let p2 = createParagraphNode(); let t2 = createTextNode(text: "")
        let p3 = createParagraphNode(); let t3 = createTextNode(text: "Last")
        try p1.append([t1]); try p2.append([t2]); try p3.append([t3])
        try root.append([p1, p2, p3])
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_EmptyParagraph_Delete() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p1 = createParagraphNode(); let t1 = createTextNode(text: "Text")
        let p2 = createParagraphNode(); let t2 = createTextNode(text: "")
        try p1.append([t1]); try p2.append([t2])
        try root.append([p1, p2])
        try t2.select(anchorOffset: 0, focusOffset: 0)
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_EmptyParagraph_InsertText() throws {
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
        try (getSelection() as? RangeSelection)?.insertText("New")
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Multiple Text Nodes in Paragraph

  func testParity_MultipleTextNodes_InOneParagraph() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        let t1 = createTextNode(text: "First")
        let t2 = createTextNode(text: "Second")
        let t3 = createTextNode(text: "Third")
        try p.append([t1, t2, t3]); try root.append([p])
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_MultipleTextNodes_DeleteAcross() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        let t1 = createTextNode(text: "AAA")
        let t2 = createTextNode(text: "BBB")
        try p.append([t1, t2]); try root.append([p])
        try t1.select(anchorOffset: 2, focusOffset: 2)
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Line Breaks

  func testParity_LineBreak_Insert() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Line One")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 4, focusOffset: 4)
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertLineBreak(selectStart: false)
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_LineBreak_DeleteBackward() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        let t1 = createTextNode(text: "Line1")
        let lb = createLineBreakNode()
        let t2 = createTextNode(text: "Line2")
        try p.append([t1, lb, t2]); try root.append([p])
        try t2.select(anchorOffset: 0, focusOffset: 0)
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_LineBreak_DeleteForward() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        let t1 = createTextNode(text: "Line1")
        let lb = createLineBreakNode()
        let t2 = createTextNode(text: "Line2")
        try p.append([t1, lb, t2]); try root.append([p])
        try t1.select(anchorOffset: 5, focusOffset: 5)
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: false) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_MultipleLineBreaks() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        let t = createTextNode(text: "Text")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 4, focusOffset: 4)
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertLineBreak(selectStart: false)
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertLineBreak(selectStart: false)
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertText("After")
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Complex Nested Structures

  func testParity_ManyParagraphs_Sequential() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        for i in 1...5 {
          let p = createParagraphNode(); let t = createTextNode(text: "Line \(i)")
          try p.append([t]); try root.append([p])
        }
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_MixedContent_ParagraphsAndBreaks() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p1 = createParagraphNode()
        let t1 = createTextNode(text: "Para1")
        try p1.append([t1]); try root.append([p1])

        let p2 = createParagraphNode()
        let t2a = createTextNode(text: "Line1")
        let lb = createLineBreakNode()
        let t2b = createTextNode(text: "Line2")
        try p2.append([t2a, lb, t2b]); try root.append([p2])

        let p3 = createParagraphNode()
        let t3 = createTextNode(text: "Para3")
        try p3.append([t3]); try root.append([p3])
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Edge Cases

  func testParity_SingleEmptyParagraph() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "")
        try p.append([t]); try root.append([p])
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_ManyEmptyParagraphs() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        for _ in 1...3 {
          let p = createParagraphNode(); let t = createTextNode(text: "")
          try p.append([t]); try root.append([p])
        }
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_AlternatingEmptyFull() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p1 = createParagraphNode(); let t1 = createTextNode(text: "Full")
        let p2 = createParagraphNode(); let t2 = createTextNode(text: "")
        let p3 = createParagraphNode(); let t3 = createTextNode(text: "Full")
        try p1.append([t1]); try p2.append([t2]); try p3.append([t3])
        try root.append([p1, p2, p3])
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }
}
