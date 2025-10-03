@testable import Lexical
import XCTest

@MainActor
final class BidiEdgeCaseParityTests: XCTestCase {

  private func makeViews() -> (opt: LexicalView, leg: LexicalView) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let opt = LexicalView(editorConfig: cfg, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let leg = LexicalView(editorConfig: cfg, featureFlags: FeatureFlags())
    opt.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
    leg.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
    return (opt, leg)
  }

  // MARK: - LTR/RTL Boundary

  func testParity_Bidi_EnglishArabic_Boundary_Backspace() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        // English then Arabic: "Hello مرحبا"
        let p = createParagraphNode(); let t = createTextNode(text: "Hello مرحبا")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 6, focusOffset: 6) // at boundary (after "Hello ")
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_Bidi_ArabicEnglish_Boundary_ForwardDelete() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        // Arabic then English: "مرحبا Hello"
        let p = createParagraphNode(); let t = createTextNode(text: "مرحبا Hello")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 6, focusOffset: 6) // at boundary (after "مرحبا ")
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: false) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_Bidi_InsertAtBoundary_English() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Hello مرحبا")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 5, focusOffset: 5) // after "Hello" before space
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertText("!")
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_Bidi_InsertAtBoundary_Arabic() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "مرحبا Hello")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 5, focusOffset: 5) // after "مرحبا" before space
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertText("!")
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Embedded RTL in LTR

  func testParity_Bidi_EmbeddedRTL_Backspace() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        // "I say مرحبا here"
        let p = createParagraphNode(); let t = createTextNode(text: "I say مرحبا here")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 11, focusOffset: 11) // after "مرحبا"
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_Bidi_EmbeddedRTL_RangeDelete() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "I say مرحبا here")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 4, focusOffset: 13) // select " say مرحبا h"
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Embedded LTR in RTL

  func testParity_Bidi_EmbeddedLTR_Backspace() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        // Arabic with embedded English: "أنا أقول Hello هنا"
        let p = createParagraphNode(); let t = createTextNode(text: "أنا أقول Hello هنا")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 14, focusOffset: 14) // after "Hello"
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_Bidi_EmbeddedLTR_InsertAfter() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "مرحبا Hello مرة")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 11, focusOffset: 11) // after "Hello"
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertText(" World")
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Multiple Direction Changes

  func testParity_Bidi_MultipleSwitches_Backspace() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        // "Hello مرحبا World العالم"
        let p = createParagraphNode(); let t = createTextNode(text: "Hello مرحبا World العالم")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 17, focusOffset: 17) // middle of second switch
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_Bidi_MultipleSwitches_RangeDelete() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "A ب C د E")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 2, focusOffset: 7) // select "ب C د"
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Punctuation in Bidi

  func testParity_Bidi_Punctuation_Neutral() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        // Punctuation between LTR and RTL: "Hello, مرحبا!"
        let p = createParagraphNode(); let t = createTextNode(text: "Hello, مرحبا!")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 6, focusOffset: 6) // after comma
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_Bidi_Punctuation_AtEnd() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "مرحبا!")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 6, focusOffset: 6) // after "!"
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Numbers in Bidi

  func testParity_Bidi_Numbers_InArabic() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        // Arabic with numbers: "العدد 123 هنا"
        let p = createParagraphNode(); let t = createTextNode(text: "العدد 123 هنا")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 9, focusOffset: 9) // after "123"
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_Bidi_Numbers_BetweenBidi() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        // "Hello 123 مرحبا"
        let p = createParagraphNode(); let t = createTextNode(text: "Hello 123 مرحبا")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 7, focusOffset: 7) // middle of numbers
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Hebrew (RTL)

  func testParity_Bidi_Hebrew_Backspace() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        // Hebrew: "שלום" (shalom)
        let p = createParagraphNode(); let t = createTextNode(text: "שלום")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 4, focusOffset: 4) // after all
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_Bidi_HebrewEnglish_Mix() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        // "Hello שלום"
        let p = createParagraphNode(); let t = createTextNode(text: "Hello שלום")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 6, focusOffset: 6) // at boundary
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: false) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Bidi with Formatting

  func testParity_Bidi_Bold_AcrossBoundary() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Hello مرحبا")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 3, focusOffset: 9) // select "lo مرح"
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.formatText(formatType: .bold)
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_Bidi_Italic_RTLOnly() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Hello مرحبا World")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 6, focusOffset: 11) // select "مرحبا"
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.formatText(formatType: .italic)
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Bidi with Line Breaks

  func testParity_Bidi_LineBreak_InRTL() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "مرحبا")
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

  func testParity_Bidi_ParagraphBreak_AtBoundary() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Hello مرحبا")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 6, focusOffset: 6) // at boundary
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertParagraph()
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Bidi Control Characters

  func testParity_Bidi_LRM_Mark() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        // Text with left-to-right mark: "Hello\u{200E}مرحبا"
        let p = createParagraphNode(); let t = createTextNode(text: "Hello\u{200E}مرحبا")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 6, focusOffset: 6) // after LRM
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_Bidi_RLM_Mark() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        // Text with right-to-left mark: "مرحبا\u{200F}Hello"
        let p = createParagraphNode(); let t = createTextNode(text: "مرحبا\u{200F}Hello")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 6, focusOffset: 6) // after RLM
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_Bidi_ALM_Mark() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        // Text with Arabic letter mark: "مرحبا\u{061C}!"
        let p = createParagraphNode(); let t = createTextNode(text: "مرحبا\u{061C}!")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 6, focusOffset: 6) // after ALM
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Complex Scenarios

  func testParity_Bidi_TripleEmbedding() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        // "A ب C د E ف G"
        let p = createParagraphNode(); let t = createTextNode(text: "A ب C د E ف G")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 4, focusOffset: 10) // select "C د E ف"
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_Bidi_MixedScripts_WithNumbers() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        // "Hello 123 مرحبا שלום 456 World"
        let p = createParagraphNode(); let t = createTextNode(text: "Hello 123 مرحبا שלום 456 World")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 0, focusOffset: 29)
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.formatText(formatType: .bold)
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }
}
