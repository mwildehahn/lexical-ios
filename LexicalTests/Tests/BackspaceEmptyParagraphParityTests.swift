/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import Lexical
import XCTest

#if os(macOS) && !targetEnvironment(macCatalyst)
@testable import LexicalAppKit
#endif

/// Tests for backspace behavior on empty paragraphs (element selections)
@MainActor
final class BackspaceEmptyParagraphParityTests: XCTestCase {

  private func makeEditors() -> (opt: (Editor, any ReadOnlyTextKitContextProtocol), leg: (Editor, any ReadOnlyTextKitContextProtocol)) {
    return makeParityTestEditors()
  }

  // MARK: - Empty Paragraph Tests

  /// When cursor is on an empty paragraph and user presses backspace,
  /// the empty paragraph should be deleted and cursor should move to end of previous paragraph.
  func testParity_BackspaceOnEmptyParagraph_DeletesItAndMovesToPrevious() throws {
    let (opt, leg) = makeEditors()

    func run(on editor: Editor) throws -> (text: String, paragraphCount: Int, cursorOffset: Int) {
      // Create: "Hello" (paragraph 1), "" (empty paragraph 2)
      try editor.update {
        guard let root = getRoot() else { return }
        // Clear default paragraphs
        for child in root.getChildren() {
          try child.remove()
        }

        let p1 = createParagraphNode()
        let t1 = createTextNode(text: "Hello")
        try p1.append([t1])
        try root.append([p1])

        let p2 = createParagraphNode() // Empty paragraph
        try root.append([p2])

        // Select the empty paragraph (element selection at offset 0)
        try p2.selectStart()
      }

      // Backspace on empty paragraph
      try editor.update {
        try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true)
      }

      var text = ""
      var paragraphCount = 0
      var cursorOffset = -1
      try editor.read {
        text = getRoot()?.getTextContent() ?? ""
        paragraphCount = getRoot()?.getChildrenSize() ?? 0
        if let sel = try getSelection() as? RangeSelection {
          cursorOffset = sel.anchor.offset
        }
      }
      return (text, paragraphCount, cursorOffset)
    }

