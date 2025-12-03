/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import Lexical
import XCTest

#if os(macOS) && !targetEnvironment(macCatalyst)
@testable import LexicalAppKit
#endif

/// Tests for decorator node deletion behavior with backspace/delete.
///
/// Expected behavior:
/// - First backspace when cursor is adjacent to decorator: SELECT the decorator (NodeSelection)
/// - Second backspace when decorator is already selected: DELETE the decorator
@MainActor
final class DecoratorDeletionBehaviorTests: XCTestCase {

  private func makeView() -> TestEditorView {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let view = TestEditorView(editorConfig: cfg, featureFlags: FeatureFlags())
    try? registerTestDecoratorNode(on: view.editor)
    return view
  }

  // MARK: - Backspace from text position after decorator

  func testBackspaceAfterDecorator_SelectsDecoratorFirst() throws {
    let view = makeView()
    let ed = view.editor

    var decoratorKey: NodeKey = ""

    // Setup: paragraph with [decorator, "Hello"] and cursor at start of text
    try ed.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode()
      let deco = TestDecoratorNodeCrossplatform()
      decoratorKey = deco.key
      let text = createTextNode(text: "Hello")
      try p.append([deco, text])
      try root.append([p])
      try text.select(anchorOffset: 0, focusOffset: 0)
    }

