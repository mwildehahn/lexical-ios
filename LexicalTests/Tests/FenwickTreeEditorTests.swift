/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import Testing
@testable import Lexical

@MainActor
struct FenwickTreeEditorTests {

  // Helper to create editor with FenwickTree enabled
  @MainActor
  func createEditorWithFenwickTree() -> (LexicalView, Editor) {
    let featureFlags = FeatureFlags(useFenwickTreeOffsets: true)
    let view = LexicalView(
      editorConfig: EditorConfig(theme: Theme(), plugins: []),
      featureFlags: featureFlags
    )
    return (view, view.editor)
  }

  // Helper to create editor with both modes for comparison
  @MainActor
  func createEditorsForComparison() -> (rangeCache: (LexicalView, Editor), fenwick: (LexicalView, Editor)) {
    let rangeCacheFlags = FeatureFlags(useFenwickTreeOffsets: false)
    let rangeCacheView = LexicalView(
      editorConfig: EditorConfig(theme: Theme(), plugins: []),
      featureFlags: rangeCacheFlags
    )

    let fenwickFlags = FeatureFlags(useFenwickTreeOffsets: true)
    let fenwickView = LexicalView(
      editorConfig: EditorConfig(theme: Theme(), plugins: []),
      featureFlags: fenwickFlags
    )

    return (
      rangeCache: (rangeCacheView, rangeCacheView.editor),
      fenwick: (fenwickView, fenwickView.editor)
    )
  }

  // MARK: - Basic Paragraph Operations

  @Test
  func addingSingleParagraph() throws {
    let (view, editor) = createEditorWithFenwickTree()

    try editor.update {
      let paragraph = ParagraphNode()
      let text = TextNode()
      try text.setText("Hello, world!")
      try paragraph.append([text])

      guard let root = getRoot() else {
        Issue.record("Root node not found")
        return
      }
      try root.append([paragraph])
    }

    #expect(view.textView.text == "Hello, world!")

    // Verify selection at end
    let range = view.textView.selectedRange
    #expect(range.location == 13)
    #expect(range.length == 0)
  }

  @Test
  func addingMultipleParagraphs() throws {
    let (view, editor) = createEditorWithFenwickTree()

    try editor.update {
      let para1 = ParagraphNode()
      let text1 = TextNode()
      try text1.setText("First paragraph")
      try para1.append([text1])

      let para2 = ParagraphNode()
      let text2 = TextNode()
      try text2.setText("Second paragraph")
      try para2.append([text2])

      let para3 = ParagraphNode()
      let text3 = TextNode()
      try text3.setText("Third paragraph")
      try para3.append([text3])

      guard let root = getRoot() else {
        Issue.record("Root node not found")
        return
      }
      try root.append([para1, para2, para3])
    }

    #expect(view.textView.text == "First paragraph\nSecond paragraph\nThird paragraph")
  }

  // MARK: - Text Insertion

  @Test
  func insertingCharactersAtBeginning() throws {
    let (view, editor) = createEditorWithFenwickTree()

    // Setup initial content
    try editor.update {
      let para = ParagraphNode()
      let text = TextNode()
      try text.setText("world")
      try para.append([text])

      guard let root = getRoot() else {
        Issue.record("Root node not found")
        return
      }
      try root.append([para])
    }

    // Insert at beginning
    view.textView.selectedRange = NSRange(location: 0, length: 0)
    view.textView.insertText("Hello ")

    #expect(view.textView.text == "Hello world")

    // Verify cursor position after insertion
    #expect(view.textView.selectedRange.location == 6)
  }

  @Test
  func insertingCharactersInMiddle() throws {
    let (view, editor) = createEditorWithFenwickTree()

    try editor.update {
      let para = ParagraphNode()
      let text = TextNode()
      try text.setText("Hello world")
      try para.append([text])

      guard let root = getRoot() else {
        Issue.record("Root node not found")
        return
      }
      try root.append([para])
    }

    // Insert in middle
    view.textView.selectedRange = NSRange(location: 5, length: 0)
    view.textView.insertText(" beautiful")

    #expect(view.textView.text == "Hello beautiful world")
    #expect(view.textView.selectedRange.location == 15)
  }

  @Test
  func insertingNewlineCreatesNewParagraph() throws {
    let (view, editor) = createEditorWithFenwickTree()

    try editor.update {
      let para = ParagraphNode()
      let text = TextNode()
      try text.setText("Hello world")
      try para.append([text])

      guard let root = getRoot() else {
        Issue.record("Root node not found")
        return
      }
      try root.append([para])
    }

    // Insert newline in middle
    view.textView.selectedRange = NSRange(location: 5, length: 0)
    view.textView.insertText("\n")

    #expect(view.textView.text == "Hello\n world")

    // Verify two paragraphs exist
    try editor.getEditorState().read {
      guard let root = getRoot() else {
        Issue.record("Root node not found")
        return
      }
      #expect(root.getChildrenSize() == 2)
    }
  }

