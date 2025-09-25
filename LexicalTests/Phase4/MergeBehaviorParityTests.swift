/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import Lexical
import XCTest

@MainActor
final class MergeBehaviorParityTests: XCTestCase {
  func testAdjacentSimpleTextNodesMergeParity() throws {
    // Legacy
    let legacyCtx = LexicalReadOnlyTextKitContext(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags(optimizedReconciler: false))
    let legacy = legacyCtx.editor
    var legacyChildrenCount = -1
    try legacy.update {
      guard let root = getActiveEditorState()?.getRootNode() else { return }
      let p = ParagraphNode()
      try p.append([TextNode(text: "ab", key: nil), TextNode(text: "cd", key: nil)])
      try root.append([p])
    }
    try legacy.read {
      guard let p = (getActiveEditorState()?.getRootNode()?.getFirstChild() as? ElementNode) else { return XCTFail("no paragraph") }
      legacyChildrenCount = p.getChildren().count
    }

    // Optimized
    let optCtx = LexicalReadOnlyTextKitContext(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: FeatureFlags(optimizedReconciler: true))
    let opt = optCtx.editor
    var optChildrenCount = -1
    try opt.update {
      guard let root = getActiveEditorState()?.getRootNode() else { return }
      let p = ParagraphNode()
      try p.append([TextNode(text: "ab", key: nil), TextNode(text: "cd", key: nil)])
      try root.append([p])
    }
    try opt.read {
      guard let p = (getActiveEditorState()?.getRootNode()?.getFirstChild() as? ElementNode) else { return XCTFail("no paragraph") }
      optChildrenCount = p.getChildren().count
    }

    XCTAssertEqual(optChildrenCount, legacyChildrenCount, "Legacy and Optimized must agree on whether adjacent simple text nodes merge")
  }
}

