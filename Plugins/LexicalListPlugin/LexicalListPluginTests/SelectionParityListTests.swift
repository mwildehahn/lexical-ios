/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import Lexical
@testable import LexicalListPlugin
import XCTest

@MainActor
final class SelectionParityListTests: XCTestCase {

  func testListItemStartBoundaryParity() throws {
    // Legacy context with ListPlugin to register nodes
    let legacyCtx = LexicalReadOnlyTextKitContext(
      editorConfig: EditorConfig(theme: Theme(), plugins: [ListPlugin()]),
      featureFlags: FeatureFlags(optimizedReconciler: false, selectionParityDebug: true)
    )
    let legacyEditor = legacyCtx.editor

    var legacyItem2: NodeKey = ""
    try legacyEditor.update {
      guard let root = getActiveEditorState()?.getRootNode() else { return }
      let list = ListNode(listType: .bullet, start: 1)
      let item1 = ListItemNode(); let t1 = TextNode(text: "One", key: nil); try item1.append([t1])
      let item2 = ListItemNode(); let t2 = TextNode(text: "Two", key: nil); try item2.append([t2])
      try list.append([item1, item2])
      try root.append([list])
      legacyItem2 = item2.getKey()
    }
    try legacyEditor.update {}

    // Optimized context with ListPlugin
    let optCtx = LexicalReadOnlyTextKitContext(
      editorConfig: EditorConfig(theme: Theme(), plugins: [ListPlugin()]),
      featureFlags: FeatureFlags(optimizedReconciler: true, selectionParityDebug: true)
    )
    let optEditor = optCtx.editor
    var optItem2: NodeKey = ""
    try optEditor.update {
      guard let root = getActiveEditorState()?.getRootNode() else { return }
      let list = ListNode(listType: .bullet, start: 1)
      let item1 = ListItemNode(); let t1 = TextNode(text: "One", key: nil); try item1.append([t1])
      let item2 = ListItemNode(); let t2 = TextNode(text: "Two", key: nil); try item2.append([t2])
      try list.append([item1, item2])
      try root.append([list])
      optItem2 = item2.getKey()
    }
    try optEditor.update {}

    // Compute absolute start of second item in both modes
    var legacyLoc = 0, optLoc = 0
    try legacyEditor.read {
      guard let rc = legacyEditor.rangeCache[legacyItem2] else { return }
      legacyLoc = rc.location
    }
    try optEditor.read {
      guard let rc = optEditor.rangeCache[optItem2] else { return }
      optLoc = rc.locationFromFenwick(using: optEditor.fenwickTree)
    }

    let lF = try? pointAtStringLocation(legacyLoc, searchDirection: .forward, rangeCache: legacyEditor.rangeCache)
    let lB = try? pointAtStringLocation(legacyLoc, searchDirection: .backward, rangeCache: legacyEditor.rangeCache)
    let oF = try? pointAtStringLocation(optLoc, searchDirection: .forward, rangeCache: optEditor.rangeCache)
    let oB = try? pointAtStringLocation(optLoc, searchDirection: .backward, rangeCache: optEditor.rangeCache)

    func loc(_ p: Point?, _ ed: Editor) -> Int? { guard let p else { return nil }; return try? stringLocationForPoint(p, editor: ed) }
    XCTAssertNotNil(lF); XCTAssertNotNil(lB); XCTAssertNotNil(oF); XCTAssertNotNil(oB)
    XCTAssertEqual(loc(lF, legacyEditor), legacyLoc)
    XCTAssertEqual(loc(lB, legacyEditor), legacyLoc)
    XCTAssertEqual(loc(oF, optEditor), optLoc)
    XCTAssertEqual(loc(oB, optEditor), optLoc)
  }

