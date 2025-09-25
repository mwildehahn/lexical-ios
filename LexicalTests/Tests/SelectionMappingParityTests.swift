import XCTest
@testable import Lexical

@MainActor
final class SelectionMappingParityTests: XCTestCase {

  private func makeEditors() -> (opt: (Editor, LexicalReadOnlyTextKitContext), leg: (Editor, LexicalReadOnlyTextKitContext)) {
    let theme = Theme(); let cfg = EditorConfig(theme: theme, plugins: [])
    let optFlags = FeatureFlags(
      reconcilerSanityCheck: false, proxyTextViewInputDelegate: false,
      useOptimizedReconciler: true, useReconcilerFenwickDelta: true,
      useReconcilerKeyedDiff: true, useReconcilerBlockRebuild: true,
      useOptimizedReconcilerStrictMode: true,
      useReconcilerFenwickCentralAggregation: true
    )
    let legFlags = FeatureFlags(reconcilerSanityCheck: false, proxyTextViewInputDelegate: false, useOptimizedReconciler: false)
    let optCtx = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: optFlags)
    let legCtx = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: legFlags)
    return ((optCtx.editor, optCtx), (legCtx.editor, legCtx))
  }

  func testCaretStabilityOnUnrelatedSiblingEdit_Parity() throws {
    let (opt, leg) = makeEditors()

    // Build: Root -> [ P1("Hello"), P2("World") ] and place caret at end of "Hello"
    func buildAndPlaceCaret(on editor: Editor) throws -> (NodeKey, NodeKey) {
      var helloKey: NodeKey = ""; var worldKey: NodeKey = ""
      try editor.update {
        guard let root = getRoot() else { return }
        let p1 = createParagraphNode(); let p2 = createParagraphNode()
        let t1 = createTextNode(text: "Hello"); helloKey = t1.getKey()
        let t2 = createTextNode(text: "World"); worldKey = t2.getKey()
        try p1.append([t1]); try p2.append([t2]); try root.append([p1, p2])
        _ = try t1.select(anchorOffset: nil, focusOffset: nil) // caret at end of "Hello"
      }
      return (helloKey, worldKey)
    }
    let (hOpt, wOpt) = try buildAndPlaceCaret(on: opt.0)
    let (hLeg, wLeg) = try buildAndPlaceCaret(on: leg.0)

    // Edit the sibling paragraph only: change "World" -> "Earth"
    try opt.0.update {
      guard let t2 = (getNodeByKey(key: wOpt) as? TextNode) else { return }
      try t2.setText("Earth")
    }
    try leg.0.update {
      guard let t2 = (getNodeByKey(key: wLeg) as? TextNode) else { return }
      try t2.setText("Earth")
    }

    // Verify selection remains at end of first text in both editors
    var optAnchor: (NodeKey, Int, SelectionType) = ("", -1, .text)
    var legAnchor: (NodeKey, Int, SelectionType) = ("", -1, .text)
    try opt.0.update {
      guard let sel = try getSelection() as? RangeSelection else { return }
      optAnchor = (sel.anchor.key, sel.anchor.offset, sel.anchor.type)
    }
    try leg.0.update {
      guard let sel = try getSelection() as? RangeSelection else { return }
      legAnchor = (sel.anchor.key, sel.anchor.offset, sel.anchor.type)
    }

    XCTAssertEqual(optAnchor.2, .text)
    XCTAssertEqual(legAnchor.2, .text)
    XCTAssertEqual(optAnchor.0, hOpt)
    XCTAssertEqual(legAnchor.0, hLeg)
    XCTAssertEqual(optAnchor.1, 5) // "Hello" length
    XCTAssertEqual(legAnchor.1, 5)

    // Ensure any pending UI sync completed
    try opt.0.update {}
    try leg.0.update {}
    // Final rendered strings must match
    XCTAssertEqual(opt.1.textStorage.string, leg.1.textStorage.string)
  }

  func testCrossNodeReplaceSelectionParity() throws {
    let (opt, leg) = makeEditors()
    // Build: Root -> [ P("Hello","World") ]
    func build(on editor: Editor) throws -> (NodeKey, NodeKey) {
      var aKey: NodeKey = ""; var bKey: NodeKey = ""
      try editor.update {
        guard let root = getRoot() else { return }
        let p = createParagraphNode()
        let a = createTextNode(text: "Hello"); aKey = a.getKey()
        let b = createTextNode(text: "World"); bKey = b.getKey()
        try p.append([a, b]); try root.append([p])
      }
      return (aKey, bKey)
    }
    let (aOpt, bOpt) = try build(on: opt.0)
    let (aLeg, bLeg) = try build(on: leg.0)

    func replaceAcross(on editor: Editor, a: NodeKey, b: NodeKey) throws {
      try editor.update {
        guard let ta = getNodeByKey(key: a) as? TextNode,
              let tb = getNodeByKey(key: b) as? TextNode else { return }
        // Select from A offset 2 to B offset 3 and replace with "X"
        var sel = try getSelection() as? RangeSelection ?? createEmptyRangeSelection()
        sel.anchor.updatePoint(key: ta.getKey(), offset: 2, type: .text)
        sel.focus.updatePoint(key: tb.getKey(), offset: 3, type: .text)
        sel.dirty = true
        try sel.insertText("X")
      }
    }

    try replaceAcross(on: opt.0, a: aOpt, b: bOpt)
    try replaceAcross(on: leg.0, a: aLeg, b: bLeg)

    XCTAssertEqual(opt.1.textStorage.string, leg.1.textStorage.string)
  }
}
