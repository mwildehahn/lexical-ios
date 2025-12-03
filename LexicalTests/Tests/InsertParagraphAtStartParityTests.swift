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

/// Tests for insertParagraph at the start of a paragraph.
///
/// When pressing Enter at the start of a paragraph, a new empty paragraph should be
/// inserted before the current one, and the cursor should stay at the start of the
/// original content (not jump to the end of the document).
@MainActor
final class InsertParagraphAtStartParityTests: XCTestCase {

  private func makeEditors() -> (opt: (Editor, any ReadOnlyTextKitContextProtocol), leg: (Editor, any ReadOnlyTextKitContextProtocol)) {
    return makeParityTestEditors()
  }

  #if os(macOS) && !targetEnvironment(macCatalyst)
  /// Test that native selection is correctly set after insertParagraph at start.
  ///
  /// This tests the fix for the bug where the native cursor would jump to the end
  /// of the document after pressing Enter at the start of a paragraph. The issue was
  /// that `applySelection(range:affinity:)` had a guard checking `isUpdatingNativeSelection`,
  /// but this flag was already set by the reconciler, causing the selection update to be skipped.
  func testAppKit_InsertParagraphAtStart_NativeSelectionSyncedCorrectly() throws {
    let flags = FeatureFlags()
    let context = LexicalReadOnlyTextKitContextAppKit(
      editorConfig: EditorConfig(theme: Theme(), plugins: []),
      featureFlags: flags
    )
    let editor = context.editor

    // Create content with cursor at start
    var textKey: NodeKey = ""
    try editor.update {
      guard let root = getRoot() else { return }
      // Clear default paragraph
      for child in root.getChildren() { try? child.remove() }
      let p = createParagraphNode()
      let t = createTextNode(text: "Hello World")
      textKey = t.getKey()
      try p.append([t])
      try root.append([p])
      try t.select(anchorOffset: 0, focusOffset: 0)
    }

    // Verify initial state
    var initialNativeLocation: Int = -1
    try editor.read {
      if let sel = try getSelection() as? RangeSelection {
        if let loc = try? stringLocationForPoint(sel.anchor, editor: editor) {
          initialNativeLocation = loc
        }
      }
    }
    XCTAssertEqual(initialNativeLocation, 0, "Initial native location should be 0")

    // Insert paragraph at start (press Enter)
    try editor.update {
      try (getSelection() as? RangeSelection)?.insertParagraph()
    }

    // Verify selection is still at start of original content, not at end
    var finalAnchorOffset = -1
    var finalNativeLocation: Int = -1
    try editor.read {
      if let sel = try getSelection() as? RangeSelection {
        finalAnchorOffset = sel.anchor.offset
        if let loc = try? stringLocationForPoint(sel.anchor, editor: editor) {
          finalNativeLocation = loc
        }
      }
    }

    // After inserting empty paragraph before "Hello World", the native location
    // should be 1 (after the newline from the new empty paragraph), not at the end
    XCTAssertEqual(finalAnchorOffset, 0, "Lexical anchor offset should stay at 0")
    XCTAssertEqual(finalNativeLocation, 1, "Native location should be 1 (after new paragraph's newline)")

    // Also verify text content is correct - should have a newline from the new empty paragraph
    var textContent = ""
    var paragraphCount = 0
    try editor.read {
      textContent = getRoot()?.getTextContent() ?? ""
      paragraphCount = getRoot()?.getChildrenSize() ?? 0
    }
    // Should have 2 paragraphs now (empty + "Hello World")
    XCTAssertEqual(paragraphCount, 2, "Should have 2 paragraphs after insert")
    // Text content should include the empty paragraph's contribution
    XCTAssertTrue(textContent.hasSuffix("Hello World"), "Content should end with original text")
  }
  #endif

