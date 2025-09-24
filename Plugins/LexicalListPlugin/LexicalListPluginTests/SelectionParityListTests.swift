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
      featureFlags: FeatureFlags(optimizedReconciler: false)
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
      featureFlags: FeatureFlags(optimizedReconciler: true)
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
    if let lF { XCTAssertEqual(loc(lF, legacyEditor), legacyLoc) }
    if let lB { XCTAssertEqual(loc(lB, legacyEditor), legacyLoc) }
    if let oF { XCTAssertEqual(loc(oF, optEditor), optLoc) }
    if let oB { XCTAssertEqual(loc(oB, optEditor), optLoc) }
  }
}

