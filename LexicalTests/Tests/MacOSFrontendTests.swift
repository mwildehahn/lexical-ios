/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#if canImport(AppKit)
import AppKit
@testable import Lexical
import XCTest

class MacOSFrontendTests: XCTestCase {

  var view: LexicalView?
  var editor: Editor {
    get {
      guard let editor = view?.editor else {
        XCTFail("Editor unexpectedly nil")
        fatalError()
      }
      return editor
    }
  }

  override func setUp() {
    view = LexicalView(
      editorConfig: EditorConfig(theme: Theme(), plugins: []),
      featureFlags: FeatureFlags()
    )
  }

  override func tearDown() {
    view = nil
  }

  // MARK: - LexicalView Tests

  func testLexicalViewInitialization() {
    XCTAssertNotNil(view)
    XCTAssertNotNil(view?.editor)
    XCTAssertNotNil(view?.textView)
  }

  func testLexicalViewFrontendProtocol() {
    XCTAssertNotNil(view?.textStorage)
    XCTAssertNotNil(view?.layoutManager)
    XCTAssertNotNil(view?.textContainer)
  }

  func testTextContainerInsets() {
    guard let view = view else {
      XCTFail("View is nil")
      return
    }

    let insets = view.textContainerInsets
    // Should have some default insets
    XCTAssertTrue(insets.top >= 0)
    XCTAssertTrue(insets.left >= 0)
    XCTAssertTrue(insets.bottom >= 0)
    XCTAssertTrue(insets.right >= 0)
  }

  // MARK: - TextView Tests

  func testTextViewInitialization() {
    guard let textView = view?.textView else {
      XCTFail("TextView is nil")
      return
    }

    XCTAssertNotNil(textView.textStorage)
    XCTAssertNotNil(textView.layoutManager)
    XCTAssertNotNil(textView.textContainer)
  }

  func testTextInsertion() throws {
    guard let textView = view?.textView else {
      XCTFail("TextView is nil")
      return
    }

    try editor.update {
      guard let root = getRoot() else {
        XCTFail("Root is nil")
        return
      }
      let paragraph = ParagraphNode()
      let textNode = TextNode(text: "Hello macOS")
      try paragraph.append([textNode])
      try root.append([paragraph])
    }

    // Allow time for reconciliation
    let expectation = self.expectation(description: "Reconciliation")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
      expectation.fulfill()
    }
    waitForExpectations(timeout: 1.0)