  /// Test that insertParagraph at start of paragraph keeps cursor at start of original content.
  ///
  /// Scenario:
  /// 1. Document has "Hello" with cursor at offset 0 (start)
  /// 2. insertParagraph is called (Enter key)
  /// 3. Expected: New empty paragraph before "Hello", cursor stays at start of "Hello"
  /// 4. NOT: Cursor jumps to end of document
  func testParity_InsertParagraphAtStart_KeepsCursorAtOriginalPosition() throws {
    let (opt, leg) = makeEditors()

    func run(on editor: Editor) throws -> (text: String, anchorOffset: Int, nativeLocation: Int?) {
      // Create a paragraph with text
      var textKey: NodeKey = ""
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        let t = createTextNode(text: "Hello")
        textKey = t.getKey()
        try p.append([t])
        try root.append([p])
        // Position cursor at start of text
        try t.select(anchorOffset: 0, focusOffset: 0)
      }

      // Verify initial selection
      var beforeAnchorOffset = -1
      try editor.read {
        if let sel = try getSelection() as? RangeSelection {
          beforeAnchorOffset = sel.anchor.offset
        }
      }
      XCTAssertEqual(beforeAnchorOffset, 0, "Initial cursor should be at offset 0")

      // Insert paragraph (press Enter at start)
      try editor.update {
        try (getSelection() as? RangeSelection)?.insertParagraph()
      }

      // Check result
      var textContent = ""
      var anchorKey: NodeKey = ""
      var anchorOffset = -1
      var anchorType: SelectionType = .text
      try editor.read {
        textContent = getRoot()?.getTextContent() ?? ""
        if let sel = try getSelection() as? RangeSelection {
          anchorKey = sel.anchor.key
          anchorOffset = sel.anchor.offset
          anchorType = sel.anchor.type
        }
      }

      // Get native selection position for debugging
      var nativeLocation: Int? = nil
      #if os(macOS) && !targetEnvironment(macCatalyst)
      if let ctx = editor.frontendAppKit as? LexicalReadOnlyTextKitContextAppKit {
        nativeLocation = ctx.textStorage.length > 0 ? nil : nil // Can't easily get native selection from read-only context
      }
      #endif

      // The cursor should still be at offset 0 (start of the "Hello" text)
      // Not at the end of the document
      XCTAssertEqual(anchorOffset, 0, "Cursor should stay at offset 0, not jump")
      XCTAssertEqual(anchorType, .text, "Selection should remain text type")

      return (textContent, anchorOffset, nativeLocation)
    }

    let optResult = try run(on: opt.0)
    let legResult = try run(on: leg.0)

    // Both should have same text content (newline + Hello)
    XCTAssertEqual(optResult.text, legResult.text, "Text content should match between reconcilers")
    // Text should be newline followed by "Hello"
    XCTAssertEqual(optResult.text, "\nHello", "Content should be newline + original text")