  // MARK: - Text Deletion

  @Test
  func deletingCharactersBackward() throws {
    let (view, editor) = createEditorWithFenwickTree()

    try editor.update {
      let para = ParagraphNode()
      let text = TextNode()
      try text.setText("Hello world")
      try para.append([text])

      guard let root = getRoot() else {
        Issue.record("Root node not found")
        return
      }
      try root.append([para])
    }

    // Delete last 6 characters
    view.textView.selectedRange = NSRange(location: 11, length: 0)
    for _ in 0..<6 {
      view.textView.deleteBackward()
    }

    #expect(view.textView.text == "Hello")
    #expect(view.textView.selectedRange.location == 5)
  }

  @Test
  func deletingAcrossParagraphs() throws {
    let (view, editor) = createEditorWithFenwickTree()

    try editor.update {
      let para1 = ParagraphNode()
      let text1 = TextNode()
      try text1.setText("First")
      try para1.append([text1])

      let para2 = ParagraphNode()
      let text2 = TextNode()
      try text2.setText("Second")
      try para2.append([text2])

      guard let root = getRoot() else {
        Issue.record("Root node not found")
        return
      }
      try root.append([para1, para2])
    }

    // Select from middle of first para to middle of second
    view.textView.selectedRange = NSRange(location: 3, length: 6)
    view.textView.insertText("")

    #expect(view.textView.text == "Firecond")

    // Should now be single paragraph
    try editor.getEditorState().read {
      guard let root = getRoot() else {
        Issue.record("Root node not found")
        return
      }
      #expect(root.getChildrenSize() == 1)
    }
  }

  // MARK: - Selection Management

  @Test
  func selectionAfterTextInsertion() throws {
    let (view, editor) = createEditorWithFenwickTree()

    try editor.update {
      let para = ParagraphNode()
      let text = TextNode()
      try text.setText("Test")
      try para.append([text])

      guard let root = getRoot() else {
        Issue.record("Root node not found")
        return
      }
      try root.append([para])
    }

    // Insert at end
    view.textView.selectedRange = NSRange(location: 4, length: 0)
    view.textView.insertText(" string")

    #expect(view.textView.selectedRange.location == 11)
    #expect(view.textView.selectedRange.length == 0)
  }

  @Test
  func selectionWithRangeReplacement() throws {
    let (view, editor) = createEditorWithFenwickTree()

    try editor.update {
      let para = ParagraphNode()
      let text = TextNode()
      try text.setText("Hello world")
      try para.append([text])

      guard let root = getRoot() else {
        Issue.record("Root node not found")
        return
      }
      try root.append([para])
    }

    // Select "world" and replace
    view.textView.selectedRange = NSRange(location: 6, length: 5)
    view.textView.insertText("universe")

    #expect(view.textView.text == "Hello universe")
    #expect(view.textView.selectedRange.location == 14)
  }

  // MARK: - Complex Operations

  @Test
  func complexEditingSequence() throws {
    let (view, editor) = createEditorWithFenwickTree()

    // Start with initial text
    try editor.update {
      let para = ParagraphNode()
      let text = TextNode()
      try text.setText("The quick brown fox")
      try para.append([text])

      guard let root = getRoot() else {
        Issue.record("Root node not found")
        return
      }
      try root.append([para])
    }

    // 1. Add text at end
    view.textView.selectedRange = NSRange(location: 19, length: 0)
    view.textView.insertText(" jumps")
    #expect(view.textView.text == "The quick brown fox jumps")

    // 2. Insert in middle
    view.textView.selectedRange = NSRange(location: 10, length: 0)
    view.textView.insertText("lazy ")
    #expect(view.textView.text == "The quick lazy brown fox jumps")

    // 3. Delete a word
    view.textView.selectedRange = NSRange(location: 15, length: 6) // "brown "
    view.textView.insertText("")
    #expect(view.textView.text == "The quick lazy fox jumps")

    // 4. Add newline and new paragraph
    view.textView.selectedRange = NSRange(location: 24, length: 0)
    view.textView.insertText("\nover the lazy dog")
    #expect(view.textView.text == "The quick lazy fox jumps\nover the lazy dog")

    // Verify structure
    try editor.getEditorState().read {
      guard let root = getRoot() else {
        Issue.record("Root node not found")
        return
      }
      #expect(root.getChildrenSize() == 2)
    }
  }

  // MARK: - Comparison Tests