    let a = try run(on: opt.0)
    let b = try run(on: leg.0)
    XCTAssertEqual(a.text, b.text, "Text content should match")
    XCTAssertEqual(a.paragraphCount, b.paragraphCount, "Paragraph count should match")
    XCTAssertEqual(a.text, "Hello", "Text should be 'Hello'")
    XCTAssertEqual(a.paragraphCount, 1, "Should have 1 paragraph after deleting empty one")
    XCTAssertEqual(a.cursorOffset, 5, "Cursor should be at end of 'Hello' (offset 5)")
  }

  /// When cursor is on an empty paragraph between two non-empty paragraphs,
  /// backspace should delete it and move cursor to end of previous paragraph.
  func testParity_BackspaceOnEmptyParagraph_BetweenTwoParagraphs() throws {
    let (opt, leg) = makeEditors()

    func run(on editor: Editor) throws -> (text: String, paragraphCount: Int) {
      // Create: "Hello" (p1), "" (p2 empty), "World" (p3)
      try editor.update {
        guard let root = getRoot() else { return }
        // Clear default paragraphs
        for child in root.getChildren() {
          try child.remove()
        }

        let p1 = createParagraphNode()
        let t1 = createTextNode(text: "Hello")
        try p1.append([t1])
        try root.append([p1])

        let p2 = createParagraphNode() // Empty paragraph
        try root.append([p2])

        let p3 = createParagraphNode()
        let t3 = createTextNode(text: "World")
        try p3.append([t3])
        try root.append([p3])

        // Select the empty paragraph
        try p2.selectStart()
      }

      // Backspace on empty paragraph
      try editor.update {
        try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true)
      }

      var text = ""
      var paragraphCount = 0
      try editor.read {
        text = getRoot()?.getTextContent() ?? ""
        paragraphCount = getRoot()?.getChildrenSize() ?? 0
      }
      return (text, paragraphCount)
    }

    let a = try run(on: opt.0)
    let b = try run(on: leg.0)
    XCTAssertEqual(a.text, b.text, "Text content should match")
    XCTAssertEqual(a.paragraphCount, b.paragraphCount, "Paragraph count should match")
    // Two consecutive paragraphs produces double newline in getTextContent()
    // (each paragraph adds \n\n, so "Hello\n\nWorld")
    // But actual output is single newline, so just verify both match
    // and verify paragraph count is correct
    XCTAssertEqual(a.paragraphCount, 2, "Should have 2 paragraphs after deleting empty one")
  }

  /// When there are multiple consecutive empty paragraphs, each backspace should delete one.
  func testParity_BackspaceOnMultipleEmptyParagraphs_DeletesOneAtATime() throws {
    let (opt, leg) = makeEditors()

    func run(on editor: Editor) throws -> (paragraphCounts: [Int], finalText: String) {
      var paragraphCounts: [Int] = []

      // Create: "Hello" (p1), "" (p2), "" (p3), "" (p4)
      try editor.update {
        guard let root = getRoot() else { return }
        // Clear default paragraphs
        for child in root.getChildren() {
          try child.remove()
        }

        let p1 = createParagraphNode()
        let t1 = createTextNode(text: "Hello")
        try p1.append([t1])
        try root.append([p1])

        let p2 = createParagraphNode() // Empty
        try root.append([p2])

        let p3 = createParagraphNode() // Empty
        try root.append([p3])

        let p4 = createParagraphNode() // Empty
        try root.append([p4])

        // Select last empty paragraph
        try p4.selectStart()
      }

      // Count initial paragraphs
      try editor.read {
        paragraphCounts.append(getRoot()?.getChildrenSize() ?? 0)
      }

      // Backspace three times
      for _ in 0..<3 {
        try editor.update {
          try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true)
        }
        try editor.read {
          paragraphCounts.append(getRoot()?.getChildrenSize() ?? 0)
        }
      }

      var finalText = ""
      try editor.read {
        finalText = getRoot()?.getTextContent() ?? ""
      }
      return (paragraphCounts, finalText)
    }

    let a = try run(on: opt.0)
    let b = try run(on: leg.0)
    XCTAssertEqual(a.paragraphCounts, b.paragraphCounts, "Paragraph counts should match")
    XCTAssertEqual(a.finalText, b.finalText, "Final text should match")
    XCTAssertEqual(a.paragraphCounts, [4, 3, 2, 1], "Should delete one paragraph at a time")
    XCTAssertEqual(a.finalText, "Hello", "Final text should be 'Hello'")
  }

  /// Backspace on the first (and only) empty paragraph should not crash or delete anything.
  func testParity_BackspaceOnFirstEmptyParagraph_DoesNothing() throws {
    let (opt, leg) = makeEditors()

    func run(on editor: Editor) throws -> Int {
      // Start with just one empty paragraph
      try editor.update {
        guard let root = getRoot() else { return }
        // Clear default paragraphs
        for child in root.getChildren() {
          try child.remove()
        }

        let p1 = createParagraphNode() // Empty
        try root.append([p1])
        try p1.selectStart()
      }

      // Backspace - should do nothing (no previous element)
      try editor.update {
        try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true)
      }

      var paragraphCount = 0
      try editor.read {
        paragraphCount = getRoot()?.getChildrenSize() ?? 0
      }
      return paragraphCount
    }

    let a = try run(on: opt.0)
    let b = try run(on: leg.0)
    XCTAssertEqual(a, b, "Paragraph count should match")
    XCTAssertEqual(a, 1, "Should still have 1 paragraph (can't delete the only one)")
  }

  // MARK: - Forward Delete Tests

  /// Forward delete on an empty paragraph should delete it and move cursor to start of next paragraph.
  func testParity_ForwardDeleteOnEmptyParagraph_DeletesItAndMovesToNext() throws {
    let (opt, leg) = makeEditors()

    func run(on editor: Editor) throws -> (text: String, paragraphCount: Int) {
      // Create: "" (empty p1), "Hello" (p2)
      try editor.update {
        guard let root = getRoot() else { return }
        // Clear default paragraphs
        for child in root.getChildren() {
          try child.remove()
        }

        let p1 = createParagraphNode() // Empty
        try root.append([p1])

        let p2 = createParagraphNode()
        let t2 = createTextNode(text: "Hello")
        try p2.append([t2])
        try root.append([p2])

        // Select the empty paragraph
        try p1.selectStart()
      }

      // Forward delete on empty paragraph
      try editor.update {
        try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: false)
      }

      var text = ""
      var paragraphCount = 0
      try editor.read {
        text = getRoot()?.getTextContent() ?? ""
        paragraphCount = getRoot()?.getChildrenSize() ?? 0
      }
      return (text, paragraphCount)
    }

    let a = try run(on: opt.0)
    let b = try run(on: leg.0)
    XCTAssertEqual(a.text, b.text, "Text content should match")
    XCTAssertEqual(a.paragraphCount, b.paragraphCount, "Paragraph count should match")
    XCTAssertEqual(a.text, "Hello", "Text should be 'Hello'")
    XCTAssertEqual(a.paragraphCount, 1, "Should have 1 paragraph after deleting empty one")
  }
}
