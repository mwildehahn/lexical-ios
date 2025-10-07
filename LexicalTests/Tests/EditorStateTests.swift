/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import XCTest

@testable import Lexical
@testable import LexicalUIKit

@MainActor
class EditorStateTests: XCTestCase {

  func testReadReturnsCorrectState() throws {
    let view = LexicalView(
      editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags())
    let editor = view.editor

    try editor.update {
      createExampleNodeTree()
    }

    try editor.getEditorState().read {
      guard let activeEditorState = getActiveEditorState() else {
        XCTFail("Editor State is unexpectedly nil")
        return
      }

      guard let node = activeEditorState.getRootNode()?.getFirstChild() as? ParagraphNode else {
        XCTFail("Node is unexpectedly nil")
        return
      }

      guard let textNode = node.getFirstChild() as? TextNode else {
        XCTFail("Text node is unexpectedly nil")
        return
      }

      XCTAssertEqual(textNode.getTextPart(), "hello ")
    }
  }

  func testNodeKeyMultiplier() throws {
    let view = LexicalView(
      editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags())
    let editor = view.editor

    try editor.update {
      createExampleNodeTree()
    }

    let json = try editor.getEditorState().toJSON()
    let editorWithMultiplier = Editor(editorConfig: .init(theme: Theme(), plugins: [], nodeKeyMultiplier: NodeKeyMultiplier(depthBlockSize: 1000000, multiplier: 1000)))
    let state = try EditorState.fromJSON(json: json, editor: editorWithMultiplier)

    try state.read {
      guard let rootNode = state.getRootNode() else {
        XCTFail("Missing root node")
        return
      }

      XCTAssertEqual(rootNode.key, kRootNodeKey)
      for (index, child) in rootNode.getChildren().enumerated() {
        XCTAssertEqual(String(index + 2), child.key)
      }

      let children = rootNode.getChildren()
      let preParagraph = children[0] as! ParagraphNode
      let paragraph2 = children[1] as! ParagraphNode
      let paragraph3 = children[3] as! ParagraphNode

      let preParagraphChildren = preParagraph.getChildren()
      XCTAssertEqual(preParagraphChildren.count, 2)
      let text1 = preParagraphChildren[0] as! TextNode
      let text2 = preParagraphChildren[1] as! TextNode
      XCTAssertEqual(text1.getTextPart(), "hello ")
      XCTAssertEqual(text2.getTextPart(), "world")
      XCTAssertEqual(text1.key, "1000000000")
      XCTAssertEqual(text2.key, "1000000001")

      // Validate paragraph2's child.
      let paragraph2Children = paragraph2.getChildren()
      XCTAssertEqual(paragraph2Children.count, 1)
      let text3 = paragraph2Children[0] as! TextNode
      XCTAssertEqual(text3.getTextPart(), "Paragraph 2 contains another text node")
      XCTAssertEqual(text3.key, "1000001000")

      // Validate paragraph3's child.
      let paragraph3Children = paragraph3.getChildren()
      XCTAssertEqual(paragraph3Children.count, 1)
      let text4 = paragraph3Children[0] as! TextNode
      XCTAssertEqual(text4.getTextPart(), "Third para.")
      XCTAssertEqual(text4.key, "1000003000")
    }
  }

  func testMigrations() throws {
    let view = LexicalView(
      editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags())
    let editor = view.editor

    try editor.update {
      createExampleNodeTree()
    }

    let migrations: [EditorStateMigration] = [
      EditorStateMigration(fromVersion: 1, toVersion: 2, handler: { editorState in
        try! MainActor.assumeIsolated {
          for (_, node) in editorState.getNodeMap() {
            if node.getTextPart() == "world" {
              try node.remove()
            }
          }
        }
      }),
      EditorStateMigration(fromVersion: 2, toVersion: 3, handler: { editorState in
        try! MainActor.assumeIsolated {
          for (_, node) in editorState.getNodeMap() {
            if node.getTextPart().starts(with: "Third") {
              try node.remove()
            }
          }
        }
      })
    ]

    let serializedState = try editor.getEditorState().toJSON()
    let editorState = try EditorState.fromJSON(json: serializedState, editor: editor, migrations: migrations)

    let postMigrationState = try editorState.toJSON()
    XCTAssertEqual(editorState.version, 3)
    XCTAssertFalse(postMigrationState.contains("world"))
    XCTAssertFalse(postMigrationState.contains("Third"))

    let deserializedMigratedState = try EditorState.fromJSON(json: postMigrationState, editor: editor, migrations: migrations)
    XCTAssertEqual(deserializedMigratedState.version, 3)
  }

  func testEditorStateVersionDefault() throws {
    let view = LexicalView(
      editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags())
    let editor = view.editor

    XCTAssertEqual(editor.getEditorState().version, 1)
  }

  func testEditorStateVersion() throws {
    let view = LexicalView(
      editorConfig: EditorConfig(theme: Theme(), plugins: [], editorStateVersion: 2), featureFlags: FeatureFlags())
    let editor = view.editor

    XCTAssertEqual(editor.getEditorState().version, 2)
  }
}