  @Test
  func rangeCacheVsFenwickTreeEquivalence() throws {
    let editors = createEditorsForComparison()

    // Perform same operations on both
    for (view, editor) in [editors.rangeCache, editors.fenwick] {
      try editor.update {
        let para1 = ParagraphNode()
        let text1 = TextNode()
        try text1.setText("First paragraph with some text")
        try para1.append([text1])

        let para2 = ParagraphNode()
        let text2 = TextNode()
        try text2.setText("Second paragraph here")
        try para2.append([text2])

        guard let root = getRoot() else {
          Issue.record("Root node not found")
          return
        }
        try root.append([para1, para2])
      }

      // Insert text
      view.textView.selectedRange = NSRange(location: 5, length: 0)
      view.textView.insertText(" NEW")

      // Delete text
      view.textView.selectedRange = NSRange(location: 20, length: 10)
      view.textView.insertText("")

      // Add newline
      view.textView.selectedRange = NSRange(location: 15, length: 0)
      view.textView.insertText("\n")
    }

    // Both should have identical output
    #expect(editors.rangeCache.0.textView.text == editors.fenwick.0.textView.text)
    #expect(editors.rangeCache.0.textView.selectedRange == editors.fenwick.0.textView.selectedRange)
  }

  // MARK: - Performance-Critical Operations

  @Test
  func largeDocumentInsertion() throws {
    let (view, editor) = createEditorWithFenwickTree()

    // Create document with many paragraphs
    try editor.update {
      guard let root = getRoot() else {
        Issue.record("Root node not found")
        return
      }

      for i in 1...100 {
        let para = ParagraphNode()
        let text = TextNode()
        try text.setText("Paragraph \(i): This is some sample text content for testing.")
        try para.append([text])
        try root.append([para])
      }
    }

    // Insert in middle paragraph
    let searchString = "Paragraph 50"
    let targetLocation = (view.textView.text as NSString?)?.range(of: searchString).location ?? 0

    view.textView.selectedRange = NSRange(location: targetLocation + 12, length: 0)
    view.textView.insertText(" [INSERTED TEXT]")

    // Verify insertion
    #expect(view.textView.text?.contains("Paragraph 50: [INSERTED TEXT]") == true)

    // Verify document structure unchanged
    try editor.getEditorState().read {
      guard let root = getRoot() else {
        Issue.record("Root node not found")
        return
      }
      #expect(root.getChildrenSize() == 100)
    }
  }

  @Test
  func rapidSequentialEdits() throws {
    let (view, editor) = createEditorWithFenwickTree()

    try editor.update {
      let para = ParagraphNode()
      let text = TextNode()
      try text.setText("Start")
      try para.append([text])

      guard let root = getRoot() else {
        Issue.record("Root node not found")
        return
      }
      try root.append([para])
    }

    // Simulate rapid typing
    let additions = [" typing", " very", " quickly", " here", "!"]
    for addition in additions {
      view.textView.selectedRange = NSRange(location: view.textView.text?.count ?? 0, length: 0)
      view.textView.insertText(addition)
    }

    #expect(view.textView.text == "Start typing very quickly here!")
  }

  // MARK: - Edge Cases

  @Test
  func emptyDocumentOperations() throws {
    let (view, editor) = createEditorWithFenwickTree()

    // Start with empty document
    view.textView.insertText("First text")

    #expect(view.textView.text == "First text")

    // Verify paragraph was created
    try editor.getEditorState().read {
      guard let root = getRoot() else {
        Issue.record("Root node not found")
        return
      }
      #expect(root.getChildrenSize() == 1)

      if let para = root.getFirstChild() as? ParagraphNode,
         let text = para.getFirstChild() as? TextNode {
        #expect(text.getTextContent() == "First text")
      } else {
        Issue.record("Expected paragraph with text node")
      }
    }
  }

  @Test
  func multipleNewlinesCreatesEmptyParagraphs() throws {
    let (view, editor) = createEditorWithFenwickTree()

    view.textView.insertText("Line 1\n\n\nLine 2")

    #expect(view.textView.text == "Line 1\n\n\nLine 2")

    // Should have 4 paragraphs (including empty ones)
    try editor.getEditorState().read {
      guard let root = getRoot() else {
        Issue.record("Root node not found")
        return
      }
      #expect(root.getChildrenSize() == 4)
    }
  }

  @Test
  func emojisAndUnicodeWithFenwickTree() throws {
    let (view, editor) = createEditorWithFenwickTree()

    // Test with emojis and unicode characters
    view.textView.insertText("Hello 👋 world 🌍")
    #expect(view.textView.text == "Hello 👋 world 🌍")

    // Insert in middle of emoji text
    view.textView.selectedRange = NSRange(location: 8, length: 0)
    view.textView.insertText("beautiful ")
    #expect(view.textView.text == "Hello 👋 beautiful world 🌍")

    // Delete emoji
    view.textView.selectedRange = NSRange(location: 6, length: 2) // Select emoji
    view.textView.insertText("")
    #expect(view.textView.text == "Hello beautiful world 🌍")
  }
}