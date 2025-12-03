/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import XCTest
@testable import Lexical

#if os(macOS) && !targetEnvironment(macCatalyst)
@testable import LexicalAppKit

/// Tests for native selection to Lexical selection synchronization.
///
/// These tests verify that when the native NSTextView selection changes,
/// the Lexical selection is properly updated to match.
@MainActor
final class NativeSelectionSyncParityTests: XCTestCase {

  /// Test that changing native selection updates Lexical selection.
  ///
  /// This test reproduces a bug where `pointAtStringLocation` is called
  /// outside of `editor.read {}`, causing the conversion to fail because
  /// `getNodeByKey` requires an active Lexical context.
  func testNativeSelectionChangeUpdatesLexicalSelection() throws {
    // Create a test editor view
    let testView = createTestEditorView()
    let editor = testView.editor
    let lexicalView = testView.view

    // Add some content: "Hello World"
    var textNodeKey: NodeKey = ""
    try editor.update {
      guard let root = getRoot() else { return }
      let paragraph = createParagraphNode()
      let textNode = createTextNode(text: "Hello World")
      textNodeKey = textNode.getKey()
      try paragraph.append([textNode])
      try root.append([paragraph])

      // Set initial selection at end of text
      _ = try textNode.select(anchorOffset: 11, focusOffset: 11)
    }

    // Verify initial Lexical selection is at position 11 (end of "Hello World")
    var initialAnchorOffset = -1
    var initialFocusOffset = -1
    try editor.read {
      guard let selection = try getSelection() as? RangeSelection else {
        XCTFail("Expected RangeSelection")
        return
      }
      initialAnchorOffset = selection.anchor.offset
      initialFocusOffset = selection.focus.offset
    }
    XCTAssertEqual(initialAnchorOffset, 11, "Initial anchor should be at 11")
    XCTAssertEqual(initialFocusOffset, 11, "Initial focus should be at 11")

    // Get the actual native string to find "Hello" position
    let nativeString = testView.attributedTextString as NSString
    let helloRange = nativeString.range(of: "Hello")
    XCTAssertNotEqual(helloRange.location, NSNotFound, "Should find 'Hello' in native text")

    // Native position right after "Hello" (accounting for any prefix characters)
    let nativePositionAfterHello = helloRange.location + helloRange.length
    let newRange = NSRange(location: nativePositionAfterHello, length: 0)
    lexicalView.textView.setSelectedRange(newRange)

    // Trigger the selection change handler
    lexicalView.textView.handleSelectionChange()

    // Verify Lexical selection was updated to match native selection
    var updatedAnchorKey: NodeKey = ""
    var updatedAnchorOffset = -1
    var updatedFocusOffset = -1
    try editor.read {
      guard let selection = try getSelection() as? RangeSelection else {
        XCTFail("Expected RangeSelection after native selection change")
        return
      }
      updatedAnchorKey = selection.anchor.key
      updatedAnchorOffset = selection.anchor.offset
      updatedFocusOffset = selection.focus.offset
    }

    // The selection should now be at position 5 (after "Hello"), not still at 11
    XCTAssertEqual(updatedAnchorKey, textNodeKey, "Selection should be in text node")
    XCTAssertEqual(updatedAnchorOffset, 5, "Anchor offset should be updated to 5")
    XCTAssertEqual(updatedFocusOffset, 5, "Focus offset should be updated to 5")
  }

  /// Test that selecting a range in native view updates Lexical selection.
  func testNativeRangeSelectionUpdatesLexicalSelection() throws {
    let testView = createTestEditorView()
    let editor = testView.editor
    let lexicalView = testView.view

    // Add content
    try editor.update {
      guard let root = getRoot() else { return }
      let paragraph = createParagraphNode()
      let textNode = createTextNode(text: "Hello World")
      try paragraph.append([textNode])
      try root.append([paragraph])

      // Set initial collapsed selection
      _ = try textNode.select(anchorOffset: 0, focusOffset: 0)
    }

    // Get the actual native string to find "Hello" position
    let nativeString = testView.attributedTextString as NSString
    let helloRange = nativeString.range(of: "Hello")
    XCTAssertNotEqual(helloRange.location, NSNotFound, "Should find 'Hello' in native text")

    // Select "Hello" in native view
    lexicalView.textView.setSelectedRange(helloRange)
    lexicalView.textView.handleSelectionChange()

    // Verify Lexical selection matches - anchor at 0, focus at 5 (selecting "Hello")
    var anchorOffset = -1
    var focusOffset = -1
    try editor.read {
      guard let selection = try getSelection() as? RangeSelection else {
        XCTFail("Expected RangeSelection")
        return
      }
      anchorOffset = selection.anchor.offset
      focusOffset = selection.focus.offset
    }

    XCTAssertEqual(anchorOffset, 0, "Anchor should be at start of 'Hello'")
    XCTAssertEqual(focusOffset, 5, "Focus should be at end of 'Hello'")
  }

