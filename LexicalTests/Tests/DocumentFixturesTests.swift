/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import Lexical
import XCTest

@MainActor
final class DocumentFixturesTests: XCTestCase {

  func testPopulateSmallCreatesExpectedParagraphCount() throws {
    let editorConfig = EditorConfig(theme: Theme(), plugins: [], metricsContainer: NullEditorMetricsContainer())
    let textKitContext = LexicalReadOnlyTextKitContext(editorConfig: editorConfig, featureFlags: FeatureFlags())
    let editor = textKitContext.editor

    try editor.update {
      guard let initialRoot = getActiveEditorState()?.getRootNode() else {
        XCTFail("Missing root node")
        return
      }

      let priorCount = initialRoot.children.count
      try DocumentFixtures.populateDocument(editor: editor, size: .small, wordsPerParagraph: 4)

      guard let updatedRoot = getActiveEditorState()?.getRootNode() else {
        XCTFail("Missing updated root node")
        return
      }

      let appendedKeys = Array(updatedRoot.children.dropFirst(priorCount))
      XCTAssertEqual(appendedKeys.count, 25)

      for key in appendedKeys {
        guard
          let paragraph = getNodeByKey(key: key) as? ParagraphNode,
          let textNode = paragraph.getFirstChild() as? TextNode
        else {
          XCTFail("Expected paragraph with text child")
          continue
        }
        let words = textNode.getTextPart().split(separator: " ")
        XCTAssertEqual(words.count, 4)
      }
    }
  }

  func testPopulateCustomParagraphCount() throws {
    let editorConfig = EditorConfig(theme: Theme(), plugins: [], metricsContainer: NullEditorMetricsContainer())
    let textKitContext = LexicalReadOnlyTextKitContext(editorConfig: editorConfig, featureFlags: FeatureFlags())
    let editor = textKitContext.editor

    try editor.update {
      guard let initialRoot = getActiveEditorState()?.getRootNode() else {
        XCTFail("Missing root node")
        return
      }

      let priorCount = initialRoot.children.count
      try DocumentFixtures.populate(editor: editor, paragraphs: 10, wordsPerParagraph: 6)

      guard let updatedRoot = getActiveEditorState()?.getRootNode() else {
        XCTFail("Missing updated root node")
        return
      }

      let appendedKeys = Array(updatedRoot.children.dropFirst(priorCount))
      XCTAssertEqual(appendedKeys.count, 10)

      guard let firstKey = appendedKeys.first,
        let paragraph = getNodeByKey(key: firstKey) as? ParagraphNode,
        let textNode = paragraph.getFirstChild() as? TextNode
      else {
        XCTFail("Expected paragraph with text child")
        return
      }

      let trimmed = textNode.getTextPart().trimmingCharacters(in: CharacterSet(charactersIn: "."))
      XCTAssertEqual(trimmed.split(separator: " ").count, 6)
    }
  }
}
