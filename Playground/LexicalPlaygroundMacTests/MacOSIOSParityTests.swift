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

  // MARK: - Advanced Formatting Tests

  func testParity_CombinedFormats() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> (String, Bool, Bool, Bool) {
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        let t = createTextNode(text: "Formatted text")

        // Apply multiple formats
        var format = TextFormat()
        format.bold = true
        format.italic = true
        format.underline = true
        try t.setFormat(format: format)

        try p.append([t])
        try root.append([p])
      }

      var content = ""
      var isBold = false, isItalic = false, isUnderline = false
      try editor.read {
        content = getRoot()?.getTextContent() ?? ""
        if let p = getRoot()?.getFirstChild() as? ParagraphNode,
           let t = p.getFirstChild() as? TextNode {
          let fmt = t.getFormat()
          isBold = fmt.bold
          isItalic = fmt.italic
          isUnderline = fmt.underline
        }
      }
      return (content, isBold, isItalic, isUnderline)
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult.0, iosResult.0, "Content should match")
    XCTAssertEqual(macResult.1, iosResult.1, "Bold should match")
    XCTAssertEqual(macResult.2, iosResult.2, "Italic should match")
    XCTAssertEqual(macResult.3, iosResult.3, "Underline should match")
  }

  func testParity_StrikethroughAndCode() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> (Bool, Bool) {
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()

        let t1 = createTextNode(text: "strikethrough ")
        var strikeFormat = TextFormat()
        strikeFormat.strikethrough = true
        try t1.setFormat(format: strikeFormat)

        let t2 = createTextNode(text: "code")
        var codeFormat = TextFormat()
        codeFormat.code = true
        try t2.setFormat(format: codeFormat)

        try p.append([t1, t2])
        try root.append([p])
      }

      var hasStrike = false, hasCode = false
      try editor.read {
        if let p = getRoot()?.getFirstChild() as? ParagraphNode {
          if let t1 = p.getFirstChild() as? TextNode {
            hasStrike = t1.getFormat().strikethrough
          }
          if let t2 = p.getLastChild() as? TextNode {
            hasCode = t2.getFormat().code
          }
        }
      }
      return (hasStrike, hasCode)
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult.0, iosResult.0, "Strikethrough should match")
    XCTAssertEqual(macResult.1, iosResult.1, "Code format should match")
  }

  func testParity_SubscriptSuperscript() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> (Bool, Bool) {
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()

        let t1 = createTextNode(text: "H")
        let t2 = createTextNode(text: "2")
        var subFormat = TextFormat()
        subFormat.subScript = true
        try t2.setFormat(format: subFormat)

        let t3 = createTextNode(text: "O x")
        let t4 = createTextNode(text: "2")
        var superFormat = TextFormat()
        superFormat.superScript = true
        try t4.setFormat(format: superFormat)

        try p.append([t1, t2, t3, t4])
        try root.append([p])
      }

      var hasSub = false, hasSuper = false
      try editor.read {
        if let p = getRoot()?.getFirstChild() as? ParagraphNode,
           let children = p.getChildren() as? [TextNode], children.count >= 4 {
          hasSub = children[1].getFormat().subScript
          hasSuper = children[3].getFormat().superScript
        }
      }
      return (hasSub, hasSuper)
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult.0, iosResult.0, "Subscript should match")
    XCTAssertEqual(macResult.1, iosResult.1, "Superscript should match")
  }

  // MARK: - Text Manipulation Tests

  func testParity_TextSplitting() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> Int {
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        let t = createTextNode(text: "HelloWorld")
        try p.append([t])
        try root.append([p])
      }

      var nodeCount = 0
      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        // Split at position 5 (between "Hello" and "World")
        _ = try t.splitText(splitOffsets: [5])
      }

      try editor.read {
        if let p = getRoot()?.getFirstChild() as? ParagraphNode {
          nodeCount = p.getChildrenSize()
        }
      }
      return nodeCount
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult, iosResult, "Split node count should match")
    XCTAssertEqual(macResult, 2, "Should have 2 nodes after split")
  }

  func testParity_TextSpliceInsertion() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> String {
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        let t = createTextNode(text: "HelloWorld")
        try p.append([t])
        try root.append([p])
      }

      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        // Splice " Beautiful " into position 5
        _ = try t.spliceText(offset: 5, delCount: 0, newText: " Beautiful ")
      }

      var content = ""
      try editor.read {
        content = getRoot()?.getTextContent() ?? ""
      }
      return content
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult, iosResult, "Spliced content should match")
    XCTAssertEqual(macResult, "Hello Beautiful World")
  }

  func testParity_TextSpliceReplacement() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> String {
      try setupBasicDocument(editor: editor)

      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        // Replace "World" (offset 6-11) with "Universe"
        _ = try t.spliceText(offset: 6, delCount: 5, newText: "Universe")
      }

      var content = ""
      try editor.read {
        content = getRoot()?.getTextContent() ?? ""
      }
      return content
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult, iosResult, "Replaced content should match")
    XCTAssertEqual(macResult, "Hello Universe")
  }

  func testParity_NodeRemoval() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> Int {
      try setupMultiParagraphDocument(editor: editor)

      try editor.update {
        guard let root = getRoot(),
              let p2 = root.getChildAtIndex(index: 1) as? ParagraphNode else { return }
        try p2.remove()
      }

      var count = 0
      try editor.read {
        count = getRoot()?.getChildrenSize() ?? 0
      }
      return count
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult, iosResult, "Paragraph count after removal should match")
    XCTAssertEqual(macResult, 2, "Should have 2 paragraphs after removing middle one")
  }

  // MARK: - Selection Manipulation Tests

  func testParity_SelectionExpansion() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> (Int, Int) {
      try setupBasicDocument(editor: editor)

      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        // Start with narrow selection
        try t.select(anchorOffset: 3, focusOffset: 5)
      }

      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        // Expand selection
        try t.select(anchorOffset: 0, focusOffset: 11)
      }

      var anchor = -1, focus = -1
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

    XCTAssertEqual(macResult.0, iosResult.0, "Expanded anchor should match")
    XCTAssertEqual(macResult.1, iosResult.1, "Expanded focus should match")
  }

  func testParity_SelectionCollapse() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> Bool {
      try setupBasicDocument(editor: editor)

      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        // Wide selection
        try t.select(anchorOffset: 0, focusOffset: 11)
      }

      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        // Collapse to single point
        try t.select(anchorOffset: 5, focusOffset: 5)
      }

      var isCollapsed = false
      try editor.read {
        if let sel = try getSelection() as? RangeSelection {
          isCollapsed = (sel.anchor.offset == sel.focus.offset)
        }
      }
      return isCollapsed
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult, iosResult, "Collapsed state should match")
    XCTAssertTrue(macResult, "Selection should be collapsed")
  }

  func testParity_SelectionAcrossParagraphs() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> (NodeKey, NodeKey, Int, Int) {
      try setupMultiParagraphDocument(editor: editor)

      try editor.update {
        guard let root = getRoot(),
              let p1 = root.getFirstChild() as? ParagraphNode,
              let t1 = p1.getFirstChild() as? TextNode else { return }
        // Start selection in first paragraph
        try t1.select(anchorOffset: 5, focusOffset: 5)

        // Extend selection to third paragraph
        if let p3 = root.getLastChild() as? ParagraphNode,
           let t3 = p3.getFirstChild() as? TextNode,
           let sel = try getSelection() as? RangeSelection {
          sel.focus.key = t3.key
          sel.focus.offset = 5
        }
      }

      var anchorKey = "", focusKey = "", anchorOff = -1, focusOff = -1
      try editor.read {
        if let sel = try getSelection() as? RangeSelection {
          anchorKey = sel.anchor.key
          focusKey = sel.focus.key
          anchorOff = sel.anchor.offset
          focusOff = sel.focus.offset
        }
      }
      return (anchorKey, focusKey, anchorOff, focusOff)
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertNotEqual(macResult.0, macResult.1, "Selection should span different nodes")
    XCTAssertEqual(macResult.0, iosResult.0, "Anchor keys should match")
    XCTAssertEqual(macResult.1, iosResult.1, "Focus keys should match")
    XCTAssertEqual(macResult.2, iosResult.2, "Anchor offsets should match")
    XCTAssertEqual(macResult.3, iosResult.3, "Focus offsets should match")
  }

  // MARK: - Complex Document Structure Tests

  func testParity_NestedNodeHierarchy() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> (Int, Int, String) {
      try editor.update {
        guard let root = getRoot() else { return }
        let p1 = createParagraphNode()
        let t1 = createTextNode(text: "Top level")
        try p1.append([t1])

        let p2 = createParagraphNode()
        let t2a = createTextNode(text: "First ")
        let t2b = createTextNode(text: "second ")
        let t2c = createTextNode(text: "third")
        try p2.append([t2a, t2b, t2c])

        try root.append([p1, p2])
      }

      var paragraphCount = 0, textNodeCount = 0
      var content = ""
      try editor.read {
        let rt = getRoot()
        paragraphCount = rt?.getChildrenSize() ?? 0
        if let p2 = rt?.getLastChild() as? ParagraphNode {
          textNodeCount = p2.getChildrenSize()
        }
        content = rt?.getTextContent() ?? ""
      }
      return (paragraphCount, textNodeCount, content)
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult.0, iosResult.0, "Paragraph count should match")
    XCTAssertEqual(macResult.1, iosResult.1, "Text node count should match")
    XCTAssertEqual(macResult.2, iosResult.2, "Content should match")
  }

  func testParity_EmptyNodesHandling() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> (Int, Int) {
      try editor.update {
        guard let root = getRoot() else { return }
        let p1 = createParagraphNode()
        let t1 = createTextNode(text: "")
        try p1.append([t1])

        let p2 = createParagraphNode()
        let t2 = createTextNode(text: "Content")
        try p2.append([t2])

        let p3 = createParagraphNode()
        let t3 = createTextNode(text: "")
        try p3.append([t3])

        try root.append([p1, p2, p3])
      }

      var paragraphs = 0
      var contentLength = 0
      try editor.read {
        paragraphs = getRoot()?.getChildrenSize() ?? 0
        contentLength = getRoot()?.getTextContent().count ?? 0
      }
      return (paragraphs, contentLength)
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult.0, iosResult.0, "Paragraph count with empty nodes should match")
    XCTAssertEqual(macResult.1, iosResult.1, "Content length should match")
  }

  func testParity_LargeTextNode() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> (Int, String, String) {
      let largeText = String(repeating: "Lorem ipsum dolor sit amet. ", count: 100)

      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        let t = createTextNode(text: largeText)
        try p.append([t])
        try root.append([p])
      }

      var length = 0, first10 = "", last10 = ""
      try editor.read {
        let content = getRoot()?.getTextContent() ?? ""
        length = content.count
        first10 = String(content.prefix(10))
        last10 = String(content.suffix(10))
      }
      return (length, first10, last10)
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult.0, iosResult.0, "Large text length should match")
    XCTAssertEqual(macResult.1, iosResult.1, "First 10 chars should match")
    XCTAssertEqual(macResult.2, iosResult.2, "Last 10 chars should match")
  }

  // MARK: - Format Persistence Tests

  func testParity_FormatPersistenceAfterSplit() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> (Bool, Bool) {
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        let t = createTextNode(text: "BoldText")
        var format = TextFormat()
        format.bold = true
        try t.setFormat(format: format)
        try p.append([t])
        try root.append([p])
      }

      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        _ = try t.splitText(splitOffsets: [4])
      }

      var firstBold = false, secondBold = false
      try editor.read {
        if let p = getRoot()?.getFirstChild() as? ParagraphNode,
           let children = p.getChildren() as? [TextNode], children.count >= 2 {
          firstBold = children[0].getFormat().bold
          secondBold = children[1].getFormat().bold
        }
      }
      return (firstBold, secondBold)
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult.0, iosResult.0, "First split node format should match")
    XCTAssertEqual(macResult.1, iosResult.1, "Second split node format should match")
  }

  // MARK: - Unicode and Special Characters Tests

  func testParity_UnicodeCharacters() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> String {
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        let t = createTextNode(text: "Hello 👋 World 🌍 Emoji 😀")
        try p.append([t])
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

    XCTAssertEqual(macResult, iosResult, "Unicode emoji content should match")
  }

  func testParity_MultibyteCharacters() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> String {
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        let t = createTextNode(text: "日本語 中文 한국어 العربية")
        try p.append([t])
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

    XCTAssertEqual(macResult, iosResult, "Multibyte character content should match")
  }

  func testParity_SpecialCharacters() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> String {
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        let t = createTextNode(text: "Special: \n\t\r & < > \" ' © ® ™")
        try p.append([t])
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

    XCTAssertEqual(macResult, iosResult, "Special character content should match")
  }

  func testParity_ZeroWidthCharacters() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> Int {
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        // Zero-width joiner, zero-width non-joiner, zero-width space
        let t = createTextNode(text: "Test\u{200D}\u{200C}\u{200B}Text")
        try p.append([t])
        try root.append([p])
      }

      var length = 0
      try editor.read {
        length = getRoot()?.getTextContent().count ?? 0
      }
      return length
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult, iosResult, "Zero-width character handling should match")
  }

  // MARK: - Selection Edge Cases

  func testParity_SelectionAtDocumentStart() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> (Int, Int) {
      try setupBasicDocument(editor: editor)

      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        try t.select(anchorOffset: 0, focusOffset: 0)
      }

      var anchor = -1, focus = -1
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

    XCTAssertEqual(macResult.0, iosResult.0, "Selection at document start anchor should match")
    XCTAssertEqual(macResult.1, iosResult.1, "Selection at document start focus should match")
    XCTAssertEqual(macResult.0, 0, "Should be at position 0")
  }

  func testParity_SelectionAtDocumentEnd() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> (Int, Int) {
      try setupBasicDocument(editor: editor)

      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        let endOffset = t.getTextPart().count
        try t.select(anchorOffset: endOffset, focusOffset: endOffset)
      }

      var anchor = -1, focus = -1
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

    XCTAssertEqual(macResult.0, iosResult.0, "Selection at document end anchor should match")
    XCTAssertEqual(macResult.1, iosResult.1, "Selection at document end focus should match")
  }

  func testParity_ReverseSelection() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> (Int, Int, Bool) {
      try setupBasicDocument(editor: editor)

      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        // Reverse selection: anchor > focus
        try t.select(anchorOffset: 8, focusOffset: 3)
      }

      var anchor = -1, focus = -1, isBackward = false
      try editor.read {
        if let sel = try getSelection() as? RangeSelection {
          anchor = sel.anchor.offset
          focus = sel.focus.offset
          isBackward = (anchor > focus)
        }
      }
      return (anchor, focus, isBackward)
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult.0, iosResult.0, "Reverse selection anchor should match")
    XCTAssertEqual(macResult.1, iosResult.1, "Reverse selection focus should match")
    XCTAssertEqual(macResult.2, iosResult.2, "Reverse selection direction should match")
  }

  // MARK: - Format Combination Tests

  func testParity_AllFormatsEnabled() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> [Bool] {
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        let t = createTextNode(text: "All formats")
        var format = TextFormat()
        format.bold = true
        format.italic = true
        format.underline = true
        format.strikethrough = true
        format.code = true
        format.subScript = true
        format.superScript = true
        try t.setFormat(format: format)
        try p.append([t])
        try root.append([p])
      }

      var formats: [Bool] = []
      try editor.read {
        if let p = getRoot()?.getFirstChild() as? ParagraphNode,
           let t = p.getFirstChild() as? TextNode {
          let fmt = t.getFormat()
          formats = [fmt.bold, fmt.italic, fmt.underline, fmt.strikethrough,
                     fmt.code, fmt.subScript, fmt.superScript]
        }
      }
      return formats
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult, iosResult, "All formats enabled should match")
    XCTAssertTrue(macResult.allSatisfy { $0 }, "All formats should be true")
  }

  func testParity_FormatClear() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> [Bool] {
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        let t = createTextNode(text: "Clear formats")
        var format = TextFormat()
        format.bold = true
        format.italic = true
        try t.setFormat(format: format)
        try p.append([t])
        try root.append([p])
      }

      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        // Clear formats by setting empty format
        try t.setFormat(format: TextFormat())
      }

      var formats: [Bool] = []
      try editor.read {
        if let p = getRoot()?.getFirstChild() as? ParagraphNode,
           let t = p.getFirstChild() as? TextNode {
          let fmt = t.getFormat()
          formats = [fmt.bold, fmt.italic, fmt.underline, fmt.strikethrough, fmt.code]
        }
      }
      return formats
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult, iosResult, "Cleared formats should match")
    XCTAssertTrue(macResult.allSatisfy { !$0 }, "All formats should be false after clear")
  }

  // MARK: - Text Insertion and Deletion Tests

  func testParity_InsertTextAtStart() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> String {
      try setupBasicDocument(editor: editor)

      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        _ = try t.spliceText(offset: 0, delCount: 0, newText: "Start ")
      }

      var content = ""
      try editor.read {
        content = getRoot()?.getTextContent() ?? ""
      }
      return content
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult, iosResult, "Insert at start should match")
    XCTAssertEqual(macResult, "Start Hello World")
  }

  func testParity_InsertTextAtEnd() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> String {
      try setupBasicDocument(editor: editor)

      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        let endOffset = t.getTextPart().count
        _ = try t.spliceText(offset: endOffset, delCount: 0, newText: " End")
      }

      var content = ""
      try editor.read {
        content = getRoot()?.getTextContent() ?? ""
      }
      return content
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult, iosResult, "Insert at end should match")
    XCTAssertEqual(macResult, "Hello World End")
  }

  func testParity_DeleteAllText() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> String {
      try setupBasicDocument(editor: editor)

      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        let length = t.getTextPart().count
        _ = try t.spliceText(offset: 0, delCount: length, newText: "")
      }

      var content = ""
      try editor.read {
        content = getRoot()?.getTextContent() ?? ""
      }
      return content
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult, iosResult, "Delete all text should match")
    XCTAssertEqual(macResult, "")
  }

  func testParity_DeleteFromMiddle() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> String {
      try setupBasicDocument(editor: editor)

      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        // Delete " World" (offset 5-11)
        _ = try t.spliceText(offset: 5, delCount: 6, newText: "")
      }

      var content = ""
      try editor.read {
        content = getRoot()?.getTextContent() ?? ""
      }
      return content
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult, iosResult, "Delete from middle should match")
    XCTAssertEqual(macResult, "Hello")
  }

  // MARK: - Multiple Text Nodes Tests

  func testParity_MultipleTextNodesFormatting() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> (Bool, Bool, Bool) {
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()

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

      var hasNormal = false, hasBold = false, hasItalic = false
      try editor.read {
        if let p = getRoot()?.getFirstChild() as? ParagraphNode,
           let children = p.getChildren() as? [TextNode], children.count >= 3 {
          hasNormal = !children[0].getFormat().bold && !children[0].getFormat().italic
          hasBold = children[1].getFormat().bold
          hasItalic = children[2].getFormat().italic
        }
      }
      return (hasNormal, hasBold, hasItalic)
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult.0, iosResult.0, "Normal text format should match")
    XCTAssertEqual(macResult.1, iosResult.1, "Bold text format should match")
    XCTAssertEqual(macResult.2, iosResult.2, "Italic text format should match")
  }

  func testParity_TextNodeMerging() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> Int {
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()

        // Create adjacent text nodes with same formatting
        let t1 = createTextNode(text: "Hello ")
        let t2 = createTextNode(text: "World")
        try p.append([t1, t2])
        try root.append([p])
      }

      var nodeCount = 0
      try editor.read {
        if let p = getRoot()?.getFirstChild() as? ParagraphNode {
          nodeCount = p.getChildrenSize()
        }
      }
      return nodeCount
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult, iosResult, "Text node count should match")
  }

  // MARK: - Paragraph Manipulation Tests

  func testParity_InsertParagraphBetween() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> (Int, String) {
      try setupMultiParagraphDocument(editor: editor)

      try editor.update {
        guard let root = getRoot() else { return }
        let newP = createParagraphNode()
        let newT = createTextNode(text: "Inserted paragraph")
        try newP.append([newT])

        // Insert between first and second paragraph
        if let p1 = root.getChildAtIndex(index: 0) {
          try p1.insertAfter(nodeToInsert: newP)
        }
      }

      var count = 0
      var secondContent = ""
      try editor.read {
        count = getRoot()?.getChildrenSize() ?? 0
        if let p2 = getRoot()?.getChildAtIndex(index: 1) as? ParagraphNode {
          secondContent = p2.getTextContent()
        }
      }
      return (count, secondContent)
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult.0, iosResult.0, "Paragraph count should match")
    XCTAssertEqual(macResult.1, iosResult.1, "Second paragraph content should match")
    XCTAssertEqual(macResult.0, 4, "Should have 4 paragraphs after insertion")
  }

  func testParity_AppendParagraphToEnd() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> (Int, String) {
      try setupBasicDocument(editor: editor)

      try editor.update {
        guard let root = getRoot() else { return }
        let newP = createParagraphNode()
        let newT = createTextNode(text: "Appended paragraph")
        try newP.append([newT])
        try root.append([newP])
      }

      var count = 0
      var lastContent = ""
      try editor.read {
        count = getRoot()?.getChildrenSize() ?? 0
        if let lastP = getRoot()?.getLastChild() as? ParagraphNode {
          lastContent = lastP.getTextContent()
        }
      }
      return (count, lastContent)
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult.0, iosResult.0, "Paragraph count should match")
    XCTAssertEqual(macResult.1, iosResult.1, "Last paragraph content should match")
    XCTAssertEqual(macResult.1, "Appended paragraph")
  }

  func testParity_RemoveAllParagraphs() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> Int {
      try setupMultiParagraphDocument(editor: editor)

      try editor.update {
        guard let root = getRoot() else { return }
        let children = root.getChildren()
        for child in children {
          try child.remove()
        }
      }

      var count = 0
      try editor.read {
        count = getRoot()?.getChildrenSize() ?? 0
      }
      return count
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult, iosResult, "Paragraph count after removal should match")
    XCTAssertEqual(macResult, 0, "Should have 0 paragraphs")
  }

  // MARK: - Complex Operations Tests

  func testParity_ChainedTextModifications() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> String {
      try setupBasicDocument(editor: editor)

      // Multiple modifications in sequence
      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        _ = try t.spliceText(offset: 0, delCount: 0, newText: ">>> ")
      }

      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        let len = t.getTextPart().count
        _ = try t.spliceText(offset: len, delCount: 0, newText: " <<<")
      }

      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        var format = TextFormat()
        format.bold = true
        try t.setFormat(format: format)
      }

      var content = ""
      try editor.read {
        content = getRoot()?.getTextContent() ?? ""
      }
      return content
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult, iosResult, "Chained modifications should match")
    XCTAssertEqual(macResult, ">>> Hello World <<<")
  }

  func testParity_InterleavedOperations() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> (Int, String) {
      try editor.update {
        guard let root = getRoot() else { return }
        let p1 = createParagraphNode()
        let t1 = createTextNode(text: "First")
        try p1.append([t1])
        try root.append([p1])
      }

      try editor.update {
        guard let root = getRoot(),
              let p1 = root.getFirstChild() as? ParagraphNode else { return }
        let p2 = createParagraphNode()
        let t2 = createTextNode(text: "Second")
        try p2.append([t2])
        try p1.insertAfter(nodeToInsert: p2)
      }

      try editor.update {
        guard let root = getRoot(),
              let p1 = root.getFirstChild() as? ParagraphNode,
              let t1 = p1.getFirstChild() as? TextNode else { return }
        var format = TextFormat()
        format.italic = true
        try t1.setFormat(format: format)
      }

      var count = 0
      var content = ""
      try editor.read {
        count = getRoot()?.getChildrenSize() ?? 0
        content = getRoot()?.getTextContent() ?? ""
      }
      return (count, content)
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult.0, iosResult.0, "Paragraph count should match")
    XCTAssertEqual(macResult.1, iosResult.1, "Content should match")
  }

  // MARK: - Node Traversal Tests

  func testParity_GetNextSibling() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> (String, String) {
      try setupMultiParagraphDocument(editor: editor)

      var firstContent = "", secondContent = ""
      try editor.read {
        if let root = getRoot(),
           let p1 = root.getFirstChild() as? ParagraphNode,
           let p2 = p1.getNextSibling() as? ParagraphNode {
          firstContent = p1.getTextContent()
          secondContent = p2.getTextContent()
        }
      }
      return (firstContent, secondContent)
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult.0, iosResult.0, "First paragraph content should match")
    XCTAssertEqual(macResult.1, iosResult.1, "Second paragraph content should match")
  }

  func testParity_GetPreviousSibling() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> (String, String) {
      try setupMultiParagraphDocument(editor: editor)

      var lastContent = "", secondLastContent = ""
      try editor.read {
        if let root = getRoot(),
           let pLast = root.getLastChild() as? ParagraphNode,
           let pPrev = pLast.getPreviousSibling() as? ParagraphNode {
          lastContent = pLast.getTextContent()
          secondLastContent = pPrev.getTextContent()
        }
      }
      return (lastContent, secondLastContent)
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult.0, iosResult.0, "Last paragraph content should match")
    XCTAssertEqual(macResult.1, iosResult.1, "Second last paragraph content should match")
  }

  func testParity_GetParent() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> (String, String) {
      try setupBasicDocument(editor: editor)

      var textNodeKey = "", parentKey = ""
      try editor.read {
        if let root = getRoot(),
           let p = root.getFirstChild() as? ParagraphNode,
           let t = p.getFirstChild() as? TextNode,
           let parent = t.getParent() {
          textNodeKey = t.key
          parentKey = parent.key
        }
      }
      return (textNodeKey, parentKey)
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertNotEqual(macResult.0, "", "Text node key should not be empty")
    XCTAssertNotEqual(macResult.1, "", "Parent key should not be empty")
    XCTAssertEqual(macResult.0, iosResult.0, "Text node keys should match")
    XCTAssertEqual(macResult.1, iosResult.1, "Parent keys should match")
  }

  func testParity_GetChildAtIndex() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> String {
      try setupMultiParagraphDocument(editor: editor)

      var content = ""
      try editor.read {
        if let root = getRoot(),
           let p2 = root.getChildAtIndex(index: 1) as? ParagraphNode {
          content = p2.getTextContent()
        }
      }
      return content
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult, iosResult, "Child at index 1 content should match")
    XCTAssertEqual(macResult, "Second paragraph")
  }

  // MARK: - Text Node Properties Tests

  func testParity_GetTextPartSize() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> Int {
      try setupBasicDocument(editor: editor)

      var size = 0
      try editor.read {
        if let root = getRoot(),
           let p = root.getFirstChild() as? ParagraphNode,
           let t = p.getFirstChild() as? TextNode {
          size = t.getTextPartSize()
        }
      }
      return size
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult, iosResult, "Text part size should match")
    XCTAssertEqual(macResult, 11, "Hello World is 11 characters")
  }

  func testParity_IsSimpleText() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> Bool {
      try setupBasicDocument(editor: editor)

      var isSimple = false
      try editor.read {
        if let root = getRoot(),
           let p = root.getFirstChild() as? ParagraphNode,
           let t = p.getFirstChild() as? TextNode {
          isSimple = t.isSimpleText()
        }
      }
      return isSimple
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult, iosResult, "isSimpleText result should match")
  }

  func testParity_CanInsertTextBefore() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> Bool {
      try setupBasicDocument(editor: editor)

      var canInsert = false
      try editor.read {
        if let root = getRoot(),
           let p = root.getFirstChild() as? ParagraphNode,
           let t = p.getFirstChild() as? TextNode {
          canInsert = t.canInsertTextBefore()
        }
      }
      return canInsert
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult, iosResult, "canInsertTextBefore should match")
  }

  func testParity_CanInsertTextAfter() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> Bool {
      try setupBasicDocument(editor: editor)

      var canInsert = false
      try editor.read {
        if let root = getRoot(),
           let p = root.getFirstChild() as? ParagraphNode,
           let t = p.getFirstChild() as? TextNode {
          canInsert = t.canInsertTextAfter()
        }
      }
      return canInsert
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult, iosResult, "canInsertTextAfter should match")
  }

  // MARK: - Multiple Split Tests

  func testParity_MultipleSplitOffsets() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> (Int, [String]) {
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        let t = createTextNode(text: "OneTwoThreeFour")
        try p.append([t])
        try root.append([p])
      }

      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        // Split at positions 3, 6, 11
        _ = try t.splitText(splitOffsets: [3, 6, 11])
      }

      var nodeCount = 0
      var texts: [String] = []
      try editor.read {
        if let p = getRoot()?.getFirstChild() as? ParagraphNode {
          nodeCount = p.getChildrenSize()
          if let children = p.getChildren() as? [TextNode] {
            texts = children.map { $0.getTextPart() }
          }
        }
      }
      return (nodeCount, texts)
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult.0, iosResult.0, "Split node count should match")
    XCTAssertEqual(macResult.1, iosResult.1, "Split text array should match")
  }

  func testParity_SplitWithFormat() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> (Bool, Bool) {
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        let t = createTextNode(text: "BoldItalic")
        var format = TextFormat()
        format.bold = true
        format.italic = true
        try t.setFormat(format: format)
        try p.append([t])
        try root.append([p])
      }

      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        _ = try t.splitText(splitOffsets: [4])
      }

      var firstBold = false, secondItalic = false
      try editor.read {
        if let p = getRoot()?.getFirstChild() as? ParagraphNode,
           let children = p.getChildren() as? [TextNode], children.count >= 2 {
          firstBold = children[0].getFormat().bold
          secondItalic = children[1].getFormat().italic
        }
      }
      return (firstBold, secondItalic)
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult.0, iosResult.0, "First split bold should match")
    XCTAssertEqual(macResult.1, iosResult.1, "Second split italic should match")
  }

  // MARK: - Selection Insert Text Tests

  func testParity_SelectionInsertText() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> String {
      try setupBasicDocument(editor: editor)

      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
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

    XCTAssertEqual(macResult, iosResult, "Inserted text should match")
    XCTAssertEqual(macResult, "Hello Universe")
  }

  func testParity_SelectionDeleteContent() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> String {
      try setupBasicDocument(editor: editor)

      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        try t.select(anchorOffset: 5, focusOffset: 11)
        try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true)
      }

      var content = ""
      try editor.read {
        content = getRoot()?.getTextContent() ?? ""
      }
      return content
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult, iosResult, "Content after delete should match")
    XCTAssertEqual(macResult, "Hello")
  }

  // MARK: - Format Toggle Tests

  func testParity_FormatToggleBold() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> (Bool, Bool) {
      try setupBasicDocument(editor: editor)

      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        try t.select(anchorOffset: 0, focusOffset: 5)
        try (getSelection() as? RangeSelection)?.formatText(formatType: .bold)
      }

      var isBold = false
      try editor.read {
        if let p = getRoot()?.getFirstChild() as? ParagraphNode,
           let t = p.getFirstChild() as? TextNode {
          isBold = t.getFormat().bold
        }
      }

      // Toggle off
      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        try t.select(anchorOffset: 0, focusOffset: 5)
        try (getSelection() as? RangeSelection)?.formatText(formatType: .bold)
      }

      var isNotBold = true
      try editor.read {
        if let p = getRoot()?.getFirstChild() as? ParagraphNode,
           let t = p.getFirstChild() as? TextNode {
          isNotBold = !t.getFormat().bold
        }
      }

      return (isBold, isNotBold)
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult.0, iosResult.0, "Bold state should match")
    XCTAssertEqual(macResult.1, iosResult.1, "Not bold state should match")
  }

  // MARK: - Empty Document Tests

  func testParity_EmptyRootNode() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> (Int, String) {
      var count = 0
      var content = ""
      try editor.read {
        count = getRoot()?.getChildrenSize() ?? 0
        content = getRoot()?.getTextContent() ?? ""
      }
      return (count, content)
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult.0, iosResult.0, "Empty root children count should match")
    XCTAssertEqual(macResult.1, iosResult.1, "Empty root content should match")
    XCTAssertEqual(macResult.0, 0, "Should have 0 children")
    XCTAssertEqual(macResult.1, "", "Should have empty content")
  }

  func testParity_SingleEmptyParagraph() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> (Int, String) {
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        try root.append([p])
      }

      var count = 0
      var content = ""
      try editor.read {
        count = getRoot()?.getChildrenSize() ?? 0
        content = getRoot()?.getTextContent() ?? ""
      }
      return (count, content)
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult.0, iosResult.0, "Paragraph count should match")
    XCTAssertEqual(macResult.1, iosResult.1, "Content should match")
    XCTAssertEqual(macResult.0, 1, "Should have 1 paragraph")
    XCTAssertEqual(macResult.1, "", "Should have empty content")
  }

  // MARK: - Node Insertion Tests

  func testParity_InsertBefore() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> (Int, String) {
      try setupBasicDocument(editor: editor)

      try editor.update {
        guard let root = getRoot(),
              let p1 = root.getFirstChild() as? ParagraphNode else { return }
        let p0 = createParagraphNode()
        let t0 = createTextNode(text: "Prepended")
        try p0.append([t0])
        try p1.insertBefore(nodeToInsert: p0)
      }

      var count = 0
      var firstContent = ""
      try editor.read {
        count = getRoot()?.getChildrenSize() ?? 0
        if let p = getRoot()?.getFirstChild() as? ParagraphNode {
          firstContent = p.getTextContent()
        }
      }
      return (count, firstContent)
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult.0, iosResult.0, "Paragraph count should match")
    XCTAssertEqual(macResult.1, iosResult.1, "First paragraph content should match")
    XCTAssertEqual(macResult.1, "Prepended")
  }

  func testParity_InsertAfter() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> (Int, String) {
      try setupBasicDocument(editor: editor)

      try editor.update {
        guard let root = getRoot(),
              let p1 = root.getFirstChild() as? ParagraphNode else { return }
        let p2 = createParagraphNode()
        let t2 = createTextNode(text: "Appended")
        try p2.append([t2])
        try p1.insertAfter(nodeToInsert: p2)
      }

      var count = 0
      var lastContent = ""
      try editor.read {
        count = getRoot()?.getChildrenSize() ?? 0
        if let p = getRoot()?.getLastChild() as? ParagraphNode {
          lastContent = p.getTextContent()
        }
      }
      return (count, lastContent)
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult.0, iosResult.0, "Paragraph count should match")
    XCTAssertEqual(macResult.1, iosResult.1, "Last paragraph content should match")
    XCTAssertEqual(macResult.1, "Appended")
  }

  // MARK: - Text Content Tests

  func testParity_GetTextContentMaxLength() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> String {
      try setupBasicDocument(editor: editor)

      var content = ""
      try editor.read {
        if let root = getRoot(),
           let p = root.getFirstChild() as? ParagraphNode,
           let t = p.getFirstChild() as? TextNode {
          content = t.getTextContent(maxLength: 5)
        }
      }
      return content
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult, iosResult, "Truncated text content should match")
    XCTAssertEqual(macResult, "Hello")
  }

  // MARK: - Whitespace Handling Tests

  func testParity_LeadingWhitespace() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> String {
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        let t = createTextNode(text: "   Leading spaces")
        try p.append([t])
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

    XCTAssertEqual(macResult, iosResult, "Leading whitespace should match")
  }

  func testParity_TrailingWhitespace() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> String {
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        let t = createTextNode(text: "Trailing spaces   ")
        try p.append([t])
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

    XCTAssertEqual(macResult, iosResult, "Trailing whitespace should match")
  }

  func testParity_MultipleConsecutiveSpaces() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> String {
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        let t = createTextNode(text: "Multiple    consecutive    spaces")
        try p.append([t])
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

    XCTAssertEqual(macResult, iosResult, "Multiple spaces should match")
  }

  // MARK: - Node Key Tests

  func testParity_NodeKeyUniqueness() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> Bool {
      try setupMultiParagraphDocument(editor: editor)

      var keys = Set<String>()
      var allUnique = true
      try editor.read {
        if let root = getRoot() {
          for child in root.getChildren() {
            if keys.contains(child.key) {
              allUnique = false
              break
            }
            keys.insert(child.key)
          }
        }
      }
      return allUnique
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult, iosResult, "Key uniqueness behavior should match")
    XCTAssertTrue(macResult, "All keys should be unique")
  }

  // MARK: - Selection Type Tests

  func testParity_RangeSelectionType() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> Bool {
      try setupBasicDocument(editor: editor)

      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        try t.select(anchorOffset: 0, focusOffset: 5)
      }

      var isRange = false
      try editor.read {
        if let sel = try getSelection() {
          isRange = (sel is RangeSelection)
        }
      }
      return isRange
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult, iosResult, "Selection type should match")
    XCTAssertTrue(macResult, "Should be RangeSelection")
  }

  // MARK: - Node Type and Hierarchy Tests

  func testParity_ParagraphNodeType() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> String {
      try setupBasicDocument(editor: editor)

      var nodeType = ""
      try editor.read {
        if let root = getRoot(),
           let p = root.getFirstChild() as? ParagraphNode {
          nodeType = String(describing: type(of: p))
        }
      }
      return nodeType
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult, iosResult, "Paragraph node type should match")
  }

  func testParity_TextNodeType() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> String {
      try setupBasicDocument(editor: editor)

      var nodeType = ""
      try editor.read {
        if let root = getRoot(),
           let p = root.getFirstChild() as? ParagraphNode,
           let t = p.getFirstChild() as? TextNode {
          nodeType = String(describing: type(of: t))
        }
      }
      return nodeType
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult, iosResult, "Text node type should match")
  }

  func testParity_RootNodeChildren() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> Int {
      try setupMultiParagraphDocument(editor: editor)

      var childCount = 0
      try editor.read {
        if let root = getRoot() {
          childCount = root.getChildren().count
        }
      }
      return childCount
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult, iosResult, "Root children count should match")
    XCTAssertEqual(macResult, 3, "Should have 3 paragraphs")
  }

  // MARK: - Complex Text Operations Tests

  func testParity_ReplaceTextMultipleTimes() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> String {
      try setupBasicDocument(editor: editor)

      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        _ = try t.spliceText(offset: 6, delCount: 5, newText: "Earth")
      }

      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        _ = try t.spliceText(offset: 0, delCount: 5, newText: "Hi")
      }

      var content = ""
      try editor.read {
        content = getRoot()?.getTextContent() ?? ""
      }
      return content
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult, iosResult, "Multiple replacements should match")
    XCTAssertEqual(macResult, "Hi Earth")
  }

  func testParity_SpliceNegativeOffset() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> String {
      try setupBasicDocument(editor: editor)

      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        // Negative offset should clamp to 0
        _ = try t.spliceText(offset: -5, delCount: 0, newText: "Start ")
      }

      var content = ""
      try editor.read {
        content = getRoot()?.getTextContent() ?? ""
      }
      return content
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult, iosResult, "Negative offset handling should match")
  }

  // MARK: - Selection Edge Cases Advanced

  func testParity_SelectionWithFormatting() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> (Int, Int, Bool) {
      try setupBasicDocument(editor: editor)

      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        var format = TextFormat()
        format.bold = true
        try t.setFormat(format: format)
        try t.select(anchorOffset: 3, focusOffset: 8)
      }

      var anchor = -1, focus = -1, isBold = false
      try editor.read {
        if let sel = try getSelection() as? RangeSelection {
          anchor = sel.anchor.offset
          focus = sel.focus.offset
        }
        if let p = getRoot()?.getFirstChild() as? ParagraphNode,
           let t = p.getFirstChild() as? TextNode {
          isBold = t.getFormat().bold
        }
      }
      return (anchor, focus, isBold)
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult.0, iosResult.0, "Anchor with formatting should match")
    XCTAssertEqual(macResult.1, iosResult.1, "Focus with formatting should match")
    XCTAssertEqual(macResult.2, iosResult.2, "Bold state should match")
  }

  func testParity_SelectionAfterTextModification() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> (Int, Int) {
      try setupBasicDocument(editor: editor)

      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        try t.select(anchorOffset: 0, focusOffset: 5)
        _ = try t.spliceText(offset: 0, delCount: 0, newText: "XXX ")
      }

      var anchor = -1, focus = -1
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

    XCTAssertEqual(macResult.0, iosResult.0, "Selection anchor after modification should match")
    XCTAssertEqual(macResult.1, iosResult.1, "Selection focus after modification should match")
  }

  // MARK: - Paragraph Operations Advanced

  func testParity_ReplaceEntireParagraph() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> String {
      try setupBasicDocument(editor: editor)

      try editor.update {
        guard let root = getRoot(),
              let oldP = root.getFirstChild() as? ParagraphNode else { return }
        let newP = createParagraphNode()
        let newT = createTextNode(text: "Replaced paragraph")
        try newP.append([newT])
        try oldP.insertAfter(nodeToInsert: newP)
        try oldP.remove()
      }

      var content = ""
      try editor.read {
        content = getRoot()?.getTextContent() ?? ""
      }
      return content
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult, iosResult, "Replaced paragraph content should match")
    XCTAssertEqual(macResult, "Replaced paragraph")
  }

  func testParity_SwapParagraphs() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> (String, String) {
      try setupMultiParagraphDocument(editor: editor)

      try editor.update {
        guard let root = getRoot(),
              let p1 = root.getChildAtIndex(index: 0) as? ParagraphNode,
              let p2 = root.getChildAtIndex(index: 1) as? ParagraphNode else { return }
        // Remove p2 and insert before p1
        try p2.remove()
        try p1.insertBefore(nodeToInsert: p2)
      }

      var first = "", second = ""
      try editor.read {
        if let p1 = getRoot()?.getFirstChild() as? ParagraphNode,
           let p2 = p1.getNextSibling() as? ParagraphNode {
          first = p1.getTextContent()
          second = p2.getTextContent()
        }
      }
      return (first, second)
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult.0, iosResult.0, "First paragraph after swap should match")
    XCTAssertEqual(macResult.1, iosResult.1, "Second paragraph after swap should match")
  }

  // MARK: - Format State Tests

  func testParity_FormatStateAfterPartialSelection() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> (Bool, Bool) {
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        let t = createTextNode(text: "BoldNormal")
        try p.append([t])
        try root.append([p])
      }

      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        try t.select(anchorOffset: 0, focusOffset: 4)
        try (getSelection() as? RangeSelection)?.formatText(formatType: .bold)
      }

      var firstBold = false, secondBold = false
      try editor.read {
        if let p = getRoot()?.getFirstChild() as? ParagraphNode,
           let children = p.getChildren() as? [TextNode], children.count >= 2 {
          firstBold = children[0].getFormat().bold
          secondBold = children[1].getFormat().bold
        }
      }
      return (firstBold, secondBold)
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult.0, iosResult.0, "First part bold state should match")
    XCTAssertEqual(macResult.1, iosResult.1, "Second part bold state should match")
  }

  func testParity_MultipleFormatsSequential() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> (Bool, Bool, Bool) {
      try setupBasicDocument(editor: editor)

      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        var format = t.getFormat()
        format.bold = true
        try t.setFormat(format: format)
      }

      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        var format = t.getFormat()
        format.italic = true
        try t.setFormat(format: format)
      }

      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        var format = t.getFormat()
        format.underline = true
        try t.setFormat(format: format)
      }

      var bold = false, italic = false, underline = false
      try editor.read {
        if let p = getRoot()?.getFirstChild() as? ParagraphNode,
           let t = p.getFirstChild() as? TextNode {
          let fmt = t.getFormat()
          bold = fmt.bold
          italic = fmt.italic
          underline = fmt.underline
        }
      }
      return (bold, italic, underline)
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult.0, iosResult.0, "Sequential bold should match")
    XCTAssertEqual(macResult.1, iosResult.1, "Sequential italic should match")
    XCTAssertEqual(macResult.2, iosResult.2, "Sequential underline should match")
  }

  // MARK: - Edge Case Character Tests

  func testParity_SingleCharacterNode() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> (String, Int) {
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        let t = createTextNode(text: "A")
        try p.append([t])
        try root.append([p])
      }

      var content = ""
      var length = 0
      try editor.read {
        content = getRoot()?.getTextContent() ?? ""
        if let p = getRoot()?.getFirstChild() as? ParagraphNode,
           let t = p.getFirstChild() as? TextNode {
          length = t.getTextPartSize()
        }
      }
      return (content, length)
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult.0, iosResult.0, "Single char content should match")
    XCTAssertEqual(macResult.1, iosResult.1, "Single char length should match")
  }

  func testParity_NewlineCharacter() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> (String, Int) {
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        let t = createTextNode(text: "Line1\nLine2")
        try p.append([t])
        try root.append([p])
      }

      var content = ""
      var length = 0
      try editor.read {
        content = getRoot()?.getTextContent() ?? ""
        length = content.count
      }
      return (content, length)
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult.0, iosResult.0, "Newline content should match")
    XCTAssertEqual(macResult.1, iosResult.1, "Newline length should match")
  }

  func testParity_TabCharacter() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> String {
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        let t = createTextNode(text: "Before\tAfter")
        try p.append([t])
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

    XCTAssertEqual(macResult, iosResult, "Tab character should match")
  }

  // MARK: - Deep Nesting Tests

  func testParity_DeepTextNodeArray() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> (Int, String) {
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()

        // Create 10 text nodes
        for i in 1...10 {
          let t = createTextNode(text: "\(i) ")
          try p.append([t])
        }

        try root.append([p])
      }

      var nodeCount = 0
      var content = ""
      try editor.read {
        if let p = getRoot()?.getFirstChild() as? ParagraphNode {
          nodeCount = p.getChildrenSize()
        }
        content = getRoot()?.getTextContent() ?? ""
      }
      return (nodeCount, content)
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult.0, iosResult.0, "Deep node count should match")
    XCTAssertEqual(macResult.1, iosResult.1, "Deep node content should match")
  }

  // MARK: - Boundary Offset Tests

  func testParity_SpliceAtBoundary() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> String {
      try setupBasicDocument(editor: editor)

      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        let length = t.getTextPartSize()
        _ = try t.spliceText(offset: length, delCount: 0, newText: "!")
      }

      var content = ""
      try editor.read {
        content = getRoot()?.getTextContent() ?? ""
      }
      return content
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult, iosResult, "Splice at boundary should match")
    XCTAssertEqual(macResult, "Hello World!")
  }

  func testParity_SplitAtBoundary() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> (Int, String, String) {
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        let t = createTextNode(text: "Test")
        try p.append([t])
        try root.append([p])
      }

      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        // Split at position 0 (beginning)
        _ = try t.splitText(splitOffsets: [0])
      }

      var nodeCount = 0
      var first = "", second = ""
      try editor.read {
        if let p = getRoot()?.getFirstChild() as? ParagraphNode {
          nodeCount = p.getChildrenSize()
          if let children = p.getChildren() as? [TextNode], children.count >= 2 {
            first = children[0].getTextPart()
            second = children[1].getTextPart()
          }
        }
      }
      return (nodeCount, first, second)
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult.0, iosResult.0, "Split at boundary node count should match")
    XCTAssertEqual(macResult.1, iosResult.1, "First part after boundary split should match")
    XCTAssertEqual(macResult.2, iosResult.2, "Second part after boundary split should match")
  }

  // MARK: - State Consistency Advanced Tests

  func testParity_ConsecutiveUpdates() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> String {
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        let t = createTextNode(text: "A")
        try p.append([t])
        try root.append([p])
      }

      for _ in 1...5 {
        try editor.update {
          guard let root = getRoot(),
                let p = root.getFirstChild() as? ParagraphNode,
                let t = p.getFirstChild() as? TextNode else { return }
          let current = t.getTextPart()
          try t.setText(current + "A")
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

    XCTAssertEqual(macResult, iosResult, "Consecutive updates should match")
    XCTAssertEqual(macResult, "AAAAAA")
  }

  func testParity_AlternatingReadWrite() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> String {
      try setupBasicDocument(editor: editor)

      for i in 1...3 {
        var current = ""
        try editor.read {
          current = getRoot()?.getTextContent() ?? ""
        }

        try editor.update {
          guard let root = getRoot(),
                let p = root.getFirstChild() as? ParagraphNode,
                let t = p.getFirstChild() as? TextNode else { return }
          try t.setText(current + " \(i)")
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

    XCTAssertEqual(macResult, iosResult, "Alternating read/write should match")
  }

  // MARK: - Format Combinations Advanced Tests

  func testParity_AllFormatsApplied() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> String {
      try setupBasicDocument(editor: editor)

      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }

        var allFormats = TextFormat()
        allFormats.bold = true
        allFormats.italic = true
        allFormats.underline = true
        allFormats.strikethrough = true
        allFormats.code = true
        try t.setFormat(format: allFormats)
      }

      var result = ""
      try editor.read {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        let fmt = t.getFormat()
        result = "b:\(fmt.bold),i:\(fmt.italic),u:\(fmt.underline),s:\(fmt.strikethrough),c:\(fmt.code)"
      }
      return result
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult, iosResult, "All formats applied should match")
    XCTAssertEqual(macResult, "b:true,i:true,u:true,s:true,c:true")
  }

  func testParity_FormatClearAfterApply() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> String {
      try setupBasicDocument(editor: editor)

      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }

        var boldFormat = TextFormat()
        boldFormat.bold = true
        try t.setFormat(format: boldFormat)

        try t.setFormat(format: TextFormat())
      }

      var result = ""
      try editor.read {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        let fmt = t.getFormat()
        result = "bold:\(fmt.bold)"
      }
      return result
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult, iosResult, "Format clear should match")
    XCTAssertEqual(macResult, "bold:false")
  }

  func testParity_SubscriptSuperscriptMutualExclusion() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> String {
      try setupBasicDocument(editor: editor)

      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }

        var subFormat = TextFormat()
        subFormat.subScript = true
        try t.setFormat(format: subFormat)
      }

      var result1 = ""
      try editor.read {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        let fmt = t.getFormat()
        result1 = "sub:\(fmt.subScript),super:\(fmt.superScript)"
      }

      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }

        var superFormat = TextFormat()
        superFormat.superScript = true
        try t.setFormat(format: superFormat)
      }

      var result2 = ""
      try editor.read {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        let fmt = t.getFormat()
        result2 = "sub:\(fmt.subScript),super:\(fmt.superScript)"
      }

      return "\(result1)|\(result2)"
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult, iosResult, "Subscript/superscript behavior should match")
  }

  // MARK: - Text Manipulation Edge Cases

  func testParity_SetTextWithEmptyString() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> String {
      try setupBasicDocument(editor: editor)

      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        try t.setText("")
      }

      var content = ""
      try editor.read {
        content = getRoot()?.getTextContent() ?? ""
      }
      return content
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult, iosResult, "Empty setText should match")
    XCTAssertEqual(macResult, "")
  }

  func testParity_SpliceEntireText() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> String {
      try setupBasicDocument(editor: editor)

      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }
        let length = t.getTextPart().count
        try t.spliceText(offset: 0, delCount: length, newText: "Replaced", moveSelection: false)
      }

      var content = ""
      try editor.read {
        content = getRoot()?.getTextContent() ?? ""
      }
      return content
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult, iosResult, "Splice entire text should match")
    XCTAssertEqual(macResult, "Replaced")
  }

  func testParity_MultipleTextNodesInParagraph() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> String {
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        let t1 = createTextNode(text: "First")
        let t2 = createTextNode(text: "Second")
        let t3 = createTextNode(text: "Third")
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

    XCTAssertEqual(macResult, iosResult, "Multiple text nodes should match")
    XCTAssertEqual(macResult, "FirstSecondThird")
  }

  // MARK: - Paragraph Manipulation Advanced

  func testParity_InsertMultipleParagraphs() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> Int {
      try editor.update {
        guard let root = getRoot() else { return }
        for i in 1...5 {
          let p = createParagraphNode()
          let t = createTextNode(text: "Para \(i)")
          try p.append([t])
          try root.append([p])
        }
      }

      var count = 0
      try editor.read {
        count = getRoot()?.getChildren().count ?? 0
      }
      return count
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult, iosResult, "Multiple paragraph insertion should match")
    XCTAssertEqual(macResult, 5)
  }

  func testParity_RemoveMiddleParagraph() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> String {
      try editor.update {
        guard let root = getRoot() else { return }
        for i in 1...3 {
          let p = createParagraphNode()
          let t = createTextNode(text: "P\(i)")
          try p.append([t])
          try root.append([p])
        }
      }

      try editor.update {
        guard let root = getRoot(),
              let middle = root.getChildren()[1] as? ParagraphNode else { return }
        try middle.remove()
      }

      var content = ""
      try editor.read {
        content = getRoot()?.getTextContent() ?? ""
      }
      return content
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult, iosResult, "Remove middle paragraph should match")
    XCTAssertEqual(macResult, "P1P3")
  }

  func testParity_ParagraphInsertBefore() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> String {
      try setupBasicDocument(editor: editor)

      try editor.update {
        guard let root = getRoot(),
              let existing = root.getFirstChild() as? ParagraphNode else { return }

        let newP = createParagraphNode()
        let newT = createTextNode(text: "Before")
        try newP.append([newT])
        try existing.insertBefore(nodeToInsert: newP)
      }

      var content = ""
      try editor.read {
        content = getRoot()?.getTextContent() ?? ""
      }
      return content
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult, iosResult, "Paragraph insertBefore should match")
    XCTAssertEqual(macResult, "BeforeHello World")
  }

  // MARK: - Selection State Tests

  func testParity_SelectionCollapsedState() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> String {
      try setupBasicDocument(editor: editor)

      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }

        try t.select(anchorOffset: 5, focusOffset: 5)
      }

      var isCollapsed = false
      try editor.read {
        if let sel = try getSelection() as? RangeSelection {
          isCollapsed = sel.isCollapsed()
        }
      }
      return "collapsed:\(isCollapsed)"
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult, iosResult, "Collapsed selection state should match")
    XCTAssertEqual(macResult, "collapsed:true")
  }

  func testParity_SelectionNotCollapsed() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> String {
      try setupBasicDocument(editor: editor)

      try editor.update {
        guard let root = getRoot(),
              let p = root.getFirstChild() as? ParagraphNode,
              let t = p.getFirstChild() as? TextNode else { return }

        try t.select(anchorOffset: 0, focusOffset: 5)
      }

      var isCollapsed = false
      try editor.read {
        if let sel = try getSelection() as? RangeSelection {
          isCollapsed = sel.isCollapsed()
        }
      }
      return "collapsed:\(isCollapsed)"
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult, iosResult, "Non-collapsed selection should match")
    XCTAssertEqual(macResult, "collapsed:false")
  }

  // MARK: - Error Handling Tests

  func testParity_InvalidSpliceOffset() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> String {
      try setupBasicDocument(editor: editor)

      var errorOccurred = false
      do {
        try editor.update {
          guard let root = getRoot(),
                let p = root.getFirstChild() as? ParagraphNode,
                let t = p.getFirstChild() as? TextNode else { return }
          try t.spliceText(offset: 1000, delCount: 0, newText: "X", moveSelection: false)
        }
      } catch {
        errorOccurred = true
      }

      return "error:\(errorOccurred)"
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult, iosResult, "Invalid splice error handling should match")
  }

  // MARK: - Performance Baseline Tests

  func testParity_LargeTextInsertion() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> Int {
      let largeText = String(repeating: "Lorem ipsum dolor sit amet. ", count: 100)

      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        let t = createTextNode(text: largeText)
        try p.append([t])
        try root.append([p])
      }

      var length = 0
      try editor.read {
        length = getRoot()?.getTextContent().count ?? 0
      }
      return length
    }

    let macResult = try scenario(editor: macOS)
    let iosResult = try scenario(editor: iOS)

    XCTAssertEqual(macResult, iosResult, "Large text insertion should match")
  }

  func testParity_ManySmallUpdates() throws {
    let (macOS, iOS) = makeEditors()

    func scenario(editor: Editor) throws -> String {
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        let t = createTextNode(text: "")
        try p.append([t])
        try root.append([p])
      }

      for i in 1...20 {
        try editor.update {
          guard let root = getRoot(),
                let p = root.getFirstChild() as? ParagraphNode,
                let t = p.getFirstChild() as? TextNode else { return }
          let current = t.getTextPart()
          try t.setText(current + "\(i)")
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

    XCTAssertEqual(macResult, iosResult, "Many small updates should match")
  }
}
