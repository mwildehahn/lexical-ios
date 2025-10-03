@testable import Lexical
import XCTest

@MainActor
final class CJKCompositionParityTests: XCTestCase {

  private func makeViews() -> (opt: LexicalView, leg: LexicalView) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let opt = LexicalView(editorConfig: cfg, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let leg = LexicalView(editorConfig: cfg, featureFlags: FeatureFlags())
    opt.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
    leg.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
    return (opt, leg)
  }

  // MARK: - Japanese Hiragana

  func testParity_JapaneseHiragana_Composition_Basic() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Hello ")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 6, focusOffset: 6)
      }
      // Simulate IME: "konnichiwa" -> "こんにちは"
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertText("こんにちは")
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_JapaneseHiragana_Backspace_AfterComposition() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "こんにちは")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 5, focusOffset: 5) // after all 5 hiragana
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_JapaneseHiragana_ReplaceSelection_WithComposition() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Hello World")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 6, focusOffset: 11) // select "World"
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertText("世界")
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Japanese Kanji

  func testParity_JapaneseKanji_Composition_Basic() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 0, focusOffset: 0)
      }
      // Simulate IME: "nihongo" -> "日本語"
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertText("日本語")
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_JapaneseKanji_MixedWithEnglish() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "I speak ")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 8, focusOffset: 8)
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertText("日本語")
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertText(" fluently")
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Chinese Simplified

  func testParity_ChineseSimplified_Pinyin_Basic() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 0, focusOffset: 0)
      }
      // Simulate IME: "nihao" -> "你好"
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertText("你好")
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_ChineseSimplified_LongSentence() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 0, focusOffset: 0)
      }
      // "I am learning Chinese"
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertText("我在学习中文")
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_ChineseSimplified_BackspaceInMiddle() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "你好世界")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 2, focusOffset: 2) // after "你好"
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Chinese Traditional

  func testParity_ChineseTraditional_Basic() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 0, focusOffset: 0)
      }
      // Traditional: "你好世界"
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertText("你好世界")
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Korean Hangul

  func testParity_KoreanHangul_Composition_Basic() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 0, focusOffset: 0)
      }
      // "annyeonghaseyo" -> "안녕하세요"
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertText("안녕하세요")
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_KoreanHangul_Jamo_Composition() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Test: ")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 6, focusOffset: 6)
      }
      // Korean with jamo composition: "한글"
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertText("한글")
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_KoreanHangul_BackspaceDecomposition() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "한글")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 2, focusOffset: 2) // after both syllables
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Mixed CJK

  func testParity_MixedCJK_JapaneseChineseKorean() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 0, focusOffset: 0)
      }
      // Mix Japanese, Chinese, Korean
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertText("こんにちは") // Japanese
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertText("你好") // Chinese
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertText("안녕") // Korean
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_MixedCJK_WithPunctuation() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 0, focusOffset: 0)
      }
      // CJK with ideographic punctuation
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertText("こんにちは、世界！")
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Composition + Formatting

  func testParity_CJK_BoldFormatting() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "こんにちは")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 0, focusOffset: 5)
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.formatText(formatType: .bold)
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_CJK_InsertAfterBold() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Hello")
        var fmt = TextFormat(); fmt.bold = true
        _ = try t.setFormat(format: fmt)
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 5, focusOffset: 5)
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertText("世界")
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Composition + Line Breaks

  func testParity_CJK_InsertLineBreak() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "こんにちは")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 3, focusOffset: 3) // middle
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertLineBreak(selectStart: false)
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_CJK_InsertParagraphBreak() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "你好世界")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 2, focusOffset: 2) // after "你好"
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertParagraph()
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Edge Cases

  func testParity_CJK_EmptyComposition_Cancel() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Test")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 4, focusOffset: 4)
      }
      // Insert and immediately delete (simulates cancelled composition)
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertText("")
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_CJK_RapidInsertDelete() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 0, focusOffset: 0)
      }
      // Rapid insert
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertText("こ")
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertText("ん")
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertText("に")
      }
      // Rapid delete
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }
}
