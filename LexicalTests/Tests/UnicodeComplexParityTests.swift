@testable import Lexical
import XCTest

@MainActor
final class UnicodeComplexParityTests: XCTestCase {

  private func makeViews() -> (opt: LexicalView, leg: LexicalView) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let opt = LexicalView(editorConfig: cfg, featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor))
    let leg = LexicalView(editorConfig: cfg, featureFlags: FeatureFlags())
    opt.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
    leg.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
    return (opt, leg)
  }

  // MARK: - Zero-Width Joiner (ZWJ) Sequences

  func testParity_ZWJ_FamilyEmoji_BackspaceDeletesCluster() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        // Family emoji: 👨‍👩‍👧‍👦 (man-woman-girl-boy with ZWJ)
        let p = createParagraphNode(); let t = createTextNode(text: "Family: 👨‍👩‍👧‍👦!")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 9, focusOffset: 9) // after family emoji
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_ZWJ_CoupleKissEmoji_ForwardDelete() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        // Kiss: woman-kiss-woman 👩‍❤️‍💋‍👩
        let p = createParagraphNode(); let t = createTextNode(text: "👩‍❤️‍💋‍👩x")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 0, focusOffset: 0) // before emoji
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: false) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_ZWJ_ProfessionEmoji_InsertText() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode(); let t = createTextNode(text: "Job: ")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 5, focusOffset: 5)
      }
      // Woman technologist: 👩‍💻
      try ed.update {
        try (getSelection() as? RangeSelection)?.insertText("👩‍💻")
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_ZWJ_FlagSequence_BackspaceDeletesFlag() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        // Regional indicator: 🇺🇸 (US flag)
        let p = createParagraphNode(); let t = createTextNode(text: "USA: 🇺🇸!")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 7, focusOffset: 7) // after flag
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Combining Characters

  func testParity_CombiningDiacritics_Accents_Backspace() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        // "café" with combining acute accent: cafe\u{301}
        let p = createParagraphNode(); let t = createTextNode(text: "cafe\u{301}")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 4, focusOffset: 4) // after "café"
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_CombiningDiacritics_MultipleMarks() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        // "a" with combining acute and tilde: a\u{301}\u{303}
        let p = createParagraphNode(); let t = createTextNode(text: "a\u{301}\u{303}bc")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 3, focusOffset: 3) // after combined char
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_CombiningDiacritics_Zalgo_Text() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        // Zalgo-like text with multiple combining marks
        let p = createParagraphNode(); let t = createTextNode(text: "H\u{036F}\u{0334}\u{0346}i")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 4, focusOffset: 4) // after "H" with marks
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // FIXME: Keycap emoji grapheme cluster handling differs between reconcilers.
  // Foundation's rangeOfComposedCharacterSequence incorrectly handles keycap boundaries.
  // Requires custom Unicode grapheme cluster boundary detection beyond Foundation APIs.
  func testParity_CombiningEnclosingKeycap_NumberEmoji() throws {
    // throw XCTSkip("Known issue: keycap emoji grapheme cluster boundary detection")
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        // Keycap digit: 1️⃣ (1 + variation selector + combining keycap)
        let p = createParagraphNode(); let t = createTextNode(text: "Count: 1️⃣2️⃣3️⃣")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 9, focusOffset: 9) // after first keycap
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Variation Selectors

  func testParity_VariationSelector_EmojiPresentation() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        // ❤️ (heavy black heart with emoji presentation selector)
        let p = createParagraphNode(); let t = createTextNode(text: "Love: ❤️!")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 8, focusOffset: 8) // after heart
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_VariationSelector_TextPresentation() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        // ☺︎ (white smiling face with text presentation selector)
        let p = createParagraphNode(); let t = createTextNode(text: "Smile: ☺︎")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 9, focusOffset: 9) // after smile
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Surrogate Pairs

  func testParity_SurrogatePairs_BasicEmoji_Backspace() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        // 𝕳𝖊𝖑𝖑𝖔 (Mathematical bold fraktur, requires surrogate pairs)
        let p = createParagraphNode(); let t = createTextNode(text: "𝕳𝖊𝖑𝖑𝖔")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 5, focusOffset: 5) // after all chars
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_SurrogatePairs_MathematicalSymbols() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        // 𝐀𝐁𝐂 (Mathematical bold capital)
        let p = createParagraphNode(); let t = createTextNode(text: "𝐀𝐁𝐂")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 2, focusOffset: 2) // after 𝐁
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_SurrogatePairs_RareHanzi() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        // 𠮷 (rare CJK character in supplementary plane)
        let p = createParagraphNode(); let t = createTextNode(text: "Rare: 𠮷")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 7, focusOffset: 7) // after rare char
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Indic Scripts (Devanagari)

  func testParity_Devanagari_ConjunctConsonants() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        // Hindi: "नमस्ते" (namaste) with conjunct
        let p = createParagraphNode(); let t = createTextNode(text: "नमस्ते")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 6, focusOffset: 6) // after all
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_Devanagari_VowelMatras() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        // "हिंदी" (Hindi) with vowel signs
        let p = createParagraphNode(); let t = createTextNode(text: "हिंदी")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 3, focusOffset: 3) // middle
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Arabic Ligatures

  func testParity_Arabic_Ligatures_LAM_ALEF() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        // Arabic: "لا" (lam-alef ligature)
        let p = createParagraphNode(); let t = createTextNode(text: "لا")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 2, focusOffset: 2) // after ligature
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_Arabic_Diacritics_Tashkeel() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        // "مَرْحَباً" (marhaban - hello with tashkeel)
        let p = createParagraphNode(); let t = createTextNode(text: "مَرْحَباً")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 8, focusOffset: 8) // after all
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Thai Script

  func testParity_Thai_VowelsAboveBelow() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        // Thai: "สวัสดี" (sawasdee - hello)
        let p = createParagraphNode(); let t = createTextNode(text: "สวัสดี")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 6, focusOffset: 6) // after all
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Mixed Complex Unicode

  func testParity_MixedComplex_EmojiCombiningZWJ() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        // Mix: regular, emoji, ZWJ, combining
        let p = createParagraphNode(); let t = createTextNode(text: "a👨‍👩‍👧b\u{301}c")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 9, focusOffset: 9) // after "b" with combining
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_MixedComplex_AllScripts() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        // Latin, Arabic, Devanagari, CJK, emoji
        let p = createParagraphNode(); let t = createTextNode(text: "Hello مرحبا नमस्ते 你好 👋")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 0, focusOffset: 28)
      }
      try ed.update {
        try (getSelection() as? RangeSelection)?.formatText(formatType: .bold)
      }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  // MARK: - Edge Cases

  func testParity_EmptyGraphemeCluster_ZeroWidthJoiner() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        // Text with standalone ZWJ (edge case)
        let p = createParagraphNode(); let t = createTextNode(text: "a\u{200D}b")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 2, focusOffset: 2) // after ZWJ
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_BidirectionalOverride_Marks() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        // Text with bidi override: LRO + text + PDF
        let p = createParagraphNode(); let t = createTextNode(text: "\u{202E}test\u{202C}")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 6, focusOffset: 6) // after all
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }

  func testParity_NonCharacters_ReplacementChar() throws {
    let (opt, leg) = makeViews()
    func run(_ v: LexicalView) throws -> String {
      let ed = v.editor
      try ed.update {
        guard let root = getRoot() else { return }
        // Replacement character: �
        let p = createParagraphNode(); let t = createTextNode(text: "Bad: �")
        try p.append([t]); try root.append([p])
        try t.select(anchorOffset: 6, focusOffset: 6) // after replacement char
      }
      try ed.update { try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true) }
      return v.attributedText.string
    }
    XCTAssertEqual(try run(opt), try run(leg))
  }
}