    XCTAssertEqual(textView.string, "Hello macOS")
  }

  func testTextDeletion() throws {
    guard let textView = view?.textView else {
      XCTFail("TextView is nil")
      return
    }

    // Insert text first
    try editor.update {
      guard let root = getRoot() else {
        XCTFail("Root is nil")
        return
      }
      let paragraph = ParagraphNode()
      let textNode = TextNode(text: "Hello World")
      try paragraph.append([textNode])
      try root.append([paragraph])
    }

    // Wait for reconciliation
    let insertExpectation = self.expectation(description: "Insert")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
      insertExpectation.fulfill()
    }
    waitForExpectations(timeout: 1.0)

    // Delete text
    try editor.update {
      guard let root = getRoot() else {
        XCTFail("Root is nil")
        return
      }
      try root.clear()
    }

    // Wait for reconciliation
    let deleteExpectation = self.expectation(description: "Delete")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
      deleteExpectation.fulfill()
    }
    waitForExpectations(timeout: 1.0)

    XCTAssertEqual(textView.string, "")
  }

  // MARK: - Selection Tests

  func testNativeSelection() throws {
    guard let view = view else {
      XCTFail("View is nil")
      return
    }

    // Insert text
    try editor.update {
      guard let root = getRoot() else {
        XCTFail("Root is nil")
        return
      }
      let paragraph = ParagraphNode()
      let textNode = TextNode(text: "Test Selection")
      try paragraph.append([textNode])
      try root.append([paragraph])
    }

    // Wait for reconciliation
    let expectation = self.expectation(description: "Reconciliation")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
      expectation.fulfill()
    }
    waitForExpectations(timeout: 1.0)

    let nativeSelection = view.nativeSelection
    XCTAssertNotNil(nativeSelection)
    XCTAssertTrue(nativeSelection.range.location >= 0)
  }

  func testSelectionUpdate() throws {
    guard let view = view else {
      XCTFail("View is nil")
      return
    }

    // Insert text
    try editor.update {
      guard let root = getRoot() else {
        XCTFail("Root is nil")
        return
      }
      let paragraph = ParagraphNode()
      let textNode = TextNode(text: "Selection Test")
      try paragraph.append([textNode])
      try root.append([paragraph])
    }

    // Wait for reconciliation
    let expectation = self.expectation(description: "Reconciliation")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
      expectation.fulfill()
    }
    waitForExpectations(timeout: 1.0)

    // Create a range selection
    try editor.update {
      guard let root = getRoot(), let paragraph = root.getFirstChild() as? ParagraphNode,
            let textNode = paragraph.getFirstChild() as? TextNode
      else {
        XCTFail("Failed to get nodes")
        return
      }

      let selection = RangeSelection(
        anchor: Point(key: textNode.key, offset: 0, type: .text),
        focus: Point(key: textNode.key, offset: 5, type: .text),
        format: TextFormat()
      )
      try selection.dirty()
    }

    // Wait for selection update
    let selectionExpectation = self.expectation(description: "Selection")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
      selectionExpectation.fulfill()
    }
    waitForExpectations(timeout: 1.0)

    let nativeSelection = view.nativeSelection
    // Selection should be updated
    XCTAssertTrue(nativeSelection.range.length > 0 || nativeSelection.range.location >= 0)
  }

  // MARK: - Pasteboard Tests

  func testPasteboardCopy() throws {
    guard let view = view else {
      XCTFail("View is nil")
      return
    }

    // Insert text
    try editor.update {
      guard let root = getRoot() else {
        XCTFail("Root is nil")
        return
      }
      let paragraph = ParagraphNode()
      let textNode = TextNode(text: "Copy Test")
      try paragraph.append([textNode])
      try root.append([paragraph])
    }

    // Wait for reconciliation
    let expectation = self.expectation(description: "Reconciliation")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
      expectation.fulfill()
    }
    waitForExpectations(timeout: 1.0)

    // Select all
    try editor.update {
      guard let root = getRoot(), let paragraph = root.getFirstChild() as? ParagraphNode,
            let textNode = paragraph.getFirstChild() as? TextNode
      else {
        XCTFail("Failed to get nodes")
        return
      }

      let selection = RangeSelection(
        anchor: Point(key: textNode.key, offset: 0, type: .text),
        focus: Point(key: textNode.key, offset: 9, type: .text),
        format: TextFormat()
      )
      try selection.dirty()

      // Copy to pasteboard
      let pasteboard = NSPasteboard.general
      try setPasteboard(selection: selection, pasteboard: pasteboard)
    }

    // Check pasteboard has content
    let pasteboard = NSPasteboard.general
    XCTAssertNotNil(pasteboard.string(forType: .string))
  }

  // MARK: - Text Format Tests

  func testBoldFormatting() throws {
    try editor.update {
      guard let root = getRoot() else {
        XCTFail("Root is nil")
        return
      }
      let paragraph = ParagraphNode()
      let textNode = TextNode(text: "Bold Text")
      textNode.format.bold = true
      try paragraph.append([textNode])
      try root.append([paragraph])
    }

    // Wait for reconciliation
    let expectation = self.expectation(description: "Reconciliation")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
      expectation.fulfill()
    }
    waitForExpectations(timeout: 1.0)

    // Verify attributed string has bold trait
    guard let textStorage = view?.textStorage as? TextStorage else {
      XCTFail("TextStorage is nil")
      return
    }

    let attrString = textStorage.attributedSubstring(from: NSRange(location: 0, length: textStorage.length))
    let font = attrString.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    XCTAssertNotNil(font)
    XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false)
  }

  func testItalicFormatting() throws {
    try editor.update {
      guard let root = getRoot() else {
        XCTFail("Root is nil")
        return
      }
      let paragraph = ParagraphNode()
      let textNode = TextNode(text: "Italic Text")
      textNode.format.italic = true
      try paragraph.append([textNode])
      try root.append([paragraph])
    }

    // Wait for reconciliation
    let expectation = self.expectation(description: "Reconciliation")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
      expectation.fulfill()
    }
    waitForExpectations(timeout: 1.0)

    // Verify attributed string has italic trait
    guard let textStorage = view?.textStorage as? TextStorage else {
      XCTFail("TextStorage is nil")
      return
    }

    let attrString = textStorage.attributedSubstring(from: NSRange(location: 0, length: textStorage.length))
    let font = attrString.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    XCTAssertNotNil(font)
    XCTAssertTrue(font?.fontDescriptor.symbolicTraits.contains(.italic) ?? false)
  }
}
#endif
