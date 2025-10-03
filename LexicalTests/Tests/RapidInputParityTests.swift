@testable import Lexical
import XCTest

@MainActor
final class RapidInputParityTests: XCTestCase {

  private func makeViews() -> (opt: LexicalView, leg: LexicalView) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let opt = LexicalView(editorConfig: cfg, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let leg = LexicalView(editorConfig: cfg, featureFlags: FeatureFlags())
    opt.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
    leg.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
    return (opt, leg)
  }

  // MARK: - Rapid Character Insertion

  func testParity_RapidTyping_Sequential() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 0, focusOffset: 0)
      }
      // Simulate rapid typing
      for char in "ABCDEFGHIJ" {
        try ed.update {
          try (getSelection() as? RangeSelection)?.insertText(String(char))
        }
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_RapidTyping_WithSpaces() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 0, focusOffset: 0)
      }
      // Type word by word
      for word in ["Quick", " ", "brown", " ", "fox"] {
        try ed.update {
          try (getSelection() as? RangeSelection)?.insertText(word)
        }
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_RapidTyping_Numbers() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 0, focusOffset: 0)
      }
      for i in 0..<10 {
        try ed.update {
          try (getSelection() as? RangeSelection)?.insertText(String(i))
        }
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Rapid Deletion

  func testParity_RapidDelete_Backspace() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "ABCDEFGHIJ")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 10, focusOffset: 10)
      }
      // Delete 5 characters rapidly
      for _ in 0..<5 {
        try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_RapidDelete_Forward() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "ABCDEFGHIJ")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 0, focusOffset: 0)
      }
      // Forward delete 5 characters
      for _ in 0..<5 {
        try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: false) }
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_RapidDelete_All() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "12345")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 5, focusOffset: 5)
      }
      // Delete all
      for _ in 0..<5 {
        try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Rapid Type-Delete Sequences

  func testParity_TypeDeleteType() throws {
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
        try (getSelection() as? RangeSelection)?.insertText("ABC")
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertText("XYZ")
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_AlternatingTypeDelete() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Start")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 5, focusOffset: 5)
      }
      for _ in 0..<3 {
        try ed.update {
          try (getSelection() as? RangeSelection)?.insertText("X")
        }
        try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Rapid Selection Changes

  func testParity_RapidSelectionChange_TypeEach() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Start")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 5, focusOffset: 5)
      }
      // Insert characters at different positions
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertText("A")
      }
      try ed.update {
        guard let root = getRoot(), let p = root.getChildren().first as? ElementNode,
              let t = p.getChildren().first as? TextNode else { return }
        try t.select(anchorOffset: 3, focusOffset: 3)
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertText("B")
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Rapid Formatting Changes

  func testParity_RapidFormat_ToggleBold() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Text")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 0, focusOffset: 4)
      }
      for _ in 0..<5 {
        try ed.update {
          try (getSelection() as? RangeSelection)?.formatText(formatType: .bold)
        }
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_RapidFormat_MultipleAttributes() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Test")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 0, focusOffset: 4)
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
      try ed.update {
        try (getSelection() as? RangeSelection)?.formatText(formatType: .bold)
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Rapid Paragraph Operations

  func testParity_RapidParagraphSplit() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Line")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 4, focusOffset: 4)
      }
      for _ in 0..<3 {
        try ed.update {
          try (getSelection() as? RangeSelection)?.insertParagraph()
          try (getSelection() as? RangeSelection)?.insertText("Next")
        }
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_RapidLineBreak() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Start")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 5, focusOffset: 5)
      }
      for i in 1...3 {
        try ed.update {
          try (getSelection() as? RangeSelection)?.insertLineBreak(selectStart: false)
          try (getSelection() as? RangeSelection)?.insertText("Line\(i)")
        }
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Rapid Mixed Operations

  func testParity_RapidMixed_TypeFormatDelete() throws {
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
        try (getSelection() as? RangeSelection)?.insertText("ABC")
      }
      try ed.update {
        guard let root = getRoot(), let p = root.getChildren().first as? ElementNode,
              let t = p.getChildren().first as? TextNode else { return }
        try t.select(anchorOffset: 0, focusOffset: 3)
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.formatText(formatType: .bold)
      }
      try ed.update {
        guard let root = getRoot(), let p = root.getChildren().first as? ElementNode,
              let t = p.getChildren().first as? TextNode else { return }
        try t.select(anchorOffset: 3, focusOffset: 3)
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_RapidMixed_Complex() throws {
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
        try (getSelection() as? RangeSelection)?.insertText(" A")
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertText("B")
      }
      try ed.update {
        guard let root = getRoot(), let p = root.getChildren().first as? ElementNode,
              let t = p.getChildren().first as? TextNode else { return }
        try t.select(anchorOffset: 6, focusOffset: 7)
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.formatText(formatType: .italic)
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Stress Tests

  func testParity_StressTest_ManyCharacters() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 0, focusOffset: 0)
      }
      // Type 50 characters
      for i in 0..<50 {
        try ed.update {
          try (getSelection() as? RangeSelection)?.insertText(String(i % 10))
        }
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_StressTest_ManyOperations() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Test")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 4, focusOffset: 4)
      }
      // 30 rapid operations
      for _ in 0..<10 {
        try ed.update {
          try (getSelection() as? RangeSelection)?.insertText("X")
        }
        try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
        try ed.update {
          try (getSelection() as? RangeSelection)?.insertText("!")
        }
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Edge Cases

  func testParity_RapidInsert_EmptyStrings() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Text")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 4, focusOffset: 4)
      }
      for _ in 0..<5 {
        try ed.update {
          try (getSelection() as? RangeSelection)?.insertText("")
        }
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_RapidDelete_AtBoundary() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "AB")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 0, focusOffset: 0)
      }
      // Try to delete before start (should be no-op)
      for _ in 0..<3 {
        try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }
}