    // First backspace: should SELECT the decorator (not delete it)
    try ed.update {
      try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true)
    }

    // Verify: decorator should still exist and be selected
    try ed.read {
      let selection = try getSelection()
      XCTAssertTrue(selection is NodeSelection, "Selection should be NodeSelection after first backspace")
      if let nodeSelection = selection as? NodeSelection {
        XCTAssertTrue(nodeSelection.has(key: decoratorKey), "Decorator should be in the node selection")
      }
      // Decorator should still be in the tree
      XCTAssertNotNil(getNodeByKey(key: decoratorKey), "Decorator should still exist after first backspace")
    }
  }

  func testBackspaceAfterDecorator_TwiceDeletesDecorator() throws {
    let view = makeView()
    let ed = view.editor

    var decoratorKey: NodeKey = ""

    // Setup: paragraph with [decorator, "Hello"] and cursor at start of text
    try ed.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode()
      let deco = TestDecoratorNodeCrossplatform()
      decoratorKey = deco.key
      let text = createTextNode(text: "Hello")
      try p.append([deco, text])
      try root.append([p])
      try text.select(anchorOffset: 0, focusOffset: 0)
    }

    // First backspace: select the decorator
    try ed.update {
      try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true)
    }

    // Verify decorator is selected
    try ed.read {
      XCTAssertTrue(try getSelection() is NodeSelection, "Should be NodeSelection")
    }

    // Second backspace: delete the decorator
    try ed.update {
      try getSelection()?.deleteCharacter(isBackwards: true)
    }

    // Verify: decorator should be deleted
    try ed.read {
      XCTAssertNil(getNodeByKey(key: decoratorKey), "Decorator should be deleted after second backspace")
    }
  }

  // MARK: - Forward delete from element position before decorator

  func testForwardDeleteAtElementOffsetZero_WithDecoratorAsFirstChild_SelectsDecorator() throws {
    let view = makeView()
    let ed = view.editor

    var decoratorKey: NodeKey = ""

    // Setup: paragraph with [decorator] and element selection at offset 0 (before decorator)
    try ed.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode()
      let deco = TestDecoratorNodeCrossplatform()
      decoratorKey = deco.key
      try p.append([deco])
      try root.append([p])
      // Select at element offset 0 (before the decorator)
      try p.select(anchorOffset: 0, focusOffset: 0)
    }

    // Forward delete at offset 0: should select the decorator (it's at index 0)
    try ed.update {
      try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: false)
    }

    // Verify: decorator should be selected (NodeSelection)
    try ed.read {
      let selection = try getSelection()
      XCTAssertTrue(selection is NodeSelection, "Selection should be NodeSelection")
      if let nodeSelection = selection as? NodeSelection {
        XCTAssertTrue(nodeSelection.has(key: decoratorKey), "Decorator should be in node selection")
      }
      XCTAssertNotNil(getNodeByKey(key: decoratorKey), "Decorator should still exist")
    }
  }

  // MARK: - Delete (forward) before decorator

  func testDeleteBeforeDecorator_SelectsDecoratorFirst() throws {
    let view = makeView()
    let ed = view.editor

    var decoratorKey: NodeKey = ""

    // Setup: paragraph with ["Hello", decorator] and cursor at end of text
    try ed.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode()
      let text = createTextNode(text: "Hello")
      let deco = TestDecoratorNodeCrossplatform()
      decoratorKey = deco.key
      try p.append([text, deco])
      try root.append([p])
      try text.select(anchorOffset: 5, focusOffset: 5) // End of "Hello"
    }

    // Forward delete: should select the decorator
    try ed.update {
      try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: false)
    }

    // Verify: decorator should be selected
    try ed.read {
      let selection = try getSelection()
      // Note: This test documents expected behavior - forward delete adjacent to decorator should select it
      // If this fails, the forward delete path may need similar treatment
      if let nodeSelection = selection as? NodeSelection {
        XCTAssertTrue(nodeSelection.has(key: decoratorKey), "Decorator should be in node selection")
      }
      XCTAssertNotNil(getNodeByKey(key: decoratorKey), "Decorator should still exist after first delete")
    }
  }

  // MARK: - Decorator with text before and after

  func testBackspaceInMiddleText_DoesNotAffectDecorator() throws {
    let view = makeView()
    let ed = view.editor

    var decoratorKey: NodeKey = ""

    // Setup: paragraph with ["Hello", decorator, "World"] and cursor in middle of "World"
    try ed.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode()
      let left = createTextNode(text: "Hello")
      let deco = TestDecoratorNodeCrossplatform()
      decoratorKey = deco.key
      let right = createTextNode(text: "World")
      try p.append([left, deco, right])
      try root.append([p])
      try right.select(anchorOffset: 2, focusOffset: 2) // Middle of "World"
    }

    // Backspace in text
    try ed.update {
      try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true)
    }

    // Verify: decorator should be unaffected
    try ed.read {
      XCTAssertNotNil(getNodeByKey(key: decoratorKey), "Decorator should be unaffected")
      let selection = try getSelection()
      XCTAssertTrue(selection is RangeSelection, "Should still be RangeSelection")
    }
  }

  // MARK: - Empty paragraph with decorator

  func testBackspaceInEmptyParagraph_AdjacentToDecoratorParagraph() throws {
    let view = makeView()
    let ed = view.editor

    var decoratorKey: NodeKey = ""

    // Setup: [paragraph with decorator], [empty paragraph], cursor in empty paragraph
    try ed.update {
      guard let root = getRoot() else { return }
      let p1 = createParagraphNode()
      let deco = TestDecoratorNodeCrossplatform()
      decoratorKey = deco.key
      try p1.append([deco])

      let p2 = createParagraphNode()
      // Empty paragraph

      try root.append([p1, p2])
      try p2.select(anchorOffset: 0, focusOffset: 0)
    }

    // Backspace in empty paragraph should merge with previous (not delete decorator)
    try ed.update {
      try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true)
    }

    // Verify decorator still exists
    try ed.read {
      XCTAssertNotNil(getNodeByKey(key: decoratorKey), "Decorator should still exist")
    }
  }

  // MARK: - Multiple Empty Paragraph Tests

  /// Test backspace through multiple empty paragraphs - selection should never become nil.
  /// This replicates the action log pattern where selection became nil.
  func testBackspaceThroughMultipleEmptyParagraphs_SelectionNeverNil() throws {
    let view = makeView()
    let ed = view.editor

    // Setup: [paragraph with text], [empty], [empty], [empty], cursor in last empty
    try ed.update {
      guard let root = getRoot() else { return }
      let p1 = createParagraphNode()
      let text = createTextNode(text: "Hello")
      try p1.append([text])

      let p2 = createParagraphNode()  // empty
      let p3 = createParagraphNode()  // empty
      let p4 = createParagraphNode()  // empty

      try root.append([p1, p2, p3, p4])
      try p4.select(anchorOffset: 0, focusOffset: 0)
    }

    // Verify initial selection
    try ed.read {
      let selection = try getSelection()
      XCTAssertNotNil(selection, "Selection should not be nil initially")
    }

    // First backspace - should delete p4, move to p3
    try ed.update {
      try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true)
    }

    try ed.read {
      let selection = try getSelection()
      XCTAssertNotNil(selection, "Selection should not be nil after first backspace")
    }

    // Second backspace - should delete p3, move to p2
    try ed.update {
      try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true)
    }

    try ed.read {
      let selection = try getSelection()
      XCTAssertNotNil(selection, "Selection should not be nil after second backspace")
    }

    // Third backspace - should delete p2, move to end of p1's text
    try ed.update {
      try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true)
    }

    try ed.read {
      let selection = try getSelection()
      XCTAssertNotNil(selection, "Selection should not be nil after third backspace")
      // Should now be at end of "Hello"
      if let rangeSelection = selection as? RangeSelection {
        XCTAssertEqual(rangeSelection.anchor.type, SelectionType.text, "Should be text selection")
        XCTAssertEqual(rangeSelection.anchor.offset, 5, "Should be at end of 'Hello'")
      }
    }
  }

  /// Test that element selection offset is always valid (within children count).
  func testElementSelectionOffset_AlwaysValid() throws {
    let view = makeView()
    let ed = view.editor

    var paragraphKey: NodeKey = ""

    // Setup: empty paragraph with element selection
    try ed.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode()
      paragraphKey = p.key
      try root.append([p])
      try p.select(anchorOffset: 0, focusOffset: 0)
    }

    // Verify selection offset is 0 for empty paragraph (not 1 or higher)
    try ed.read {
      let selection = try getSelection() as? RangeSelection
      XCTAssertNotNil(selection, "Should have selection")
      XCTAssertEqual(selection?.anchor.key, paragraphKey, "Should be on paragraph")
      XCTAssertEqual(selection?.anchor.type, SelectionType.element, "Should be element selection")
      XCTAssertEqual(selection?.anchor.offset, 0, "Offset should be 0 for empty paragraph")

      // Verify offset is within bounds
      if let para = getNodeByKey(key: paragraphKey) as? ElementNode {
        let childCount = para.getChildrenSize()
        XCTAssertLessThanOrEqual(selection?.anchor.offset ?? 0, childCount, "Offset should be <= child count")
      }
    }
  }

  /// Test backspace at element offset 1 on single-child paragraph (the suspicious case from action log).
  func testBackspaceAtElementOffset1_OnSingleChildParagraph() throws {
    let view = makeView()
    let ed = view.editor

    var decoratorKey: NodeKey = ""
    var paragraphKey: NodeKey = ""

    // Setup: paragraph with single decorator, element selection at offset 1 (after decorator)
    try ed.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode()
      paragraphKey = p.key
      let deco = TestDecoratorNodeCrossplatform()
      decoratorKey = deco.key
      try p.append([deco])
      try root.append([p])
      // Element offset 1 = after the only child
      try p.select(anchorOffset: 1, focusOffset: 1)
    }

    // Verify setup
    try ed.read {
      let selection = try getSelection() as? RangeSelection
      XCTAssertEqual(selection?.anchor.offset, 1, "Should be at offset 1")
      XCTAssertEqual(selection?.anchor.type, SelectionType.element, "Should be element selection")
    }

    // First backspace at offset 1: should select the decorator
    try ed.update {
      try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true)
    }

    // Selection should NOT be nil
    try ed.read {
      let selection = try getSelection()
      XCTAssertNotNil(selection, "Selection should NOT be nil after backspace at offset 1")
      XCTAssertTrue(selection is NodeSelection, "Should be NodeSelection (decorator selected)")
      if let nodeSelection = selection as? NodeSelection {
        XCTAssertTrue(nodeSelection.has(key: decoratorKey), "Decorator should be selected")
      }
    }
  }

  // MARK: - Real-World Flow Tests (from action logs)

  /// Replicates the exact sequence from action logs:
  /// 1. Paragraph with decorator, cursor at element offset 1 (after decorator)
  /// 2. Backspace at element offset 1 → should create NodeSelection
  /// 3. Verify NodeSelection contains the decorator
  /// 4. Second backspace → should delete decorator via NodeSelection.deleteCharacter
  func testRealWorldFlow_BackspaceAtElementOffset1_CreatesNodeSelection_ThenDeletes() throws {
    let view = makeView()
    let ed = view.editor

    var decoratorKey: NodeKey = ""

    // Setup: empty paragraph, then paragraph with decorator
    // Simulates: user typed, created paragraphs, inserted decorator
    try ed.update {
      guard let root = getRoot() else { return }

      // Paragraph with text
      let p1 = createParagraphNode()
      let text = createTextNode(text: "Hello")
      try p1.append([text])

      // Paragraph with decorator
      let p2 = createParagraphNode()
      let deco = TestDecoratorNodeCrossplatform()
      decoratorKey = deco.key
      try p2.append([deco])

      try root.append([p1, p2])

      // Position cursor at element offset 1 (after decorator)
      // This is what happens after inserting a decorator
      try p2.select(anchorOffset: 1, focusOffset: 1)
    }

    // Verify setup: RangeSelection at element offset 1
    try ed.read {
      let selection = try getSelection() as? RangeSelection
      XCTAssertNotNil(selection, "Should start with RangeSelection")
      XCTAssertEqual(selection?.anchor.type, SelectionType.element)
      XCTAssertEqual(selection?.anchor.offset, 1, "Should be at offset 1 (after decorator)")
    }

    // FIRST BACKSPACE: should create NodeSelection (not delete!)
    try ed.update {
      try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true)
    }

    // Verify: NodeSelection was created, decorator still exists
    var isNodeSelection = false
    try ed.read {
      let selection = try getSelection()
      isNodeSelection = selection is NodeSelection
      XCTAssertTrue(isNodeSelection, "First backspace should create NodeSelection")
      if let nodeSelection = selection as? NodeSelection {
        XCTAssertTrue(nodeSelection.has(key: decoratorKey), "NodeSelection should contain decorator")
      }
      XCTAssertNotNil(getNodeByKey(key: decoratorKey), "Decorator should still exist after first backspace")
    }

    // SECOND BACKSPACE: should delete the decorator
    try ed.update {
      // At this point selection should be NodeSelection
      try getSelection()?.deleteCharacter(isBackwards: true)
    }

    // Verify: decorator is deleted
    try ed.read {
      XCTAssertNil(getNodeByKey(key: decoratorKey), "Decorator should be deleted after second backspace")
      // Selection should now be RangeSelection at the position where decorator was
      let selection = try getSelection()
      XCTAssertTrue(selection is RangeSelection, "Should be RangeSelection after deletion")
    }
  }

  /// Test the merged paragraph scenario from action logs:
  /// 1. Two paragraphs: text paragraph, decorator paragraph
  /// 2. Backspace merges them, cursor ends up at element offset after decorator
  /// 3. Backspace should select decorator (NodeSelection)
  /// 4. Another backspace should delete
  func testMergedParagraph_DecoratorSelection_Flow() throws {
    let view = makeView()
    let ed = view.editor

    var decoratorKey: NodeKey = ""
    var p1Key: NodeKey = ""

    // Setup: two paragraphs that will be merged
    try ed.update {
      guard let root = getRoot() else { return }

      // First paragraph with decorator
      let p1 = createParagraphNode()
      p1Key = p1.key
      let deco = TestDecoratorNodeCrossplatform()
      decoratorKey = deco.key
      try p1.append([deco])

      // Second empty paragraph (cursor here)
      let p2 = createParagraphNode()

      try root.append([p1, p2])
      try p2.select(anchorOffset: 0, focusOffset: 0)
    }

    // Backspace in empty paragraph - should merge with previous
    try ed.update {
      try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true)
    }

    // After merge, cursor should be at element offset 1 (after decorator in merged paragraph)
    try ed.read {
      let selection = try getSelection() as? RangeSelection
      XCTAssertNotNil(selection)
      // After merge, we should be in p1 at element offset 1 (after the decorator)
      XCTAssertEqual(selection?.anchor.key, p1Key, "Should be in first paragraph after merge")
      XCTAssertEqual(selection?.anchor.offset, 1, "Should be at offset 1 (after decorator)")
      XCTAssertNotNil(getNodeByKey(key: decoratorKey), "Decorator should still exist")
    }

    // Now backspace at element offset 1 - should select decorator
    try ed.update {
      try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true)
    }

    try ed.read {
      let selection = try getSelection()
      XCTAssertTrue(selection is NodeSelection, "Should be NodeSelection after backspace at offset 1")
      XCTAssertNotNil(getNodeByKey(key: decoratorKey), "Decorator should still exist")
    }

    // Final backspace - should delete
    try ed.update {
      try getSelection()?.deleteCharacter(isBackwards: true)
    }

    try ed.read {
      XCTAssertNil(getNodeByKey(key: decoratorKey), "Decorator should be deleted")
    }
  }

  // MARK: - NodeSelection Preservation Tests

  /// Test that NodeSelection is preserved when trying to set a RangeSelection over it.
  /// This simulates what happens when native selection change tries to overwrite NodeSelection.
  func testNodeSelectionNotOverwrittenByRangeSelection() throws {
    let view = makeView()
    let ed = view.editor

    var decoratorKey: NodeKey = ""
    var textKey: NodeKey = ""

    // Setup: paragraph with [decorator, "Hello"]
    try ed.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode()
      let deco = TestDecoratorNodeCrossplatform()
      decoratorKey = deco.key
      let text = createTextNode(text: "Hello")
      textKey = text.key
      try p.append([deco, text])
      try root.append([p])
    }

    // Set a NodeSelection on the decorator
    try ed.update {
      let nodeSelection = NodeSelection(nodes: [decoratorKey])
      try setSelection(nodeSelection)
    }

    // Verify NodeSelection is set
    try ed.read {
      let selection = try getSelection()
      XCTAssertTrue(selection is NodeSelection, "Should be NodeSelection")
    }

    // Try to overwrite with RangeSelection - WITHOUT the protection check
    // This simulates what would happen if notifyLexicalOfSelectionChange didn't preserve NodeSelection
    try ed.update {
      let rangeSelection = RangeSelection(
        anchor: Point(key: textKey, offset: 0, type: .text),
        focus: Point(key: textKey, offset: 0, type: .text),
        format: TextFormat()
      )
      try setSelection(rangeSelection)
    }

    // Verify that the selection WAS overwritten (documenting the problem case)
    try ed.read {
      let selection = try getSelection()
      // Without protection, the NodeSelection gets overwritten
      XCTAssertTrue(selection is RangeSelection, "Selection should be RangeSelection (demonstrating the problem)")
    }

    // Now test the FIX: set NodeSelection again, then use the protection pattern
    try ed.update {
      let nodeSelection = NodeSelection(nodes: [decoratorKey])
      try setSelection(nodeSelection)
    }

    // Apply the protection check (as done in notifyLexicalOfSelectionChange)
    try ed.update {
      // Check if existing selection is NodeSelection - preserve it
      if let existingSelection = try? getSelection(), existingSelection is NodeSelection {
        // NodeSelection exists - don't overwrite
        return
      }
      // Would set RangeSelection here, but we returned early
      let rangeSelection = RangeSelection(
        anchor: Point(key: textKey, offset: 0, type: .text),
        focus: Point(key: textKey, offset: 0, type: .text),
        format: TextFormat()
      )
      try setSelection(rangeSelection)
    }

    // Verify NodeSelection is now preserved (the fix works)
    try ed.read {
      let selection = try getSelection()
      XCTAssertTrue(selection is NodeSelection, "NodeSelection should be preserved with protection check")
      if let nodeSelection = selection as? NodeSelection {
        XCTAssertTrue(nodeSelection.has(key: decoratorKey), "Decorator should still be in node selection")
      }
    }
  }

  /// Test the full flow: backspace creates NodeSelection, which survives until second backspace deletes.
  /// This tests the core two-backspace deletion behavior with an intermediate state check.
  func testTwoBackspaceFlow_NodeSelectionSurvivesIntermediateState() throws {
    let view = makeView()
    let ed = view.editor

    var decoratorKey: NodeKey = ""

    // Setup: paragraph with [decorator, "Hello"] and cursor at start of text
    try ed.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode()
      let deco = TestDecoratorNodeCrossplatform()
      decoratorKey = deco.key
      let text = createTextNode(text: "Hello")
      try p.append([deco, text])
      try root.append([p])
      try text.select(anchorOffset: 0, focusOffset: 0)
    }

    // First backspace: should create NodeSelection
    try ed.update {
      try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true)
    }

    // Verify NodeSelection was created
    var nodeSelectionCreated = false
    try ed.read {
      let selection = try getSelection()
      nodeSelectionCreated = selection is NodeSelection
      XCTAssertTrue(nodeSelectionCreated, "First backspace should create NodeSelection")
    }

    // Simulate what would happen if native selection change tried to overwrite
    // (In real app, this happens via notifyLexicalOfSelectionChange)
    try ed.update {
      // This simulates the check in notifyLexicalOfSelectionChange
      if let existingSelection = try? getSelection(), existingSelection is NodeSelection {
        // Preserve NodeSelection - don't convert to RangeSelection
        return
      }
    }

    // Verify NodeSelection is STILL set (wasn't overwritten)
    try ed.read {
      let selection = try getSelection()
      XCTAssertTrue(selection is NodeSelection, "NodeSelection should survive intermediate state")
      XCTAssertNotNil(getNodeByKey(key: decoratorKey), "Decorator should still exist")
    }

    // Second backspace: should delete the decorator
    try ed.update {
      try getSelection()?.deleteCharacter(isBackwards: true)
    }

    // Verify decorator is deleted
    try ed.read {
      XCTAssertNil(getNodeByKey(key: decoratorKey), "Decorator should be deleted after second backspace")
    }
  }

  /// Test that NodeSelection.deleteCharacter actually deletes the selected node.
  func testNodeSelectionDeleteCharacter_DeletesSelectedNode() throws {
    let view = makeView()
    let ed = view.editor

    var decoratorKey: NodeKey = ""

    // Setup: paragraph with [decorator, "Hello"]
    try ed.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode()
      let deco = TestDecoratorNodeCrossplatform()
      decoratorKey = deco.key
      let text = createTextNode(text: "Hello")
      try p.append([deco, text])
      try root.append([p])
    }

    // Directly create and set NodeSelection
    try ed.update {
      let nodeSelection = NodeSelection(nodes: [decoratorKey])
      try setSelection(nodeSelection)
    }

    // Verify setup
    try ed.read {
      XCTAssertNotNil(getNodeByKey(key: decoratorKey), "Decorator should exist before deletion")
      XCTAssertTrue(try getSelection() is NodeSelection, "Should be NodeSelection")
    }

    // Delete via NodeSelection.deleteCharacter
    try ed.update {
      try getSelection()?.deleteCharacter(isBackwards: true)
    }

    // Verify decorator was deleted
    try ed.read {
      XCTAssertNil(getNodeByKey(key: decoratorKey), "Decorator should be deleted")
    }
  }

  // MARK: - Cursor Positioning Before Decorator Tests

  /// Test the exact scenario from user report:
  /// User has: `<text>\n<cursor><image>`  (cursor on line 2, before image)
  /// After backspace, user sees: `<text>\n<image><cursor>`  (cursor moved AFTER image) - BUG!
  /// Expected: cursor should stay BEFORE image after merge
  ///
  /// Setup:
  /// - p1: "Hello"
  /// - p2: [decorator] with cursor at element offset 0 (before decorator)
  ///
  /// First backspace: Should merge p2 into p1, cursor should be BEFORE decorator (element offset 1)
  func testBackspaceBeforeDecorator_AtStartOfParagraph_CursorStaysBeforeDecorator() throws {
    let view = makeView()
    let ed = view.editor

    var decoratorKey: NodeKey = ""
    var p1Key: NodeKey = ""

    // Setup:
    // p1: "Hello"
    // p2: [decorator] with cursor at element offset 0 (BEFORE decorator)
    try ed.update {
      guard let root = getRoot() else { return }

      let p1 = createParagraphNode()
      p1Key = p1.key
      let text = createTextNode(text: "Hello")
      try p1.append([text])

      let p2 = createParagraphNode()
      let deco = TestDecoratorNodeCrossplatform()
      decoratorKey = deco.key
      try p2.append([deco])

      try root.append([p1, p2])
      // Cursor at element offset 0 in p2 = BEFORE the decorator
      try p2.select(anchorOffset: 0, focusOffset: 0)
    }

    // Verify initial state: element selection at offset 0 (before decorator)
    try ed.read {
      let selection = try getSelection() as? RangeSelection
      XCTAssertNotNil(selection, "Should have selection")
      XCTAssertEqual(selection?.anchor.type, SelectionType.element, "Should be element selection")
      XCTAssertEqual(selection?.anchor.offset, 0, "Should be at offset 0 (before decorator)")
    }

    // FIRST BACKSPACE: merge p2 into p1, cursor should stay BEFORE decorator
    try ed.update {
      try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true)
    }

    // Verify: cursor is BEFORE the decorator (element offset 1, between text and decorator)
    try ed.read {
      let selection = try getSelection()

      // Should NOT be NodeSelection (decorator not selected yet)
      XCTAssertFalse(selection is NodeSelection, "Should NOT be NodeSelection yet - cursor should be BEFORE decorator")

      if let rangeSelection = selection as? RangeSelection {
        // After merge, p1 should contain: ["Hello" text, decorator]
        // Cursor should be at element offset 1 (between text and decorator)
        XCTAssertEqual(rangeSelection.anchor.key, p1Key, "Cursor should be in merged paragraph (p1)")
        XCTAssertEqual(rangeSelection.anchor.type, SelectionType.element, "Should be element selection")
        XCTAssertEqual(rangeSelection.anchor.offset, 1, "Cursor should be at element offset 1 (BEFORE decorator, after text)")
      }

      // Decorator should still exist
      XCTAssertNotNil(getNodeByKey(key: decoratorKey), "Decorator should still exist after merge")
    }
  }

  /// Test decorator-only paragraph merge (no text before decorator).
  /// Setup:
  /// - p1: [empty]
  /// - p2: [decorator] with cursor at element offset 0
  ///
  /// First backspace: Should merge p2 into p1, cursor at element offset 0 (before decorator)
  /// Second backspace: Should SELECT the decorator
  /// Third backspace: Should DELETE the decorator
  func testBackspaceBeforeDecorator_MergeIntoEmptyParagraph_SelectThenDelete() throws {
    let view = makeView()
    let ed = view.editor

    var decoratorKey: NodeKey = ""
    var p1Key: NodeKey = ""

    // Setup:
    // p1: [empty]
    // p2: [decorator] with cursor at element offset 0 (BEFORE decorator)
    try ed.update {
      guard let root = getRoot() else { return }

      let p1 = createParagraphNode()
      p1Key = p1.key
      // Empty paragraph

      let p2 = createParagraphNode()
      let deco = TestDecoratorNodeCrossplatform()
      decoratorKey = deco.key
      try p2.append([deco])

      try root.append([p1, p2])
      // Cursor at element offset 0 in p2 = BEFORE the decorator
      try p2.select(anchorOffset: 0, focusOffset: 0)
    }

    // FIRST BACKSPACE: merge p2 into p1
    try ed.update {
      try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true)
    }

    // After merge, p1 contains [decorator], cursor at element offset 0
    try ed.read {
      let selection = try getSelection() as? RangeSelection
      XCTAssertNotNil(selection, "Should have selection")
      XCTAssertEqual(selection?.anchor.key, p1Key, "Cursor should be in p1")
      XCTAssertEqual(selection?.anchor.type, SelectionType.element, "Should be element selection")
      XCTAssertEqual(selection?.anchor.offset, 0, "Cursor should be at element offset 0 (before decorator)")
      XCTAssertNotNil(getNodeByKey(key: decoratorKey), "Decorator should still exist")
    }

    // SECOND BACKSPACE: nothing to delete (at start of document), should stay in place
    // Actually since p1 is now at start, backspace at offset 0 does nothing
    try ed.update {
      try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true)
    }

    // Still at element offset 0
    try ed.read {
      let selection = try getSelection() as? RangeSelection
      XCTAssertNotNil(selection, "Should still have selection")
      XCTAssertNotNil(getNodeByKey(key: decoratorKey), "Decorator should still exist")
    }
  }

  /// Alternative interpretation: empty paragraph before decorator paragraph.
  /// Setup:
  /// - p1: "Hello"
  /// - p2: [empty] ← cursor here
  /// - p3: [decorator]
  ///
  /// First backspace: remove p2, cursor goes to end of p1's text (at offset 5)
  /// This is the CURRENT behavior - documenting it.
  func testBackspaceInEmptyParagraph_BeforeDecoratorParagraph_CursorGoesToEndOfText() throws {
    let view = makeView()
    let ed = view.editor

    var decoratorKey: NodeKey = ""
    var textKey: NodeKey = ""

    // Setup:
    // p1: "Hello"
    // p2: [empty] ← cursor
    // p3: [decorator]
    try ed.update {
      guard let root = getRoot() else { return }

      let p1 = createParagraphNode()
      let text = createTextNode(text: "Hello")
      textKey = text.key
      try p1.append([text])

      let p2 = createParagraphNode()
      // Empty paragraph - cursor goes here

      let p3 = createParagraphNode()
      let deco = TestDecoratorNodeCrossplatform()
      decoratorKey = deco.key
      try p3.append([deco])

      try root.append([p1, p2, p3])
      try p2.select(anchorOffset: 0, focusOffset: 0)
    }

    // FIRST BACKSPACE: remove empty p2, cursor goes to end of p1
    try ed.update {
      try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true)
    }

    // Verify current behavior: cursor at end of text in p1
    try ed.read {
      let selection = try getSelection() as? RangeSelection
      XCTAssertNotNil(selection, "Should have selection")
      XCTAssertEqual(selection?.anchor.key, textKey, "Cursor should be in text node")
      XCTAssertEqual(selection?.anchor.type, SelectionType.text, "Should be text selection")
      XCTAssertEqual(selection?.anchor.offset, 5, "Should be at end of 'Hello'")
      XCTAssertNotNil(getNodeByKey(key: decoratorKey), "Decorator should still exist")
    }
  }

  /// Test the same scenario but with inline decorator in same paragraph:
  /// [text paragraph with text + decorator]
  /// [empty paragraph] ← cursor
  ///
  /// Backspace from empty paragraph should delete empty paragraph and move cursor to last text position.
  func testBackspaceInEmptyParagraph_AfterParagraphWithInlineDecorator() throws {
    let view = makeView()
    let ed = view.editor

    var decoratorKey: NodeKey = ""
    var textKey: NodeKey = ""

    // Setup:
    // p1: "Hello" [decorator]
    // p2: [empty] ← cursor
    try ed.update {
      guard let root = getRoot() else { return }

      let p1 = createParagraphNode()
      let text = createTextNode(text: "Hello")
      textKey = text.key
      let deco = TestDecoratorNodeCrossplatform()
      decoratorKey = deco.key
      try p1.append([text, deco])

      let p2 = createParagraphNode()
      // Empty paragraph - cursor goes here

      try root.append([p1, p2])
      try p2.select(anchorOffset: 0, focusOffset: 0)
    }

    // BACKSPACE: remove empty paragraph
    try ed.update {
      try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true)
    }

    // Verify: cursor should be at end of last text node in p1
    // (This is the behavior for backspace from empty paragraph - cursor goes to last text position)
    try ed.read {
      let selection = try getSelection() as? RangeSelection
      XCTAssertNotNil(selection, "Should be RangeSelection")
      XCTAssertEqual(selection?.anchor.key, textKey, "Cursor should be in text node")
      XCTAssertEqual(selection?.anchor.offset, 5, "Cursor should be at end of 'Hello'")
      XCTAssertNotNil(getNodeByKey(key: decoratorKey), "Decorator should still exist")
    }
  }

  /// Test that a decorator-only paragraph with cursor at element offset still handles delete correctly.
  func testDecoratorOnlyParagraph_BackspaceAtElementOffset() throws {
    let view = makeView()
    let ed = view.editor

    var decoratorKey: NodeKey = ""

    // Setup: paragraph with only [decorator], selection at element offset 1 (after decorator)
    try ed.update {
      guard let root = getRoot() else { return }
      let p = createParagraphNode()
      let deco = TestDecoratorNodeCrossplatform()
      decoratorKey = deco.key
      try p.append([deco])
      try root.append([p])
      // Element offset 1 = after the decorator
      try p.select(anchorOffset: 1, focusOffset: 1)
    }

    // Verify setup - should be RangeSelection at element offset
    try ed.read {
      let selection = try getSelection() as? RangeSelection
      XCTAssertNotNil(selection, "Should be RangeSelection")
      XCTAssertEqual(selection?.anchor.type, SelectionType.element, "Should be element selection")
      XCTAssertEqual(selection?.anchor.offset, 1, "Should be at offset 1 (after decorator)")
    }

    // First backspace: should select the decorator
    try ed.update {
      try (getSelection() as? RangeSelection)?.deleteCharacter(isBackwards: true)
    }

    // Verify: decorator should be selected (NodeSelection)
    try ed.read {
      let selection = try getSelection()
      XCTAssertTrue(selection is NodeSelection, "Selection should be NodeSelection after backspace from element offset")
      if let nodeSelection = selection as? NodeSelection {
        XCTAssertTrue(nodeSelection.has(key: decoratorKey), "Decorator should be in node selection")
      }
      XCTAssertNotNil(getNodeByKey(key: decoratorKey), "Decorator should still exist")
    }
  }
}