  /// Test that backspace with a range selection deletes the selected text.
  ///
  /// This test verifies that when text is selected in the native view and backspace
  /// is pressed, the entire selection is deleted (not just a single character).
  func testBackspaceDeletesSelectedRange() throws {
    let testView = createTestEditorView()
    let editor = testView.editor
    let lexicalView = testView.view

    // Add content: "Hello World"
    try editor.update {
      guard let root = getRoot() else { return }
      let paragraph = createParagraphNode()
      let textNode = createTextNode(text: "Hello World")
      try paragraph.append([textNode])
      try root.append([paragraph])

      // Initial cursor at end
      _ = try textNode.select(anchorOffset: 11, focusOffset: 11)
    }

    // Find "World" in native string and select it
    let nativeString = testView.attributedTextString as NSString
    let worldRange = nativeString.range(of: "World")
    XCTAssertNotEqual(worldRange.location, NSNotFound)

    // Select "World"
    lexicalView.textView.setSelectedRange(worldRange)
    lexicalView.textView.handleSelectionChange()

    // Verify selection is now "World" (length 5)
    var anchorOffset = -1
    var focusOffset = -1
    try editor.read {
      guard let selection = try getSelection() as? RangeSelection else {
        XCTFail("Expected RangeSelection")
        return
      }
      anchorOffset = selection.anchor.offset
      focusOffset = selection.focus.offset
    }
    XCTAssertEqual(focusOffset - anchorOffset, 5, "Selection should span 'World' (5 chars)")

    // Now dispatch backspace command
    editor.dispatchCommand(type: .deleteCharacter, payload: true)

    // Verify "World" is deleted, "Hello " remains
    let finalString = testView.attributedTextString
    XCTAssertTrue(finalString.contains("Hello"), "Should still have 'Hello'")
    XCTAssertFalse(finalString.contains("World"), "'World' should be deleted")
  }

  /// Test that repeated select-and-backspace operations work correctly.
  ///
  /// This reproduces a bug where "selecting text + backspace doesn't delete consistently
  /// (works first time, then only deletes single character)".
  func testRepeatedSelectAndBackspace() throws {
    let testView = createTestEditorView()
    let editor = testView.editor
    let lexicalView = testView.view

    // Add content: "AAABBBCCC"
    try editor.update {
      guard let root = getRoot() else { return }
      let paragraph = createParagraphNode()
      let textNode = createTextNode(text: "AAABBBCCC")
      try paragraph.append([textNode])
      try root.append([paragraph])
    }

    // First deletion: Select "BBB" and delete
    var nativeString = testView.attributedTextString as NSString
    var bbbRange = nativeString.range(of: "BBB")
    XCTAssertNotEqual(bbbRange.location, NSNotFound, "Should find 'BBB'")

    lexicalView.textView.setSelectedRange(bbbRange)
    lexicalView.textView.handleSelectionChange()
    editor.dispatchCommand(type: .deleteCharacter, payload: true)

    // Verify "BBB" is deleted
    var afterFirst = testView.attributedTextString
    XCTAssertFalse(afterFirst.contains("BBB"), "'BBB' should be deleted after first backspace")
    XCTAssertTrue(afterFirst.contains("AAA"), "'AAA' should remain")
    XCTAssertTrue(afterFirst.contains("CCC"), "'CCC' should remain")

    // Second deletion: Select "CCC" and delete
    nativeString = testView.attributedTextString as NSString
    let cccRange = nativeString.range(of: "CCC")
    XCTAssertNotEqual(cccRange.location, NSNotFound, "Should find 'CCC'")

    lexicalView.textView.setSelectedRange(cccRange)
    lexicalView.textView.handleSelectionChange()
    editor.dispatchCommand(type: .deleteCharacter, payload: true)

    // Verify "CCC" is also deleted (not just single character)
    let afterSecond = testView.attributedTextString
    XCTAssertFalse(afterSecond.contains("CCC"), "'CCC' should be deleted after second backspace")
    XCTAssertTrue(afterSecond.contains("AAA"), "'AAA' should remain")
  }

  /// Test that native selection change with multiple paragraphs works correctly.
  ///
  /// Note: Adjacent text nodes in the same paragraph may have range cache issues
  /// that are separate from the main selection sync bug. This test uses separate
  /// paragraphs to avoid that complexity.
  func testNativeSelectionWithMultipleParagraphs() throws {
    let testView = createTestEditorView()
    let editor = testView.editor
    let lexicalView = testView.view

    // Add content with two paragraphs: "Hello" and "World"
    var worldKey: NodeKey = ""
    try editor.update {
      guard let root = getRoot() else { return }
      let p1 = createParagraphNode()
      let p2 = createParagraphNode()
      let hello = createTextNode(text: "Hello")
      let world = createTextNode(text: "World")
      worldKey = world.getKey()
      try p1.append([hello])
      try p2.append([world])
      try root.append([p1, p2])

      // Initial selection at start of first paragraph
      _ = try hello.select(anchorOffset: 0, focusOffset: 0)
    }

    // Get the actual native string to find "World" position
    let nativeString = testView.attributedTextString as NSString
    let worldRange = nativeString.range(of: "World")
    XCTAssertNotEqual(worldRange.location, NSNotFound, "Should find 'World' in native text")

    // Select position 2 characters into "World"
    let nativePosition = worldRange.location + 2
    let newRange = NSRange(location: nativePosition, length: 0)
    lexicalView.textView.setSelectedRange(newRange)
    lexicalView.textView.handleSelectionChange()

    // Verify selection moved to the second paragraph's text node
    var anchorKey: NodeKey = ""
    var anchorOffset = -1
    try editor.read {
      guard let selection = try getSelection() as? RangeSelection else {
        XCTFail("Expected RangeSelection")
        return
      }
      anchorKey = selection.anchor.key
      anchorOffset = selection.anchor.offset
    }

    XCTAssertEqual(anchorKey, worldKey, "Selection should be in 'World' text node")
    XCTAssertEqual(anchorOffset, 2, "Offset should be 2 within 'World' node")
  }
}



#endif // os(macOS) && !targetEnvironment(macCatalyst)
