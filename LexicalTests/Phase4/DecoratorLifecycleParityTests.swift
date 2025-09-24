/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import Lexical
import XCTest

@MainActor
final class DecoratorLifecycleParityTests: XCTestCase {

  private func makeOptimizedView() -> LexicalView {
    let flags = FeatureFlags(optimizedReconciler: true)
    return LexicalView(editorConfig: EditorConfig(theme: Theme(), plugins: []), featureFlags: flags)
  }

  func testCreateDecorateRemoveAndMoveParity() throws {
    let view = makeOptimizedView()
    let editor = view.editor

    try editor.registerNode(nodeType: .testNode, class: TestDecoratorNode.self)

    var decoratorKey: NodeKey!

    // Create a decorator; expect 1 decorate during initial mount
    try editor.update {
      guard let root = getActiveEditorState()?.getRootNode() else { return }
      let p = ParagraphNode()
      let t = TextNode(text: "Hello", key: nil)
      let d = TestDecoratorNode()
      decoratorKey = d.getKey()
      try p.append([t, d])
      try root.append([p])
    }

    try editor.read {
      guard let k = decoratorKey, let node = getNodeByKey(key: k) as? TestDecoratorNode else { XCTFail(); return }
      XCTAssertEqual(node.numberOfTimesDecorateHasBeenCalled, 1, "create -> decorate once")
    }

    // No changes -> no extra decorate calls
    try editor.update {}
    try editor.read {
      guard let k = decoratorKey, let node = getNodeByKey(key: k) as? TestDecoratorNode else { XCTFail(); return }
      XCTAssertEqual(node.numberOfTimesDecorateHasBeenCalled, 1, "no-op update -> no decorate")
    }

    // Mark the decorator dirty -> expect decorate once more
    try editor.update {
      guard let k = decoratorKey, let node = getNodeByKey(key: k) as? TestDecoratorNode else { return }
      internallyMarkNodeAsDirty(node: node, cause: .userInitiated)
    }
    try editor.read {
      guard let k = decoratorKey, let node = getNodeByKey(key: k) as? TestDecoratorNode else { XCTFail(); return }
      XCTAssertEqual(node.numberOfTimesDecorateHasBeenCalled, 2, "dirty -> re-decorate once")
    }

    // Move the decorator into a different paragraph (reposition) -> expect decorate once more
    try editor.update {
      guard let root = getActiveEditorState()?.getRootNode(), let k = decoratorKey,
            let d = getNodeByKey(key: k) as? TestDecoratorNode else { return }
      // Create a new paragraph before existing
      let newP = ParagraphNode()
      let pre = TextNode(text: "Prelude", key: nil)
      try newP.append([pre, d])

      let children = root.getChildren()
      // Insert the new paragraph before the first child; moving 'd' repositions the decorator
      if let first = children.first {
        try first.insertBefore(nodeToInsert: newP)
      }
    }
    try editor.read {
      guard let k = decoratorKey, let node = getNodeByKey(key: k) as? TestDecoratorNode else { XCTFail(); return }
      XCTAssertEqual(node.numberOfTimesDecorateHasBeenCalled, 3, "move -> re-decorate once")
    }

    // Finally remove the decorator; expect it to be gone (cache + position cleared)
    try editor.update {
      guard let k = decoratorKey, let d = getNodeByKey(key: k) as? TestDecoratorNode else { return }
      try d.remove()
    }

    XCTAssertNil(editor.decoratorCache[decoratorKey], "Decorator cache entry should be destroyed on delete")
    XCTAssertNil(editor.textStorage?.decoratorPositionCache[decoratorKey], "Position cache cleared on delete")
  }
}
