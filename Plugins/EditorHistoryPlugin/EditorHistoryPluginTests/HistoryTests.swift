/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import EditorHistoryPlugin
@testable import Lexical
import XCTest

#if os(macOS) && !targetEnvironment(macCatalyst)
@testable import LexicalAppKit
#endif

@MainActor
class HistoryTests: XCTestCase {

  #if os(macOS) && !targetEnvironment(macCatalyst)
  var view: LexicalAppKit.LexicalView?
  #else
  var view: Lexical.LexicalView?
  #endif

  var historyPlugin: EditorHistoryPlugin?
  var editor: Editor {
    get {
      guard let editor = view?.editor else {
        XCTFail("Editor unexpectedly nil")
        fatalError()
      }
      return editor
    }
  }

  var editorHistory: EditorHistory {
    get {
      guard let historyPlugin, let editorHistory = historyPlugin.editorHistory else {
        XCTFail("historyPlugin unexpectedly nil")
        fatalError()
      }
      return editorHistory
    }
  }

  override func setUp() {
    let historyPlugin = EditorHistoryPlugin()
    self.historyPlugin = historyPlugin

    #if os(macOS) && !targetEnvironment(macCatalyst)
    view = LexicalAppKit.LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: [historyPlugin]), featureFlags: FeatureFlags())
    #else
    view = Lexical.LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: [historyPlugin]), featureFlags: FeatureFlags())
    #endif
  }

  override func tearDown() {
    view = nil
  }

  func testGetDirtyNodes() throws {
    try editor.update {
      guard let editorState = getActiveEditorState(), let rootNode = editorState.getRootNode() else {
        XCTFail("should have editor state")
        return
      }
      let textNode = TextNode()
      try textNode.setText("hello ")

      let textNode2 = TextNode()
      try textNode2.setText("world")

      let paragraphNode = ParagraphNode()
      try paragraphNode.append([textNode])
      try paragraphNode.append([textNode2])

      try rootNode.append([paragraphNode])

      XCTAssertEqual(editor.dirtyNodes.count, 5)
      XCTAssert(editor.dirtyNodes[textNode.key] != nil)
    }
  }

  func testGetChangeType() throws {
    try editor.update {
      guard let editorState = getActiveEditorState(), let rootNode = editorState.getRootNode() else {
        XCTFail("should have editor state")
        return
      }
      guard let pendingEditorState = editor.testing_getPendingEditorState() else {
        XCTFail("should have editor state")
        return
      }

      let changeType = try getChangeType(prevEditorState: editorState, nextEditorState: pendingEditorState, dirtyLeavesSet: editor.dirtyNodes, isComposing: false)

      XCTAssertNotNil(editorState)
      XCTAssertEqual(changeType, .other)

      let textNode = TextNode()
      try textNode.setText("é")

      let paragraphNode = ParagraphNode()
      try paragraphNode.append([textNode])
      try rootNode.append([paragraphNode])

      let changeType1 = try getChangeType(prevEditorState: editorState, nextEditorState: pendingEditorState, dirtyLeavesSet: editor.dirtyNodes, isComposing: true)
      XCTAssertEqual(changeType1, .composingCharacter)
    }
  }

  #if !os(macOS) || targetEnvironment(macCatalyst)
  // UIKit-specific test that uses textStorage and insertText APIs
  func testApplyHistory() throws {
    guard let view else { XCTFail(); return }

    XCTAssertEqual(view.textStorage.string, "", "Text storage should be empty")
    view.textView.insertText("A")
    XCTAssertEqual(view.textStorage.string, "A", "Text storage should contain A")
    view.editor.dispatchCommand(type: .undo)
    XCTAssertEqual(view.textStorage.string, "", "Text storage should be empty")
  }
  #endif
}
