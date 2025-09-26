import XCTest
@testable import Lexical

@MainActor
final class SelectionStabilityLargeUnrelatedEditsTests: XCTestCase {

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
        try p.append([ createTextNode(text: "Line \(i)") ])
        nodes.append(p)
      }
      try root.append(nodes)
    }
  }

  func testSelectionStableUnderUnrelatedLargeEdits() throws {
    let (opt, leg) = makeEditors()
    try buildLargeDoc(on: opt.0, paragraphs: 200)
    try buildLargeDoc(on: leg.0, paragraphs: 200)

    func placeCaretInEarlyParagraph(_ editor: Editor) throws -> Int {
      var baselineLoc: Int = -1
      try editor.update {
        guard let root = getRoot(), let p = root.getChildren()[safe: 10] as? ParagraphNode, let t = p.getFirstChild() as? TextNode else { return }
        if let point = try? stringToPoint(node: t, offset: 3) {
          try setSelection(point, point)
          baselineLoc = try stringLocationForPoint(point, editor: editor) ?? -1
        }
      }
      return baselineLoc
    }
    let baseOpt = try placeCaretInEarlyParagraph(opt.0)
    let baseLeg = try placeCaretInEarlyParagraph(leg.0)
    XCTAssertEqual(baseOpt, baseLeg)

    // Apply unrelated edits to the tail half: toggle bold and append text
    func unrelatedEdits(_ editor: Editor) throws {
      try editor.update {
        guard let root = getRoot() else { return }
        for (idx, node) in root.getChildren().enumerated() where idx >= 120 {
          if let p = node as? ParagraphNode, let t = p.getFirstChild() as? TextNode {
            try t.setBold(true)
            try t.setText(t.getTextPart() + "!")
          }
        }
        let newP = createParagraphNode(); try newP.append([ createTextNode(text: "TAIL") ]); try root.append([newP])
      }
    }
    try unrelatedEdits(opt.0)
    try unrelatedEdits(leg.0)

    func currentCaretLoc(_ editor: Editor) throws -> Int {
      var loc: Int = -1
      try editor.read {
        guard let sel = try getSelection() as? RangeSelection else { return }
        loc = try stringLocationForPoint(sel.anchor, editor: editor) ?? -1
      }
      return loc
    }

    let nowOpt = try currentCaretLoc(opt.0)
    let nowLeg = try currentCaretLoc(leg.0)
    XCTAssertEqual(nowOpt, baseOpt)
    XCTAssertEqual(nowLeg, baseLeg)
    XCTAssertEqual(nowOpt, nowLeg)
  }
}

private extension Array {
  subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}

