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
    // Use legacy reconciler for tests - no TextView/TextStorage attached
    let macOS = Editor(featureFlags: FeatureFlags(), editorConfig: cfg)
    let iOS = Editor(featureFlags: FeatureFlags(), editorConfig: cfg)
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

  // MARK: - Multi-Paragraph Tests

  func testParity_MultipleParagraphs() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> String {
      try editor.update {
        guard let root = getRoot() else { return }
        for i in 1...3 {
          let p = createParagraphNode()
          let t = createTextNode(text: "Paragraph \(i)")
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

    XCTAssertEqual(macResult, iosResult, "Multi-paragraph content should match")
  }

  func testParity_ParagraphNavigation() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> (Int, Int) {
      try setupMultiParagraphDocument(editor: editor)
      var anchor = -1, focus = -1

      try editor.update {
        guard let root = getRoot(),
              let lastParagraph = root.getLastChild() as? ParagraphNode,
              let lastText = lastParagraph.getFirstChild() as? TextNode else { return }
        try lastText.select(anchorOffset: 0, focusOffset: 5)
      }

      try editor.read {
        if let sel = try getSelection() as? RangeSelection {
          anchor = sel.anchor.offset
          focus = sel.focus.offset
        }
      }
      return (anchor, focus)
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult.0, iosResult.0, "Paragraph navigation anchor should match")
    XCTAssertEqual(macResult.1, iosResult.1, "Paragraph navigation focus should match")
  }

  // MARK: - Line Break Tests

  func testParity_LineBreakInsertion() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> String {
      try setupBasicDocument(editor: editor)

      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        try t.select(anchorOffset: 5, focusOffset: 5)
        try (getSelection() as? RangeSelection)?.insertLineBreak(selectStart: false)
      }

      var content = ""
      try editor.read {
        content = getRoot()?.getTextContent() ?? ""
      }
      return content
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult, iosResult, "Line break insertion should match")
  }

  // MARK: - Nested Formatting Tests

  func testParity_NestedFormatting() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> (Bool, Bool) {
      try setupBasicDocument(editor: editor)
      var isBold = false
      var isItalic = false

      // Apply bold
      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        try t.select(anchorOffset: 0, focusOffset: 5)
        try (getSelection() as? RangeSelection)?.formatText(formatType: .bold)
      }

      // Apply italic to same range
      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        try t.select(anchorOffset: 0, focusOffset: 5)
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

    XCTAssertEqual(macResult.0, iosResult.0, "Nested bold formatting should match")
    XCTAssertEqual(macResult.1, iosResult.1, "Nested italic formatting should match")
    XCTAssertTrue(macResult.0 && macResult.1, "Both formats should be applied")
  }

  func testParity_FormatToggle() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> Bool {
      try setupBasicDocument(editor: editor)

      // Apply bold
      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        try t.select(anchorOffset: 0, focusOffset: 5)
        try (getSelection() as? RangeSelection)?.formatText(formatType: .bold)
      }

      // Remove bold (toggle off)
      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        try t.select(anchorOffset: 0, focusOffset: 5)
        try (getSelection() as? RangeSelection)?.formatText(formatType: .bold)
      }

      var isBold = true
      try editor.read {
        if let p = getRoot()?.getFirstChild() as? ParagraphNode,
           let t = p.getFirstChild() as? TextNode {
          isBold = t.getFormat().isTypeSet(type: .bold)
        }
      }
      return isBold
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult, iosResult, "Format toggle should match")
    XCTAssertFalse(macResult, "Bold should be toggled off")
  }

  // MARK: - Edge Case Tests

  func testParity_EmptyParagraph() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> Int {
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        try root.append([p])
      }

      var childCount = 0
      try editor.read {
        childCount = getRoot()?.getChildrenSize() ?? 0
      }
      return childCount
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult, iosResult, "Empty paragraph handling should match")
  }

  func testParity_BoundarySelection() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> (Int, Int) {
      try setupBasicDocument(editor: editor)
      var anchor = -1, focus = -1

      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        let textLength = t.getTextContentSize()
        try t.select(anchorOffset: textLength, focusOffset: textLength)
      }

      try editor.read {
        if let sel = try getSelection() as? RangeSelection {
          anchor = sel.anchor.offset
          focus = sel.focus.offset
        }
      }
      return (anchor, focus)
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult.0, iosResult.0, "Boundary selection anchor should match")
    XCTAssertEqual(macResult.1, iosResult.1, "Boundary selection focus should match")
  }

  func testParity_ZeroLengthSelection() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> Bool {
      try setupBasicDocument(editor: editor)
      var isCollapsed = false

      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        try t.select(anchorOffset: 5, focusOffset: 5)
      }

      try editor.read {
        if let sel = try getSelection() as? RangeSelection {
          isCollapsed = sel.isCollapsed()
        }
      }
      return isCollapsed
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult, iosResult, "Zero-length selection should match")
    XCTAssertTrue(macResult, "Selection should be collapsed")
  }

  // MARK: - Mixed Content Tests

  func testParity_MixedFormattedText() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> String {
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()

        // Create text with different formats
        let t1 = createTextNode(text: "Normal ")
        let t2 = createTextNode(text: "Bold ")
        var boldFormat = TextFormat()
        boldFormat.bold = true
        try t2.setFormat(format: boldFormat)
        let t3 = createTextNode(text: "Italic")
        var italicFormat = TextFormat()
        italicFormat.italic = true
        try t3.setFormat(format: italicFormat)

        try p.append([t1, t2, t3])
        try root.append([p])
      }

      var content = ""
      try editor.read {
        content = getRoot()?.getTextContent() ?? ""
      }
      return content
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult, iosResult, "Mixed formatted text content should match")
    XCTAssertEqual(macResult, "Normal Bold Italic")
  }

  func testParity_SelectionAcrossFormats() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> (Int, Int) {
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()

        let t1 = createTextNode(text: "Hello ")
        let t2 = createTextNode(text: "World")
        var boldFormat = TextFormat()
        boldFormat.bold = true
        try t2.setFormat(format: boldFormat)

        try p.append([t1, t2])
        try root.append([p])
      }

      var anchor = -1, focus = -1
      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t1 = p.getFirstChild() as? TextNode else { return }
        try t1.select(anchorOffset: 3, focusOffset: 6)
      }

      try editor.read {
        if let sel = try getSelection() as? RangeSelection {
          anchor = sel.anchor.offset
          focus = sel.focus.offset
        }
      }
      return (anchor, focus)
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult.0, iosResult.0, "Selection across formats anchor should match")
    XCTAssertEqual(macResult.1, iosResult.1, "Selection across formats focus should match")
  }

  // MARK: - State Consistency Tests

  func testParity_StateAfterMultipleOperations() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> (String, Int, Bool) {
      try setupBasicDocument(editor: editor)

      // Insert text
      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        try t.select(anchorOffset: 5, focusOffset: 5)
        try (getSelection() as? RangeSelection)?.insertText(" inserted")
      }

      // Format part of text
      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        try t.select(anchorOffset: 0, focusOffset: 5)
        try (getSelection() as? RangeSelection)?.formatText(formatType: .bold)
      }

      // Delete some text
      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        try t.select(anchorOffset: 10, focusOffset: 15)
        try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true)
      }

      var content = ""
      var paragraphCount = 0
      var hasBoldText = false

      try editor.read {
        content = getRoot()?.getTextContent() ?? ""
        paragraphCount = getRoot()?.getChildrenSize() ?? 0
        if let p = getRoot()?.getFirstChild() as? ParagraphNode,
           let t = p.getFirstChild() as? TextNode {
          hasBoldText = t.getFormat().isTypeSet(type: .bold)
        }
      }

      return (content, paragraphCount, hasBoldText)
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult.0, iosResult.0, "Final content should match")
    XCTAssertEqual(macResult.1, iosResult.1, "Paragraph count should match")
    XCTAssertEqual(macResult.2, iosResult.2, "Bold formatting presence should match")
  }
}
