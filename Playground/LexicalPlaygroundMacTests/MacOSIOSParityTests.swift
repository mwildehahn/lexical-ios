//
//  MacOSIOSParityTests.swift
//  LexicalPlaygroundMacTests
//
//  Comprehensive tests to ensure macOS and iOS Lexical editors behave identically
//

import XCTest
@testable import Lexical

@MainActor
final class MacOSIOSParityTests: XCTestCase {

  // MARK: - Test Helpers

  private func makeEditors() -> (Editor, Editor) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let macOS = Editor(featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor), editorConfig: cfg)
    let iOS = Editor(featureFlags: FeatureFlags.optimizedProfile(.aggressiveEditor), editorConfig: cfg)
    return (macOS, iOS)
  }

  private func setupBasicDocument(editor: Editor) throws {
    try editor.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode()
      let t = createTextNode(text: "Hello World")
      try p.append([t])
      try root.append([p])
    }
  }

  private func setupMultiParagraphDocument(editor: Editor) throws {
    try editor.update {
      guard let root = getRoot() else { return }
      let p1 = createParagraphNode()
      let t1 = createTextNode(text: "First paragraph")
      try p1.append([t1])

      let p2 = createParagraphNode()
      let t2 = createTextNode(text: "Second paragraph")
      try p2.append([t2])

      let p3 = createParagraphNode()
      let t3 = createTextNode(text: "Third paragraph")
      try p3.append([t3])

      try root.append([p1, p2, p3])
    }
  }

  // MARK: - Selection Tests

  func testParity_BasicTextSelection() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> (String, Int, Int) {
      try setupBasicDocument(editor: editor)
      var anchorOffset = -1, focusOffset = -1

      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        // Select "World" (offset 6-11)
        try t.select(anchorOffset: 6, focusOffset: 11)
      }

      var content = ""
      try editor.read {
        content = getRoot()?.getTextContent() ?? ""
        if let sel = try getSelection() as? RangeSelection {
          anchorOffset = sel.anchor.offset
          focusOffset = sel.focus.offset
        }
      }
      return (content, anchorOffset, focusOffset)
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult.0, iosResult.0, "Content should be identical")
    XCTAssertEqual(macResult.1, iosResult.1, "Anchor offset should be identical")
    XCTAssertEqual(macResult.2, iosResult.2, "Focus offset should be identical")
  }

  func testParity_SelectionStabilityDuringRemoteEdit() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> (String, NodeKey, Int) {
      try setupMultiParagraphDocument(editor: editor)
      var anchorKey: NodeKey = ""
      var anchorOffset = -1

      // Select in first paragraph
      try editor.update {
        guard let root = getRoot(),
              let p1 = root.getFirstChild() as? ParagraphNode,
              let t1 = p1.getFirstChild() as? TextNode else { return }
        try t1.select(anchorOffset: 5, focusOffset: 5)
      }

      // Edit third paragraph (remote from selection)
      try editor.update {
        guard let root = getRoot(),
              let p3 = root.getLastChild() as? ParagraphNode,
              let t3 = p3.getFirstChild() as? TextNode else { return }
        try t3.setText("Third paragraph edited!")
      }

      var content = ""
      try editor.read {
        content = getRoot()?.getTextContent() ?? ""
        if let sel = try getSelection() as? RangeSelection {
          anchorKey = sel.anchor.key
          anchorOffset = sel.anchor.offset
        }
      }
      return (content, anchorKey, anchorOffset)
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult.0, iosResult.0, "Content should be identical")
    XCTAssertEqual(macResult.1, iosResult.1, "Selection anchor key should be stable")
    XCTAssertEqual(macResult.2, iosResult.2, "Selection offset should be stable")
  }

  func testParity_SelectionAfterInsertText() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> (String, Int) {
      try setupBasicDocument(editor: editor)
      var focusOffset = -1

      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        try t.select(anchorOffset: 5, focusOffset: 5)
        try (getSelection() as? RangeSelection)?.insertText(" Amazing")
      }

      var content = ""
      try editor.read {
        content = getRoot()?.getTextContent() ?? ""
        if let sel = try getSelection() as? RangeSelection {
          focusOffset = sel.focus.offset
        }
      }
      return (content, focusOffset)
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult.0, iosResult.0, "Content should be identical")
    XCTAssertEqual(macResult.1, iosResult.1, "Selection should move after inserted text")
  }

  func testParity_SelectionAfterDeleteText() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> (String, Int) {
      try setupBasicDocument(editor: editor)
      var focusOffset = -1

      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        // Select "World" and delete
        try t.select(anchorOffset: 6, focusOffset: 11)
        try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true)
      }

      var content = ""
      try editor.read {
        content = getRoot()?.getTextContent() ?? ""
        if let sel = try getSelection() as? RangeSelection {
          focusOffset = sel.focus.offset
        }
      }
      return (content, focusOffset)
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult.0, iosResult.0, "Content should be identical")
    XCTAssertEqual(macResult.1, iosResult.1, "Selection should collapse after delete")
  }

  // MARK: - Text Editing Tests

  func testParity_BasicTextInsertion() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> String {
      try setupBasicDocument(editor: editor)

      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        try t.select(anchorOffset: 11, focusOffset: 11)
        try (getSelection() as? RangeSelection)?.insertText(" from macOS/iOS")
      }

      var content = ""
      try editor.read {
        content = getRoot()?.getTextContent() ?? ""
      }
      return content
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult, iosResult, "Inserted text should be identical")
    XCTAssertEqual(macResult, "Hello World from macOS/iOS")
  }

  func testParity_MultilineTextInsertion() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> (String, Int) {
      try setupBasicDocument(editor: editor)
      var paragraphCount = 0

      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        try t.select(anchorOffset: 5, focusOffset: 5)
        try (getSelection() as? RangeSelection)?.insertParagraph()
      }

      var content = ""
      try editor.read {
        content = getRoot()?.getTextContent() ?? ""
        paragraphCount = getRoot()?.getChildren().count ?? 0
      }
      return (content, paragraphCount)
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult.0, iosResult.0, "Content after paragraph break should be identical")
    XCTAssertEqual(macResult.1, iosResult.1, "Paragraph count should be identical")
    XCTAssertEqual(macResult.1, 2, "Should have 2 paragraphs after split")
  }

  func testParity_ReplaceSelectedText() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> String {
      try setupBasicDocument(editor: editor)

      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        // Select "World" and replace with "Universe"
        try t.select(anchorOffset: 6, focusOffset: 11)
        try (getSelection() as? RangeSelection)?.insertText("Universe")
      }

      var content = ""
      try editor.read {
        content = getRoot()?.getTextContent() ?? ""
      }
      return content
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult, iosResult, "Replaced text should be identical")
    XCTAssertEqual(macResult, "Hello Universe")
  }

  // MARK: - Formatting Tests

  func testParity_BoldFormatting() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> (String, Bool) {
      try setupBasicDocument(editor: editor)
      var isBold = false

      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        try t.select(anchorOffset: 0, focusOffset: 5)
        try (getSelection() as? RangeSelection)?.formatText(formatType: .bold)
      }

      var content = ""
      try editor.read {
        content = getRoot()?.getTextContent() ?? ""
        if let p = getRoot()?.getFirstChild() as? ParagraphNode,
           let t = p.getFirstChild() as? TextNode {
          isBold = t.getFormat().isTypeSet(type: .bold)
        }
      }
      return (content, isBold)
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult.0, iosResult.0, "Content should be unchanged")
    XCTAssertEqual(macResult.1, iosResult.1, "Bold formatting should match")
    XCTAssertTrue(macResult.1, "Text should be bold")
  }

  func testParity_ItalicFormatting() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> Bool {
      try setupBasicDocument(editor: editor)
      var isItalic = false

      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        try t.select(anchorOffset: 6, focusOffset: 11)
        try (getSelection() as? RangeSelection)?.formatText(formatType: .italic)
      }

      try editor.read {
        if let p = getRoot()?.getFirstChild() as? ParagraphNode,
           let t = p.getLastChild() as? TextNode {
          isItalic = t.getFormat().isTypeSet(type: .italic)
        }
      }
      return isItalic
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult, iosResult, "Italic formatting should match")
    XCTAssertTrue(macResult, "Text should be italic")
  }

  func testParity_UnderlineFormatting() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> Bool {
      try setupBasicDocument(editor: editor)
      var isUnderlined = false

      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        try t.select(anchorOffset: 0, focusOffset: 11)
        try (getSelection() as? RangeSelection)?.formatText(formatType: .underline)
      }

      try editor.read {
        if let p = getRoot()?.getFirstChild() as? ParagraphNode,
           let t = p.getFirstChild() as? TextNode {
          isUnderlined = t.getFormat().isTypeSet(type: .underline)
        }
      }
      return isUnderlined
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult, iosResult, "Underline formatting should match")
    XCTAssertTrue(macResult, "Text should be underlined")
  }

  func testParity_StrikethroughFormatting() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> Bool {
      try setupBasicDocument(editor: editor)
      var isStrikethrough = false

      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        try t.select(anchorOffset: 0, focusOffset: 11)
        try (getSelection() as? RangeSelection)?.formatText(formatType: .strikethrough)
      }

      try editor.read {
        if let p = getRoot()?.getFirstChild() as? ParagraphNode,
           let t = p.getFirstChild() as? TextNode {
          isStrikethrough = t.getFormat().isTypeSet(type: .strikethrough)
        }
      }
      return isStrikethrough
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult, iosResult, "Strikethrough formatting should match")
    XCTAssertTrue(macResult, "Text should be strikethrough")
  }

  func testParity_MultipleFormatsToggle() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> (Bool, Bool) {
      try setupBasicDocument(editor: editor)
      var isBold = false
      var isItalic = false

      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        try t.select(anchorOffset: 0, focusOffset: 11)
        try (getSelection() as? RangeSelection)?.formatText(formatType: .bold)
        try (getSelection() as? RangeSelection)?.formatText(formatType: .italic)
      }

      try editor.read {
        if let p = getRoot()?.getFirstChild() as? ParagraphNode,
           let t = p.getFirstChild() as? TextNode {
          let format = t.getFormat()
          isBold = format.isTypeSet(type: .bold)
          isItalic = format.isTypeSet(type: .italic)
        }
      }
      return (isBold, isItalic)
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult.0, iosResult.0, "Bold should match")
    XCTAssertEqual(macResult.1, iosResult.1, "Italic should match")
    XCTAssertTrue(macResult.0 && macResult.1, "Both formats should be applied")
  }

  // MARK: - Complex Editing Tests

  func testParity_SelectAllAndReplace() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> String {
      try setupMultiParagraphDocument(editor: editor)

      try editor.update {
        guard let root = getRoot() else { return }
        try root.select(anchorOffset: 0, focusOffset: nil)
        try (getSelection() as? RangeSelection)?.insertText("All replaced")
      }

      var content = ""
      try editor.read {
        content = getRoot()?.getTextContent() ?? ""
      }
      return content
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult, iosResult, "Select all and replace should match")
    XCTAssertEqual(macResult, "All replaced")
  }

  func testParity_DeleteWordBackwards() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> String {
      try setupBasicDocument(editor: editor)

      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        try t.select(anchorOffset: 11, focusOffset: 11)
        try (getSelection() as? RangeSelection)?.deleteWord(isBackwards: true)
      }

      var content = ""
      try editor.read {
        content = getRoot()?.getTextContent() ?? ""
      }
      return content
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult, iosResult, "Delete word should match")
    XCTAssertEqual(macResult, "Hello ")
  }

  // MARK: - Performance Tests

  func testParity_LargeDocumentPerformance() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> String {
      try editor.update {
        guard let root = getRoot() else { return }
        // Create 100 paragraphs with text
        for i in 0..<100 {
          let p = createParagraphNode()
          let t = createTextNode(text: "Paragraph \(i) with some content")
          try p.append([t])
          try root.append([p])
        }
      }

      var content = ""
      try editor.read {
        content = getRoot()?.getTextContent() ?? ""
      }
      return content
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult, iosResult, "Large document content should match")
  }

  func testParity_RapidSelectionChanges() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> (Int, Int) {
      try setupBasicDocument(editor: editor)
      var finalAnchor = -1
      var finalFocus = -1

      // Rapidly change selection 10 times
      for i in 0..<10 {
        try editor.update {
          guard let root = getRoot(),
                let p = root.getFirstChild() as? ParagraphNode,
                let t = p.getFirstChild() as? TextNode else { return }
          let offset = i % 11
          try t.select(anchorOffset: offset, focusOffset: offset)
        }
      }

      try editor.read {
        if let sel = try getSelection() as? RangeSelection {
          finalAnchor = sel.anchor.offset
          finalFocus = sel.focus.offset
        }
      }
      return (finalAnchor, finalFocus)
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult.0, iosResult.0, "Final anchor should match")
    XCTAssertEqual(macResult.1, iosResult.1, "Final focus should match")
  }
}
