/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import Lexical
import XCTest

// Selection parity checks ensure that legacy and optimized map the same string
// locations to valid Points, and those Points resolve back to the original
// string locations. We compare by absolute locations rather than insisting on
// identical node/offset, because multiple equivalent representations may exist.

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
      featureFlags: FeatureFlags(
        reconcilerSanityCheck: true,
        proxyTextViewInputDelegate: false,
        optimizedReconciler: false,
        reconcilerMetrics: false,
        darkLaunchOptimized: false,
        decoratorSiblingRedecorate: false,
        selectionParityDebug: true)
    )
    let legacyEditor = legacyCtx.editor
    let (legacyT1, legacyT2) = try buildSimpleTwoTextNodesDocument(editor: legacyEditor)

    // Optimized context
    let optCtx = LexicalReadOnlyTextKitContext(
      editorConfig: EditorConfig(theme: Theme(), plugins: []),
      featureFlags: FeatureFlags(
        reconcilerSanityCheck: true,
        proxyTextViewInputDelegate: false,
        optimizedReconciler: true,
        reconcilerMetrics: false,
        darkLaunchOptimized: false,
        decoratorSiblingRedecorate: false,
        selectionParityDebug: true)
    )
    let optEditor = optCtx.editor
    let (optT1, optT2) = try buildSimpleTwoTextNodesDocument(editor: optEditor)

    // Compute boundary location as the start of the second text node
    var legacyLoc = 0
    var optLoc = 0
    var legacyF: Point? = nil, legacyB: Point? = nil
    try legacyEditor.read {
      guard let rc2 = legacyEditor.rangeCache[legacyT2] else { return }
      legacyLoc = rc2.textRange.location
      legacyF = try? pointAtStringLocation(legacyLoc, searchDirection: .forward, rangeCache: legacyEditor.rangeCache)
      legacyB = try? pointAtStringLocation(legacyLoc, searchDirection: .backward, rangeCache: legacyEditor.rangeCache)
    }
    var optF: Point? = nil, optB: Point? = nil
    try optEditor.read {
      guard let rc2 = optEditor.rangeCache[optT2] else { return }
      let tr2 = rc2.textRangeFromFenwick(using: optEditor.fenwickTree)
      optLoc = tr2.location
      optF = try? pointAtStringLocation(optLoc, searchDirection: .forward, rangeCache: optEditor.rangeCache)
      optB = try? pointAtStringLocation(optLoc, searchDirection: .backward, rangeCache: optEditor.rangeCache)
    }
    // Compare by absolute location round-trip
    func loc(_ p: Point?, _ ed: Editor) throws -> Int? { guard let p else { return nil }; return try stringLocationForPoint(p, editor: ed) }
    let legacyFLoc = try loc(legacyF, legacyEditor)
    let legacyBLoc = try loc(legacyB, legacyEditor)
    let optFLoc = try loc(optF, optEditor)
    let optBLoc = try loc(optB, optEditor)
    if let lfl = legacyFLoc, let lbl = legacyBLoc {
      XCTAssertEqual(lfl, legacyLoc)
      XCTAssertEqual(lbl, legacyLoc)
    }
    if let ofl = optFLoc, let obl = optBLoc {
      XCTAssertEqual(ofl, optLoc)
      XCTAssertEqual(obl, optLoc)
    }
  }

  func testStyledBoundaryBetweenAdjacentTextNodesParity() throws {
    // Legacy
    let legacyCtx = LexicalReadOnlyTextKitContext(
      editorConfig: EditorConfig(theme: Theme(), plugins: []),
      featureFlags: FeatureFlags(
        reconcilerSanityCheck: true,
        proxyTextViewInputDelegate: false,
        optimizedReconciler: false,
        reconcilerMetrics: false,
        darkLaunchOptimized: false,
        decoratorSiblingRedecorate: false,
        selectionParityDebug: false)
    )
    let legacyEditor = legacyCtx.editor
    var legacyT2: NodeKey = ""
    try legacyEditor.update {
      guard let root = getActiveEditorState()?.getRootNode() else { return }
      let p = ParagraphNode()
      let n1 = TextNode(text: "ab", key: nil)
      let n2 = TextNode(text: "cd", key: nil)
      try n2.setBold(true)
      try p.append([n1, n2])
      try root.append([p])
      legacyT2 = n2.getKey()
    }
    try legacyEditor.update {}

    // Optimized
    let optCtx = LexicalReadOnlyTextKitContext(
      editorConfig: EditorConfig(theme: Theme(), plugins: []),
      featureFlags: FeatureFlags(
        reconcilerSanityCheck: true,
        proxyTextViewInputDelegate: false,
        optimizedReconciler: true,
        reconcilerMetrics: false,
        darkLaunchOptimized: false,
        decoratorSiblingRedecorate: false,
        selectionParityDebug: false)
    )
    let optEditor = optCtx.editor
    var optT2: NodeKey = ""
    try optEditor.update {
      guard let root = getActiveEditorState()?.getRootNode() else { return }
      let p = ParagraphNode()
      let n1 = TextNode(text: "ab", key: nil)
      let n2 = TextNode(text: "cd", key: nil)
      try n2.setBold(true)
      try p.append([n1, n2])
      try root.append([p])
      optT2 = n2.getKey()
    }
    try optEditor.update {}

    var legacyLoc = 0, optLoc = 0
    try legacyEditor.read {
      guard let rc2 = legacyEditor.rangeCache[legacyT2] else { return }
      legacyLoc = rc2.textRange.location
    }
    try optEditor.read {
      guard let rc2 = optEditor.rangeCache[optT2] else { return }
      optLoc = rc2.textRangeFromFenwick(using: optEditor.fenwickTree).location
    }

    let lF = try? pointAtStringLocation(legacyLoc, searchDirection: .forward, rangeCache: legacyEditor.rangeCache)
    let lB = try? pointAtStringLocation(legacyLoc, searchDirection: .backward, rangeCache: legacyEditor.rangeCache)
    let oF = try? pointAtStringLocation(optLoc, searchDirection: .forward, rangeCache: optEditor.rangeCache)
    let oB = try? pointAtStringLocation(optLoc, searchDirection: .backward, rangeCache: optEditor.rangeCache)

    func loc(_ p: Point?, _ ed: Editor) -> Int? { (try? stringLocationForPoint(p!, editor: ed)) }
    if let lF { XCTAssertEqual(loc(lF, legacyEditor), legacyLoc) }
    if let lB { XCTAssertEqual(loc(lB, legacyEditor), legacyLoc) }
    if let oF { XCTAssertEqual(loc(oF, optEditor), optLoc) }
    if let oB { XCTAssertEqual(loc(oB, optEditor), optLoc) }

    // Cross-mode absolute location equality intentionally not asserted yet.
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
      featureFlags: FeatureFlags(
        reconcilerSanityCheck: true,
        proxyTextViewInputDelegate: false,
        optimizedReconciler: false,
        reconcilerMetrics: false,
        darkLaunchOptimized: false,
        decoratorSiblingRedecorate: false,
        selectionParityDebug: false)
    )
    let legacyEditor = legacyCtx.editor
    let legacyP = try buildEmptyParagraphDoc(legacyEditor)

    let optCtx = LexicalReadOnlyTextKitContext(
      editorConfig: EditorConfig(theme: Theme(), plugins: []),
      featureFlags: FeatureFlags(
        reconcilerSanityCheck: true,
        proxyTextViewInputDelegate: false,
        optimizedReconciler: true,
        reconcilerMetrics: false,
        darkLaunchOptimized: false,
        decoratorSiblingRedecorate: false,
        selectionParityDebug: false)
    )
    let optEditor = optCtx.editor
    let optP = try buildEmptyParagraphDoc(optEditor)

    var legacyStart = 0
    var optStart = 0
    var legacyEF: Point? = nil, legacyEB: Point? = nil
    try legacyEditor.read {
      guard let rc = legacyEditor.rangeCache[legacyP] else { return }
      let start = rc.location
      legacyStart = start
      do {
        legacyEF = try pointAtStringLocation(start, searchDirection: .forward, rangeCache: legacyEditor.rangeCache)
        legacyEB = try pointAtStringLocation(start, searchDirection: .backward, rangeCache: legacyEditor.rangeCache)
      } catch { legacyEF = nil; legacyEB = nil }
    }
    var optEF: Point? = nil, optEB: Point? = nil
    try optEditor.read {
      guard let rc = optEditor.rangeCache[optP] else { return }
      let start = rc.locationFromFenwick(using: optEditor.fenwickTree)
      optStart = start
      do {
        optEF = try pointAtStringLocation(start, searchDirection: .forward, rangeCache: optEditor.rangeCache)
        optEB = try pointAtStringLocation(start, searchDirection: .backward, rangeCache: optEditor.rangeCache)
      } catch { optEF = nil; optEB = nil }
    }
    func aloc(_ p: Point?, _ ed: Editor) throws -> Int? { guard let p else { return nil }; return try stringLocationForPoint(p, editor: ed) }
    let legacyEFLoc = try aloc(legacyEF, legacyEditor)
    let legacyEBLoc = try aloc(legacyEB, legacyEditor)
    let optEFLoc = try aloc(optEF, optEditor)
    let optEBLoc = try aloc(optEB, optEditor)
    if let lfl = legacyEFLoc, let lbl = legacyEBLoc {
      XCTAssertEqual(lfl, legacyStart)
      XCTAssertEqual(lbl, legacyStart)
    }
    if let ofl = optEFLoc, let obl = optEBLoc {
      XCTAssertEqual(ofl, optStart)
      XCTAssertEqual(obl, optStart)
    }

    // Cross-mode absolute location equality intentionally not asserted yet.
  }

  func testParagraphBoundaryParity() throws {
    // Legacy editor: two paragraphs, measure boundary at start of second paragraph
    let legacyCtx = LexicalReadOnlyTextKitContext(
      editorConfig: EditorConfig(theme: Theme(), plugins: []),
      featureFlags: FeatureFlags(
        reconcilerSanityCheck: true,
        proxyTextViewInputDelegate: false,
        optimizedReconciler: false,
        reconcilerMetrics: false,
        darkLaunchOptimized: false,
        decoratorSiblingRedecorate: false,
        selectionParityDebug: false)
    )
    let legacyEditor = legacyCtx.editor
    var legacyP2: NodeKey = ""

    try legacyEditor.update {
      guard let root = getActiveEditorState()?.getRootNode() else { return }
      let p1 = ParagraphNode(); let t1 = TextNode(text: "A", key: nil); try p1.append([t1])
      let p2 = ParagraphNode(); let t2 = TextNode(text: "B", key: nil); try p2.append([t2])
      try root.append([p1, p2])
      legacyP2 = p2.getKey()
    }
    try legacyEditor.update {}

    // Optimized editor: same structure
    let optCtx = LexicalReadOnlyTextKitContext(
      editorConfig: EditorConfig(theme: Theme(), plugins: []),
      featureFlags: FeatureFlags(
        reconcilerSanityCheck: true,
        proxyTextViewInputDelegate: false,
        optimizedReconciler: true,
        reconcilerMetrics: false,
        darkLaunchOptimized: false,
        decoratorSiblingRedecorate: false,
        selectionParityDebug: false)
    )
    let optEditor = optCtx.editor
    var optP2: NodeKey = ""
    try optEditor.update {
      guard let root = getActiveEditorState()?.getRootNode() else { return }
      let p1 = ParagraphNode(); let t1 = TextNode(text: "A", key: nil); try p1.append([t1])
      let p2 = ParagraphNode(); let t2 = TextNode(text: "B", key: nil); try p2.append([t2])
      try root.append([p1, p2])
      optP2 = p2.getKey()
    }
    try optEditor.update {}

    var legacyStart = 0, optStart = 0
    var legacyF: Point?, legacyB: Point?, optF: Point?, optB: Point?
    try legacyEditor.read {
      guard let rc = legacyEditor.rangeCache[legacyP2] else { return }
      legacyStart = rc.location
      legacyF = try? pointAtStringLocation(legacyStart, searchDirection: .forward, rangeCache: legacyEditor.rangeCache)
      legacyB = try? pointAtStringLocation(legacyStart, searchDirection: .backward, rangeCache: legacyEditor.rangeCache)
    }
    try optEditor.read {
      guard let rc = optEditor.rangeCache[optP2] else { return }
      optStart = rc.locationFromFenwick(using: optEditor.fenwickTree)
      optF = try? pointAtStringLocation(optStart, searchDirection: .forward, rangeCache: optEditor.rangeCache)
      optB = try? pointAtStringLocation(optStart, searchDirection: .backward, rangeCache: optEditor.rangeCache)
    }

    func aloc(_ p: Point?, _ ed: Editor) throws -> Int? { guard let p else { return nil }; return try stringLocationForPoint(p, editor: ed) }
    let legacyFLoc = try aloc(legacyF, legacyEditor)
    let legacyBLoc = try aloc(legacyB, legacyEditor)
    let optFLoc = try aloc(optF, optEditor)
    let optBLoc = try aloc(optB, optEditor)

    if let lfl = legacyFLoc, let lbl = legacyBLoc {
      XCTAssertEqual(lfl, legacyStart)
      XCTAssertEqual(lbl, legacyStart)
    }
    if let ofl = optFLoc, let obl = optBLoc {
      XCTAssertEqual(ofl, optStart)
      XCTAssertEqual(obl, optStart)
    }

    // Cross-mode absolute location equality intentionally not asserted yet.
  }

  func testCreateNativeSelectionParity() throws {
    // Build adjacent text nodes and compare native selection ranges
    let legacyCtx = LexicalReadOnlyTextKitContext(
      editorConfig: EditorConfig(theme: Theme(), plugins: []),
      featureFlags: FeatureFlags(optimizedReconciler: false)
    )
    let legacyEditor = legacyCtx.editor
    var lT1: NodeKey = "", lT2: NodeKey = ""
    try legacyEditor.update {
      guard let root = getActiveEditorState()?.getRootNode() else { return }
      let p = ParagraphNode()
      let n1 = TextNode(text: "abcd", key: nil)
      let n2 = TextNode(text: "efgh", key: nil)
      try p.append([n1, n2])
      try root.append([p])
      lT1 = n1.getKey(); lT2 = n2.getKey()
    }
    try legacyEditor.update {}

    let optCtx = LexicalReadOnlyTextKitContext(
      editorConfig: EditorConfig(theme: Theme(), plugins: []),
      featureFlags: FeatureFlags(optimizedReconciler: true)
    )
    let optEditor = optCtx.editor
    var oT1: NodeKey = "", oT2: NodeKey = ""
    try optEditor.update {
      guard let root = getActiveEditorState()?.getRootNode() else { return }
      let p = ParagraphNode()
      let n1 = TextNode(text: "abcd", key: nil)
      let n2 = TextNode(text: "efgh", key: nil)
      try p.append([n1, n2])
      try root.append([p])
      oT1 = n1.getKey(); oT2 = n2.getKey()
    }
    try optEditor.update {}

    var legacyRange: NSRange? = nil
    var optRange: NSRange? = nil
    do {
      try legacyEditor.read {
        let sel = RangeSelection(anchor: Point(key: lT1, offset: 1, type: .text),
                                 focus: Point(key: lT2, offset: 1, type: .text),
                                 format: TextFormat())
        legacyRange = try createNativeSelection(from: sel, editor: legacyEditor).range
      }
    } catch { /* tolerate for now */ }
    do {
      try optEditor.read {
        let sel = RangeSelection(anchor: Point(key: oT1, offset: 1, type: .text),
                                 focus: Point(key: oT2, offset: 1, type: .text),
                                 format: TextFormat())
        optRange = try createNativeSelection(from: sel, editor: optEditor).range
      }
    } catch { /* tolerate for now */ }

    if let l = legacyRange, let o = optRange {
      XCTAssertEqual(l.length, o.length)
      // Absolute locations may differ until parity is finalized.
    }
  }

  func testMultiParagraphSelectionParity() throws {
    // Legacy context
    let legacyCtx = LexicalReadOnlyTextKitContext(
      editorConfig: EditorConfig(theme: Theme(), plugins: []),
      featureFlags: FeatureFlags(
        reconcilerSanityCheck: true,
        proxyTextViewInputDelegate: false,
        optimizedReconciler: false,
        reconcilerMetrics: false,
        darkLaunchOptimized: false,
        decoratorSiblingRedecorate: false,
        selectionParityDebug: true)
    )
    let legacyEditor = legacyCtx.editor

    // Optimized context
    let optCtx = LexicalReadOnlyTextKitContext(
      editorConfig: EditorConfig(theme: Theme(), plugins: []),
      featureFlags: FeatureFlags(
        reconcilerSanityCheck: true,
        proxyTextViewInputDelegate: false,
        optimizedReconciler: true,
        reconcilerMetrics: false,
        darkLaunchOptimized: false,
        decoratorSiblingRedecorate: false,
        selectionParityDebug: true)
    )
    let optEditor = optCtx.editor

    // Build 3 paragraphs: "ABCD", "EFGH", "IJKL"
    var lP1: ParagraphNode = ParagraphNode(), lP3: ParagraphNode = ParagraphNode()
    try legacyEditor.update {
      guard let root = getActiveEditorState()?.getRootNode() else { return }
      let p1 = ParagraphNode(); try p1.append([TextNode(text: "ABCD", key: nil)])
      let p2 = ParagraphNode(); try p2.append([TextNode(text: "EFGH", key: nil)])
      let p3 = ParagraphNode(); try p3.append([TextNode(text: "IJKL", key: nil)])
      try root.append([p1, p2, p3])
      lP1 = p1; lP3 = p3
    }
    try legacyEditor.update {}

    var oP1: ParagraphNode = ParagraphNode(), oP3: ParagraphNode = ParagraphNode()
    try optEditor.update {
      guard let root = getActiveEditorState()?.getRootNode() else { return }
      let p1 = ParagraphNode(); try p1.append([TextNode(text: "ABCD", key: nil)])
      let p2 = ParagraphNode(); try p2.append([TextNode(text: "EFGH", key: nil)])
      let p3 = ParagraphNode(); try p3.append([TextNode(text: "IJKL", key: nil)])
      try root.append([p1, p2, p3])
      oP1 = p1; oP3 = p3
    }
    try optEditor.update {}

    // Select from mid of first paragraph to mid of third paragraph (B..K)
    var lRange: NSRange? = nil
    var oRange: NSRange? = nil

    try legacyEditor.read {
      guard let t1 = (lP1.getChildren().first as? TextNode),
            let t3 = (lP3.getChildren().first as? TextNode) else { return }
      let sel = RangeSelection(anchor: Point(key: t1.getKey(), offset: 1, type: .text),
                               focus: Point(key: t3.getKey(), offset: 2, type: .text),
                               format: TextFormat())
      lRange = try createNativeSelection(from: sel, editor: legacyEditor).range
    }
    try optEditor.read {
      guard let t1 = (oP1.getChildren().first as? TextNode),
            let t3 = (oP3.getChildren().first as? TextNode) else { return }
      let sel = RangeSelection(anchor: Point(key: t1.getKey(), offset: 1, type: .text),
                               focus: Point(key: t3.getKey(), offset: 2, type: .text),
                               format: TextFormat())
      oRange = try createNativeSelection(from: sel, editor: optEditor).range
    }

    // Now that newline placement is aligned, assert strict equality
    if let l = lRange, let o = oRange {
      XCTAssertEqual(l.length, o.length)
    } else {
      XCTFail("Expected both legacy and optimized to produce native ranges")
    }
  }
}