  func testNestedListStartBoundaryParity() throws {
    // Legacy editor with nested list under second item
    let legacyCtx = LexicalReadOnlyTextKitContext(
      editorConfig: EditorConfig(theme: Theme(), plugins: [ListPlugin()]),
      featureFlags: FeatureFlags(optimizedReconciler: false, selectionParityDebug: true)
    )
    let legacyEditor = legacyCtx.editor
    var nestedLegacyListKey: NodeKey = ""
    try legacyEditor.update {
      guard let root = getActiveEditorState()?.getRootNode() else { return }
      let list = ListNode(listType: .bullet, start: 1)
      let item1 = ListItemNode(); try item1.append([TextNode(text: "One", key: nil)])
      let item2 = ListItemNode(); try item2.append([TextNode(text: "Two", key: nil)])
      // nested
      let nested = ListNode(listType: .bullet, start: 1)
      let nItem = ListItemNode(); try nItem.append([TextNode(text: "Child", key: nil)])
      try nested.append([nItem])
      try item2.append([nested])
      try list.append([item1, item2])
      try root.append([list])
      nestedLegacyListKey = nested.getKey()
    }
    try legacyEditor.update {}

    // Optimized editor mirror
    let optCtx = LexicalReadOnlyTextKitContext(
      editorConfig: EditorConfig(theme: Theme(), plugins: [ListPlugin()]),
      featureFlags: FeatureFlags(optimizedReconciler: true, selectionParityDebug: true)
    )
    let optEditor = optCtx.editor
    var nestedOptListKey: NodeKey = ""
    try optEditor.update {
      guard let root = getActiveEditorState()?.getRootNode() else { return }
      let list = ListNode(listType: .bullet, start: 1)
      let item1 = ListItemNode(); try item1.append([TextNode(text: "One", key: nil)])
      let item2 = ListItemNode(); try item2.append([TextNode(text: "Two", key: nil)])
      let nested = ListNode(listType: .bullet, start: 1)
      let nItem = ListItemNode(); try nItem.append([TextNode(text: "Child", key: nil)])
      try nested.append([nItem])
      try item2.append([nested])
      try list.append([item1, item2])
      try root.append([list])
      nestedOptListKey = nested.getKey()
    }
    try optEditor.update {}

    // Compute absolute start for nested list in both modes
    var lLoc = 0, oLoc = 0
    try legacyEditor.read {
      guard let rc = legacyEditor.rangeCache[nestedLegacyListKey] else { return }
      lLoc = rc.location
    }
    try optEditor.read {
      guard let rc = optEditor.rangeCache[nestedOptListKey] else { return }
      oLoc = rc.locationFromFenwick(using: optEditor.fenwickTree)
    }

    let lF = try? pointAtStringLocation(lLoc, searchDirection: .forward, rangeCache: legacyEditor.rangeCache)
    let lB = try? pointAtStringLocation(lLoc, searchDirection: .backward, rangeCache: legacyEditor.rangeCache)
    let oF = try? pointAtStringLocation(oLoc, searchDirection: .forward, rangeCache: optEditor.rangeCache)
    let oB = try? pointAtStringLocation(oLoc, searchDirection: .backward, rangeCache: optEditor.rangeCache)

    func loc(_ p: Point?, _ ed: Editor) -> Int? { guard let p else { return nil }; return try? stringLocationForPoint(p, editor: ed) }
    XCTAssertNotNil(lF); XCTAssertNotNil(lB); XCTAssertNotNil(oF); XCTAssertNotNil(oB)
    XCTAssertEqual(loc(lF, legacyEditor), lLoc)
    XCTAssertEqual(loc(lB, legacyEditor), lLoc)
    XCTAssertEqual(loc(oF, optEditor), oLoc)
    XCTAssertEqual(loc(oB, optEditor), oLoc)
  }

  func testListItemEndBoundaryParity() throws {
    // Legacy
    let legacyCtx = LexicalReadOnlyTextKitContext(
      editorConfig: EditorConfig(theme: Theme(), plugins: [ListPlugin()]),
      featureFlags: FeatureFlags(optimizedReconciler: false, selectionParityDebug: true)
    )
    let legacyEditor = legacyCtx.editor
    var legacyItemKey: NodeKey = ""
    try legacyEditor.update {
      guard let root = getActiveEditorState()?.getRootNode() else { return }
      let list = ListNode(listType: .bullet, start: 1)
      let item = ListItemNode(); try item.append([TextNode(text: "End", key: nil)])
      try list.append([item])
      try root.append([list])
      legacyItemKey = item.getKey()
    }
    try legacyEditor.update {}

    // Optimized
    let optCtx = LexicalReadOnlyTextKitContext(
      editorConfig: EditorConfig(theme: Theme(), plugins: [ListPlugin()]),
      featureFlags: FeatureFlags(optimizedReconciler: true, selectionParityDebug: true)
    )
    let optEditor = optCtx.editor
    var optItemKey: NodeKey = ""
    try optEditor.update {
      guard let root = getActiveEditorState()?.getRootNode() else { return }
      let list = ListNode(listType: .bullet, start: 1)
      let item = ListItemNode(); try item.append([TextNode(text: "End", key: nil)])
      try list.append([item])
      try root.append([list])
      optItemKey = item.getKey()
    }
    try optEditor.update {}

    // Compute end-of-item boundary: childrenStart + childrenLength
    var lEnd = 0, oEnd = 0
    try legacyEditor.read {
      guard let rc = legacyEditor.rangeCache[legacyItemKey] else { return }
      lEnd = rc.location + rc.preambleLength + rc.childrenLength
    }
    try optEditor.read {
      guard let rc = optEditor.rangeCache[optItemKey] else { return }
      let base = rc.locationFromFenwick(using: optEditor.fenwickTree)
      oEnd = base + rc.preambleLength + rc.childrenLength
    }

    let lF = try? pointAtStringLocation(lEnd, searchDirection: .forward, rangeCache: legacyEditor.rangeCache)
    let lB = try? pointAtStringLocation(lEnd, searchDirection: .backward, rangeCache: legacyEditor.rangeCache)
    let oF = try? pointAtStringLocation(oEnd, searchDirection: .forward, rangeCache: optEditor.rangeCache)
    let oB = try? pointAtStringLocation(oEnd, searchDirection: .backward, rangeCache: optEditor.rangeCache)

    func loc2(_ p: Point?, _ ed: Editor) -> Int? { guard let p else { return nil }; return try? stringLocationForPoint(p, editor: ed) }
    XCTAssertNotNil(lF); XCTAssertNotNil(lB); XCTAssertNotNil(oF); XCTAssertNotNil(oB)
    XCTAssertEqual(loc2(lF, legacyEditor), lEnd)
    XCTAssertEqual(loc2(lB, legacyEditor), lEnd)
    XCTAssertEqual(loc2(oF, optEditor), oEnd)
    XCTAssertEqual(loc2(oB, optEditor), oEnd)
  }
}
