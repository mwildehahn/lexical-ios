import XCTest
@testable import Lexical

@MainActor
final class OptimizedReconcilerLegacyParityMixedParentsComplexTests: XCTestCase {

  private func makeEditors() -> (opt: (Editor, LexicalReadOnlyTextKitContext), leg: (Editor, LexicalReadOnlyTextKitContext)) {
    let cfg = EditorConfig(theme: Theme(), plugins: [])
    let optFlags = FeatureFlags(
      reconcilerSanityCheck: false,
      proxyTextViewInputDelegate: false,
      useOptimizedReconciler: true,
      useReconcilerFenwickDelta: true,
      useReconcilerKeyedDiff: true,
      useReconcilerBlockRebuild: true,
      useOptimizedReconcilerStrictMode: true,
      useReconcilerFenwickCentralAggregation: true
    )
    let legFlags = FeatureFlags(
      reconcilerSanityCheck: false,
      proxyTextViewInputDelegate: false,
      useOptimizedReconciler: false
    )
    let optCtx = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: optFlags)
    let legCtx = LexicalReadOnlyTextKitContext(editorConfig: cfg, featureFlags: legFlags)
    return ((optCtx.editor, optCtx), (legCtx.editor, legCtx))
  }

  func testMixedParents_ReorderInA_InsertInB_TextEditInA_Parity() throws {
    let (opt, leg) = makeEditors()

    func build(on editor: Editor) throws -> (NodeKey, NodeKey) {
      var aKey: NodeKey = ""; var bKey: NodeKey = ""
      try editor.update {
        guard let root = getRoot() else { return }
        let a = createParagraphNode(); aKey = a.getKey(); try a.append([ createTextNode(text: "A1"), createTextNode(text: "A2") ])
        let b = createParagraphNode(); bKey = b.getKey(); try b.append([ createTextNode(text: "B1") ])
        try root.append([a, b])
      }
      return (aKey, bKey)
    }
    let (ao, bo) = try build(on: opt.0)
    let (al, bl) = try build(on: leg.0)

    // Single update on both editors:
    // - Reorder children within A (swap A1/A2)
    // - Insert new paragraph C("C1") after B
    // - Edit text of A1 (after swap, becomes second)
    func apply(on editor: Editor, a: NodeKey, b: NodeKey) throws {
      try editor.update {
        guard let aNode = getNodeByKey(key: a) as? ParagraphNode,
              let root = getRoot() else { return }
        let children = aNode.getChildren()
        if children.count >= 2 {
          if let n0 = children.first, let n1 = children.dropFirst().first {
            _ = try n0.insertBefore(nodeToInsert: n1)
          }
        }
        let c = createParagraphNode(); try c.append([ createTextNode(text: "C1") ])
        try root.append([c])
        if let t = (aNode.getChildren().last as? TextNode) {
          t.setText_dangerousPropertyAccess("AX")
        }
      }
    }
    try apply(on: opt.0, a: ao, b: bo)
    try apply(on: leg.0, a: al, b: bl)

    XCTAssertEqual(opt.1.textStorage.string, leg.1.textStorage.string)
  }
}