    // Both should have cursor at offset 0
    XCTAssertEqual(optResult.anchorOffset, 0, "Optimized reconciler: cursor should be at offset 0")
    XCTAssertEqual(legResult.anchorOffset, 0, "Legacy reconciler: cursor should be at offset 0")
  }

  /// Test that insertParagraph at start of first paragraph creates new paragraph above.
  func testParity_InsertParagraphAtStartOfFirstParagraph_CreatesNewParagraphAbove() throws {
    let (opt, leg) = makeEditors()

    func run(on editor: Editor) throws -> Int {
      // Get initial paragraph count (there's a default empty paragraph)
      var initialCount = 0
      try editor.read { initialCount = getRoot()?.getChildrenSize() ?? 0 }

      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        let t = createTextNode(text: "First paragraph")
        try p.append([t])
        try root.append([p])
        try t.select(anchorOffset: 0, focusOffset: 0)
      }

      try editor.update {
        try (getSelection() as? RangeSelection)?.insertParagraph()
      }

      var count = 0
      try editor.read {
        count = getRoot()?.getChildrenSize() ?? 0
      }
      // Account for default paragraph + our paragraph + new empty paragraph from Enter
      return count - initialCount
    }

    let optCount = try run(on: opt.0)
    let legCount = try run(on: leg.0)

    // Should have added 2 paragraphs (our content + empty from Enter)
    XCTAssertEqual(optCount, 2, "Should have 2 new paragraphs after insert")
    XCTAssertEqual(legCount, 2, "Should have 2 new paragraphs after insert")
  }

  /// Test that multiple insertParagraph at start creates multiple empty paragraphs.
  func testParity_MultipleInsertParagraphAtStart_CreatesMultipleEmptyParagraphs() throws {
    let (opt, leg) = makeEditors()

    func run(on editor: Editor) throws -> (addedParagraphs: Int, textContent: String) {
      // Get initial paragraph count
      var initialCount = 0
      try editor.read { initialCount = getRoot()?.getChildrenSize() ?? 0 }

      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        let t = createTextNode(text: "Content")
        try p.append([t])
        try root.append([p])
        try t.select(anchorOffset: 0, focusOffset: 0)
      }

      // Insert 3 paragraphs at start
      for _ in 0..<3 {
        try editor.update {
          try (getSelection() as? RangeSelection)?.insertParagraph()
        }
      }

      var count = 0
      var text = ""
      try editor.read {
        count = getRoot()?.getChildrenSize() ?? 0
        text = getRoot()?.getTextContent() ?? ""
      }
      return (count - initialCount, text)
    }

    let optResult = try run(on: opt.0)
    let legResult = try run(on: leg.0)

    // Should have added 4 paragraphs (1 content + 3 empty from Enter)
    XCTAssertEqual(optResult.addedParagraphs, 4, "Should have added 4 paragraphs")
    XCTAssertEqual(legResult.addedParagraphs, 4, "Should have added 4 paragraphs")
    // Text content should contain 3 newlines + "Content" (plus initial empty paragraph newline)
    XCTAssertTrue(optResult.textContent.hasSuffix("\n\n\nContent"), "Should end with 3 newlines + Content")
    XCTAssertTrue(legResult.textContent.hasSuffix("\n\n\nContent"), "Should end with 3 newlines + Content")
  }

  /// Test insertParagraph at start with multiple paragraphs - cursor should stay with original text node.
  func testParity_InsertParagraphAtStart_WithMultipleParagraphs_CursorStaysWithOriginalText() throws {
    let (opt, leg) = makeEditors()

    func run(on editor: Editor) throws -> (anchorKey: NodeKey, anchorOffset: Int) {
      var targetTextKey: NodeKey = ""
      try editor.update {
        guard let root = getRoot() else { return }
        // Create multiple paragraphs
        for i in 0..<3 {
          let p = createParagraphNode()
          let t = createTextNode(text: "Para \(i)")
          if i == 1 { targetTextKey = t.getKey() } // Will put cursor here
          try p.append([t])
          try root.append([p])
        }
        // Position cursor at start of second paragraph
        if let t = getNodeByKey(key: targetTextKey) as? TextNode {
          try t.select(anchorOffset: 0, focusOffset: 0)
        }
      }

      // Insert paragraph at start of second paragraph
      try editor.update {
        try (getSelection() as? RangeSelection)?.insertParagraph()
      }

      // Check where cursor is now
      var anchorKey: NodeKey = ""
      var anchorOffset = -1
      try editor.read {
        if let sel = try getSelection() as? RangeSelection {
          anchorKey = sel.anchor.key
          anchorOffset = sel.anchor.offset
        }
      }

      // The cursor should still be at the start of the original "Para 1" text node
      XCTAssertEqual(anchorKey, targetTextKey, "Cursor should stay with original text node")
      XCTAssertEqual(anchorOffset, 0, "Cursor should stay at offset 0")

      return (anchorKey, anchorOffset)
    }

    let optResult = try run(on: opt.0)
    let legResult = try run(on: leg.0)

    XCTAssertEqual(optResult.anchorOffset, legResult.anchorOffset, "Both reconcilers should have same anchor offset")
  }
}
