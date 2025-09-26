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
      useReconcilerFenwickCentralAggregation: true
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

  func testSelectionStable_WithTailReordersAndEdits() throws {
    let (opt, leg) = makeEditors()
    try buildLargeDoc(on: opt.0, paragraphs: 400)
    try buildLargeDoc(on: leg.0, paragraphs: 400)

    func placeCaret(_ editor: Editor) throws -> Int {
      var loc = -1
      try editor.update {
        guard let root = getRoot(), let p = root.getChildren()[safe: 20] as? ParagraphNode, let t = p.getFirstChild() as? TextNode else { return }
        if let point = try? stringToPoint(node: t, offset: 8) { try setSelection(point, point); loc = try stringLocationForPoint(point, editor: editor) ?? -1 }
      }
      return loc
    }
    let l0Opt = try placeCaret(opt.0)
    let l0Leg = try placeCaret(leg.0)
    XCTAssertEqual(l0Opt, l0Leg)

    func tailReorderAndEdits(_ editor: Editor) throws {
      try editor.update {
        guard let root = getRoot() else { return }
        let cs = root.getChildren()
        // move last 50 paragraphs to front in blocks of 5
        for group in cs.suffix(50).chunked(into: 5).reversed() {
          for node in group { try node.remove(); _ = try cs.first?.insertBefore(nodeToInsert: node) }
        }
        // toggle italic in paragraphs 300..350 and append text
        for (idx, node) in root.getChildren().enumerated() where (300..<350).contains(idx) {
          if let p = node as? ParagraphNode, let t = p.getFirstChild() as? TextNode {
            try t.setItalic(true); try t.setText(t.getTextPart() + "!")
          }
        }
      }
    }
    try tailReorderAndEdits(opt.0)
    try tailReorderAndEdits(leg.0)

    func caretLoc(_ editor: Editor) throws -> Int {
      var loc = -1
      try editor.read {
        guard let sel = try getSelection() as? RangeSelection else { return }
        loc = try stringLocationForPoint(sel.anchor, editor: editor) ?? -1
      }
      return loc
    }
    XCTAssertEqual(try caretLoc(opt.0), l0Opt)
    XCTAssertEqual(try caretLoc(leg.0), l0Leg)
    XCTAssertEqual(try caretLoc(opt.0), try caretLoc(leg.0))
  }
}

private extension Array {
  func chunked(into size: Int) -> [[Element]] {
    stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
  }
  subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

