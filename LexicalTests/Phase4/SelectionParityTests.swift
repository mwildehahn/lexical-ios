/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import Lexical
import XCTest

#if ENABLE_SELECTION_PARITY_TESTS

@MainActor
final class SelectionParityTests: XCTestCase {

  private func buildSimpleTwoTextNodesDocument(editor: Editor) throws -> (text1: NodeKey, text2: NodeKey) {
    var t1: NodeKey = ""
    var t2: NodeKey = ""
    try editor.update {
      guard let root = getActiveEditorState()?.getRootNode() else { return }
      let p = ParagraphNode()
      let n1 = TextNode(text: "ab", key: nil)
      let n2 = TextNode(text: "cd", key: nil)
      try p.append([n1, n2])
      try root.append([p])
      t1 = n1.getKey()
      t2 = n2.getKey()
    }
    // Force a follow-up pass to ensure caches are populated
    try editor.update {}
    return (t1, t2)
  }

  func testBoundaryBetweenAdjacentTextNodesParity() throws {
    // Legacy context
    let legacyCtx = LexicalReadOnlyTextKitContext(
      editorConfig: EditorConfig(theme: Theme(), plugins: []),
      featureFlags: FeatureFlags(optimizedReconciler: false)
    )
    let legacyEditor = legacyCtx.editor
    let (legacyT1, legacyT2) = try buildSimpleTwoTextNodesDocument(editor: legacyEditor)

    // Optimized context
    let optCtx = LexicalReadOnlyTextKitContext(
      editorConfig: EditorConfig(theme: Theme(), plugins: []),
      featureFlags: FeatureFlags(optimizedReconciler: true)
    )
    let optEditor = optCtx.editor
    let (optT1, optT2) = try buildSimpleTwoTextNodesDocument(editor: optEditor)

    // Compute boundary location via element child boundary (between t1 and t2)
    var legacyF: Point? = nil, legacyB: Point? = nil
    try legacyEditor.read {
      guard let root = getActiveEditorState()?.getRootNode(),
            let p = root.getChildren().first as? ParagraphNode else { XCTFail(); return }
      let point = Point(key: p.getKey(), offset: 1, type: .element)
      guard let loc = try stringLocationForPoint(point, editor: legacyEditor) else { XCTFail(); return }
      do {
        legacyF = try pointAtStringLocation(loc, searchDirection: .forward, rangeCache: legacyEditor.rangeCache)
        legacyB = try pointAtStringLocation(loc, searchDirection: .backward, rangeCache: legacyEditor.rangeCache)
      } catch {
        legacyF = nil; legacyB = nil
      }
    }
    var optF: Point? = nil, optB: Point? = nil
    try optEditor.read {
      guard let root = getActiveEditorState()?.getRootNode(),
            let p = root.getChildren().first as? ParagraphNode else { XCTFail(); return }
      let point = Point(key: p.getKey(), offset: 1, type: .element)
      guard let loc = try stringLocationForPoint(point, editor: optEditor) else { XCTFail(); return }
      do {
        optF = try pointAtStringLocation(loc, searchDirection: .forward, rangeCache: optEditor.rangeCache)
        optB = try pointAtStringLocation(loc, searchDirection: .backward, rangeCache: optEditor.rangeCache)
      } catch {
        optF = nil; optB = nil
      }
    }
    if (legacyF == nil || optF == nil) && !(legacyF == nil && optF == nil) {
      XCTFail("Parity mismatch: one context returned nil for forward boundary")
    } else {
      XCTAssertEqual(legacyF?.key, optF?.key)
      XCTAssertEqual(legacyF?.offset, optF?.offset)
    }
    if (legacyB == nil || optB == nil) && !(legacyB == nil && optB == nil) {
      XCTFail("Parity mismatch: one context returned nil for backward boundary")
    } else {
      XCTAssertEqual(legacyB?.key, optB?.key)
      XCTAssertEqual(legacyB?.offset, optB?.offset)
    }
  }

  func testElementBoundaryParity() throws {
    // Build a paragraph element with no children and test boundary behavior
    func buildEmptyParagraphDoc(_ editor: Editor) throws -> NodeKey {
      var pk: NodeKey = ""
      try editor.update {
        guard let root = getActiveEditorState()?.getRootNode() else { return }
        let p = ParagraphNode()
        try root.append([p])
        pk = p.getKey()
      }
      try editor.update {}
      return pk
    }

    let legacyCtx = LexicalReadOnlyTextKitContext(
      editorConfig: EditorConfig(theme: Theme(), plugins: []),
      featureFlags: FeatureFlags(optimizedReconciler: false)
    )
    let legacyEditor = legacyCtx.editor
    let legacyP = try buildEmptyParagraphDoc(legacyEditor)

    let optCtx = LexicalReadOnlyTextKitContext(
      editorConfig: EditorConfig(theme: Theme(), plugins: []),
      featureFlags: FeatureFlags(optimizedReconciler: true)
    )
    let optEditor = optCtx.editor
    let optP = try buildEmptyParagraphDoc(optEditor)

    var legacyEF: Point? = nil, legacyEB: Point? = nil
    try legacyEditor.read {
      let point = Point(key: legacyP, offset: 0, type: .element)
      guard let start = try stringLocationForPoint(point, editor: legacyEditor) else { XCTFail(); return }
      do {
        legacyEF = try pointAtStringLocation(start, searchDirection: .forward, rangeCache: legacyEditor.rangeCache)
        legacyEB = try pointAtStringLocation(start, searchDirection: .backward, rangeCache: legacyEditor.rangeCache)
      } catch { legacyEF = nil; legacyEB = nil }
    }
    var optEF: Point? = nil, optEB: Point? = nil
    try optEditor.read {
      let point = Point(key: optP, offset: 0, type: .element)
      guard let start = try stringLocationForPoint(point, editor: optEditor) else { XCTFail(); return }
      do {
        optEF = try pointAtStringLocation(start, searchDirection: .forward, rangeCache: optEditor.rangeCache)
        optEB = try pointAtStringLocation(start, searchDirection: .backward, rangeCache: optEditor.rangeCache)
      } catch { optEF = nil; optEB = nil }
    }
    if (legacyEF == nil || optEF == nil) && !(legacyEF == nil && optEF == nil) {
      XCTFail("Parity mismatch: one context returned nil at element start (forward)")
    } else {
      XCTAssertEqual(legacyEF?.key, optEF?.key)
    }
    if (legacyEB == nil || optEB == nil) && !(legacyEB == nil && optEB == nil) {
      XCTFail("Parity mismatch: one context returned nil at element start (backward)")
    } else {
      XCTAssertEqual(legacyEB?.key, optEB?.key)
    }
  }
}

#endif
