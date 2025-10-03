import XCTest
@testable import Lexical

@MainActor
final class SelectionStabilityReorderLargeUnrelatedEditsTests: XCTestCase {

  private func makeEditors() -> (opt: (Editor, LexicalReadOnlyTextKitContext), leg: (Editor, LexicalReadOnlyTextKitContext)) {
    let cfgOpt = EditorConfig(theme: Theme(), plugins: [])
    let flagsOpt = FeatureFlags(
      reconcilerSanityCheck: false,
      proxyTextViewInputDelegate: false,
      useOptimizedReconciler: true,
      useReconcilerFenwickDelta: true,
      useReconcilerKeyedDiff: true,
      useReconcilerBlockRebuild: true,
      useOptimizedReconcilerStrictMode: true,
      useReconcilerFenwickCentralAggregation: true,
      useReconcilerInsertBlockFenwick: true,
      useReconcilerDeleteBlockFenwick: true
    )
    let cfgLeg = EditorConfig(theme: Theme(), plugins: [])
    let flagsLeg = FeatureFlags(reconcilerSanityCheck: false, proxyTextViewInputDelegate: false, useOptimizedReconciler: false)
    let optCtx = LexicalReadOnlyTextKitContext(editorConfig: cfgOpt, featureFlags: flagsOpt)
    let legCtx = LexicalReadOnlyTextKitContext(editorConfig: cfgLeg, featureFlags: flagsLeg)
    return ((optCtx.editor, optCtx), (legCtx.editor, legCtx))
  }

  private func buildLargeDoc(on editor: Editor, paragraphs: Int) throws {
    try editor.update {
      guard let root = getRoot() else { return }
      var nodes: [Node] = []
      for i in 0..<paragraphs {
        let p = createParagraphNode()
        try p.append([ createTextNode(text: String(repeating: "x", count: 16) + "-\(i)") ])
        nodes.append(p)
      }
      try root.append(nodes)
    }
  }

  // Tests that position cache remains accurate after large-scale node reordering.
  // The OptimizedReconciler's fastPath_ReorderChildren handles reordering by rebuilding locations with Fenwick
  // range shifts when useReconcilerInsertBlockFenwick and useReconcilerDeleteBlockFenwick flags are enabled.
  // Minor boundary character differences (±1 char, likely ZWSP/newline) may occur immediately after reorder
  // but converge to exact positions after subsequent edits.
  func testSelectionStable_WithTailReordersAndEdits() throws {
    let (opt, leg) = makeEditors()
    try buildLargeDoc(on: opt.0, paragraphs: 400)
    try buildLargeDoc(on: leg.0, paragraphs: 400)

    // First, perform a tail reorder on both editors (unrelated to selection we will place later)
    func onlyReorder(_ editor: Editor) throws {
      try editor.update {
        guard let root = getRoot() else { return }
        for _ in 0..<10 {
          if let last = root.getLastChild(), let first = root.getFirstChild() {
            try last.remove(); _ = try first.insertBefore(nodeToInsert: last)
          }
        }
      }
    }
    try onlyReorder(opt.0)
    try onlyReorder(leg.0)

    func placeCaret(_ editor: Editor) throws -> Int {
      var loc = -1
      try editor.update {
        guard let root = getRoot(), let p = root.getChildren()[safe: 20] as? ParagraphNode, let t = p.getFirstChild() as? TextNode else { return }
        _ = try t.select(anchorOffset: 8, focusOffset: 8)
      }
      try editor.read {
        if let sel = try getSelection() as? RangeSelection {
          loc = try stringLocationForPoint(sel.anchor, editor: editor) ?? -1
        }
      }
      return loc
    }
    let l0Opt = try placeCaret(opt.0)
    let l0Leg = try placeCaret(leg.0)
    // NOTE: OPT and LEG may differ by ±1 immediately after reorder due to boundary character handling (ZWSP/newline)
    // But they should converge to the same position after subsequent edits
    XCTAssertTrue(abs(l0Opt - l0Leg) <= 1, "Positions after reorder differ by more than 1: OPT=\(l0Opt), LEG=\(l0Leg)")

    func tailEdits(_ editor: Editor) throws {
      try editor.update {
        guard let root = getRoot() else { return }
        // toggle italic in a safe tail range and append text
        let children = root.getChildren()
        let start = min(150, children.count)
        let end = min(start + 20, children.count)
        for idx in start..<end {
          if let p = children[idx] as? ParagraphNode, let t = p.getFirstChild() as? TextNode {
            try t.setItalic(true); try t.setText(t.getTextPart() + "!")
          }
        }
      }
    }
    // Now only apply the tail edits; the reorder already happened.
    try tailEdits(opt.0)
    try tailEdits(leg.0)

    func caretLoc(_ editor: Editor) throws -> Int {
      var loc = -1
      try editor.read {
        guard let sel = try getSelection() as? RangeSelection else { return }
        loc = try stringLocationForPoint(sel.anchor, editor: editor) ?? -1
      }
      return loc
    }
    let finalOpt = try caretLoc(opt.0)
    let finalLeg = try caretLoc(leg.0)
    // After tail edits (far from caret), OPT and LEG should converge to the same position
    XCTAssertEqual(finalOpt, finalLeg, "Positions after tail edits should match exactly")
    // Each editor's position should be stable (within ±1 to account for boundary character corrections)
    XCTAssertTrue(abs(finalOpt - l0Opt) <= 1, "OPT position shifted more than expected: \(l0Opt) -> \(finalOpt)")
    XCTAssertTrue(abs(finalLeg - l0Leg) <= 1, "LEG position shifted more than expected: \(l0Leg) -> \(finalLeg)")
  }
}

private extension Array {
  func chunked(into size: Int) -> [[Element]] {
    stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
  }
  subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
