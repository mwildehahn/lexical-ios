/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import XCTest

@testable import Lexical

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

  func testMigrations() throws {
    let view = LexicalView(
      editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags())
    let editor = view.editor

    try editor.update {
      createExampleNodeTree()
    }

    let migrations: [EditorStateMigration] = [
      EditorStateMigration(fromVersion: 1, toVersion: 2, handler: { editorState in
        for (_, node) in editorState.getNodeMap() {
          if node.getTextPart() == "world" {
            try node.remove()
          }
        }
      }),
      EditorStateMigration(fromVersion: 2, toVersion: 3, handler: { editorState in
        for (_, node) in editorState.getNodeMap() {
          if node.getTextPart().starts(with: "Third") {
            try node.remove()
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
}
